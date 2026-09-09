import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_package.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_validator.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/config_parser.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/script_merger.dart';
import 'package:sakiengine/src/sks_compiler/compiled_sks_registry.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';
import 'package:sakiengine/src/utils/animation_manager.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';

const fixture = 'test/fixtures/yuyu/sequence.yuyu';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async {
    await YuyuPackage.active?.close();
    clearRuntimeProjectConfig();
    CharacterLayerParser.clearCache();
    AnimationManager.clearCache();
    ScriptMerger().clearCache();
  });

  test(
    'same source package validates, resolves aliases, and cleans its mount',
    () async {
      final package = await YuyuPackage.open(fixture);
      final directory = package.directory;
      final report = await validateYuyuPackage(package);
      expect(report['nodes'], 16);
      expect(report['animations'], 1);
      expect(package.entryFile('game/story.rpy'), isNotNull);
      expect(package.listFiles('assets/GameScript/labels/', '.sks'), [
        'start.sks',
      ]);
      expect(
        await package.loadText('assets/GameScript/labels/start.sks'),
        contains('这是兼容验证。'),
      );
      expect(package.resolveAsset('missing'), isNull);
      await package.close();
      expect(await directory.exists(), isFalse);
    },
  );

  test(
    'package assets and scripts override bundled content and layers never fall back',
    () async {
      final package = YuyuPackage.active = await YuyuPackage.open(fixture);
      configureRuntimeProject(
        projectName: package.gameId,
        packageDigest: package.digest,
      );
      expect(CompiledSksRegistry.instance.activeBundle, isNull);
      final merged = await ScriptMerger().getMergedScript();
      expect(merged.children.whereType<SayNode>().map((v) => v.dialogue), [
        '这是兼容验证。',
        '完成。',
      ]);
      final show = merged.children.whereType<ShowNode>().single;
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: show.character,
        pose: show.pose!,
        expression: show.expression!,
      );
      expect(layers, hasLength(1));
      expect(
        await File(
          (await AssetManager().findAsset(layers.single.assetName))!,
        ).exists(),
        isTrue,
      );
      await expectLater(
        CharacterLayerParser.parseCharacterLayers(
          resourceId: show.character,
          pose: 'missing',
          expression: '__none',
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets('mapped story runs through the existing GameManager', (
    tester,
  ) async {
    final parser = ConfigParser();
    final manager = GameManager();
    addTearDown(manager.dispose);
    late ScriptNode script;
    await tester.runAsync(() async {
      final package = YuyuPackage.active = await YuyuPackage.open(fixture);
      configureRuntimeProject(
        projectName: package.gameId,
        packageDigest: package.digest,
      );
      manager.characterConfigs.addAll(
        parser.parseCharacters(
          await package.loadText('GameScript/configs/characters.sks'),
        ),
      );
      manager.poseConfigs.addAll(
        parser.parsePoses(
          await package.loadText('GameScript/configs/poses.sks'),
        ),
      );
      AnimationManager.loadAnimationsFromStringForTesting(
        await package.loadText('GameScript/configs/animation.sks'),
      );
      script = SksParser().parse(
        await package.loadText('GameScript/labels/start.sks'),
      );
    });
    late BuildContext context;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    manager.setContext(context, const TestVSync());
    await tester.runAsync(() async {
      final dialogue = manager.gameStateStream.firstWhere(
        (state) => state.dialogue != null,
      );
      await manager.startTestScript(script);
      await dialogue.timeout(const Duration(seconds: 5));
    });
    await tester.pump();
    expect(manager.currentState.dialogue, '这是兼容验证。');
    expect(manager.currentState.speaker, '测试');
    expect(manager.currentState.currentNode, isNot(isA<MenuNode>()));
    expect(manager.currentState.characters, hasLength(1));
    await tester.pump(const Duration(milliseconds: 100));
    manager.dispose();
    await tester.runAsync(() async {
      await YuyuPackage.active?.close();
    });
  });

  test(
    'tampered, incomplete, traversal, duplicate and oversized packages fail',
    () async {
      final directory = await Directory.systemTemp.createTemp('yuyu-invalid-');
      addTearDown(() => directory.delete(recursive: true));
      final original = ZipDecoder().decodeBytes(
        await File(fixture).readAsBytes(),
      );
      Future<String> mutation(
        String name,
        void Function(Archive) change,
      ) async {
        final archive = Archive();
        for (final entry in original) {
          archive.add(ArchiveFile.bytes(entry.name, entry.content));
        }
        change(archive);
        final file = File('${directory.path}/$name.yuyu');
        await file.writeAsBytes(ZipEncoder().encode(archive));
        return file.path;
      }

      final badHash = await mutation('hash', (archive) {
        final entry = archive.find('game/story.rpy')!;
        archive.add(ArchiveFile.bytes(entry.name, List.filled(entry.size, 0)));
      });
      await expectLater(YuyuPackage.open(badHash), throwsFormatException);
      final incomplete = await mutation('incomplete', (archive) {
        final manifest = jsonDecode(
          utf8.decode(archive.find('manifest.json')!.content),
        );
        manifest['compatibility']['status'] = 'incomplete';
        archive.add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
      });
      await expectLater(
        YuyuPackage.open(incomplete, forValidation: true),
        throwsFormatException,
      );
      for (final status in ['incomplete', 'not-validated']) {
        final native = await mutation('native-$status', (archive) {
          final manifest = jsonDecode(
            utf8.decode(archive.find('manifest.json')!.content),
          );
          manifest['compatibility']['status'] = status;
          manifest['compatibility']['publicationTarget'] = 'yuyuball';
          archive.add(
            ArchiveFile.string('manifest.json', jsonEncode(manifest)),
          );
        });
        for (final validation in [false, true]) {
          await expectLater(
            YuyuPackage.open(native, forValidation: validation),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains('请使用 YuYuball 运行'),
              ),
            ),
          );
        }
      }
      final traversal = await mutation(
        'traversal',
        (archive) => archive.add(ArchiveFile.string('../outside', 'x')),
      );
      await expectLater(YuyuPackage.open(traversal), throwsFormatException);
      final duplicate = await mutation(
        'duplicate',
        (archive) => archive.add(ArchiveFile.string('GAME/story.rpy', 'x')),
      );
      await expectLater(YuyuPackage.open(duplicate), throwsFormatException);
      await expectLater(
        YuyuPackage.open(fixture, maxEntryBytes: 1),
        throwsFormatException,
      );
      for (final name in [
        '../file',
        '/absolute',
        r'a\b',
        'a:stream',
        'nul.txt',
      ]) {
        expect(() => YuyuPackage.validatePath(name), throwsFormatException);
      }
    },
  );
}
