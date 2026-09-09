import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_package.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_layers.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_validator.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_game_module.dart';
import 'package:sakiengine/src/config/config_parser.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/rendering/character_layer_blend.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';
import 'package:sakiengine/src/utils/animation_manager.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/src/utils/character_composite_cache.dart';
import 'package:sakiengine/src/widgets/dialogue_box.dart';

const fixture = 'test/fixtures/yuyu/layered.yuyu';

String request(YuyuLayerMapping mapping, List<String> attributes) => mapping
    .requests
    .entries
    .firstWhere(
      (e) => jsonEncode(e.value['attributes']) == jsonEncode(attributes),
    )
    .key;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    clearRuntimeProjectConfig();
    CharacterLayerParser.clearCache();
    AnimationManager.clearCache();
  });

  test(
    'exclusive attributes inherit across branches and defaults stay implicit',
    () async {
      final package = await YuyuPackage.open(fixture);
      addTearDown(package.close);
      expect((await validateYuyuPackage(package))['nodes'], 20);
      final mapping = await package.layerMapping;
      final first = mapping.resolvePose(
        request(mapping, ['shirt', 'dusk']),
        null,
      );
      final sad = mapping.resolvePose(request(mapping, ['sad']), first);
      final smile = mapping.resolvePose(request(mapping, ['smile']), first);
      expect(sad, isNot(smile));
      for (final pose in [sad, smile]) {
        final layers = mapping.layersFor('e:$pose:__none');
        expect(layers, hasLength(3));
        expect(layers.first['assetName'], contains('shirt'));
        expect(layers.last['blend'], 'multiplyPreserveAlpha');
      }
      final removed = mapping.resolvePose(request(mapping, ['-dusk']), sad);
      expect(mapping.layersFor('e:$removed:__none'), hasLength(2));
      final reset = mapping.resolvePose(request(mapping, []), null);
      final layers = mapping.layersFor('e:$reset:__none');
      expect(layers, hasLength(2));
      expect(layers.first['assetName'], contains('base'));
      expect(layers.last['assetName'], contains('smile'));
      // No explicit defaults are recorded, matching Ren'Py's image attributes.
      final state = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(
              reset.substring(YuyuLayerMapping.statePrefix.length),
            ),
          ),
        ),
      );
      expect(state[1], isEmpty);
    },
  );

  test(
    'validator rejects malformed layer rules, capabilities and character defaults',
    () async {
      final package = await YuyuPackage.open(fixture);
      addTearDown(package.close);
      final file = package.entryFile('mappings/layers.json')!;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final model = (data['models'] as Map).values.first;
      model['layers'][0]['blend'] = 'screen';
      expect(() => YuyuLayerMapping(data), throwsFormatException);
      final capabilities =
          (package.manifest['compatibility'] as Map)['requiredCapabilities']
              as List;
      capabilities.remove('sks.layers.yuyuball-attributes@1');
      await expectLater(validateYuyuPackage(package), throwsFormatException);
    },
  );

  test(
    'Character color reaches native dialogue without an implicit sprite show',
    () async {
      final package = await YuyuPackage.open(fixture);
      addTearDown(package.close);
      final alias = package.speakerMapping.keys.single;
      final configs = ConfigParser().parseCharacters(
        await package.loadText('GameScript/configs/characters.sks'),
      );
      expect(configs[alias]!.name, 'Layer fixture');
      expect(configs[alias]!.resourceId, 'narrator');
      final box =
          YuyuGameModule(package).createDialogueBox(
                speaker: 'Layer fixture',
                speakerAlias: alias,
                dialogue: 'hello',
                isFastForwarding: false,
                scriptIndex: 0,
              )
              as DialogueBox;
      expect(box.speakerColor, const Color(0xaad7c3ff));
    },
  );

  test(
    'multiply preserves destination alpha and matches the source GL equation',
    () async {
      Future<ui.Image> solid(ui.Color color) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 1, 1),
          ui.Paint()..color = color,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 1);
        picture.dispose();
        return image;
      }

      final base = await solid(const ui.Color.fromARGB(128, 100, 200, 60));
      final filter = await solid(const ui.Color.fromARGB(110, 180, 110, 160));
      addTearDown(base.dispose);
      addTearDown(filter.dispose);
      final dst = (await base.toByteData())!.buffer.asUint8List();
      final src = (await filter.toByteData())!.buffer.asUint8List();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImage(base, ui.Offset.zero, ui.Paint());
      drawCharacterLayerImage(
        canvas,
        filter,
        ui.Paint(),
        'multiplyPreserveAlpha',
      );
      final picture = recorder.endRecording();
      final result = await picture.toImage(2, 1);
      picture.dispose();
      addTearDown(result.dispose);
      final actual = (await result.toByteData())!.buffer.asUint8List();
      for (var channel = 0; channel < 3; channel++) {
        expect(
          actual[channel],
          closeTo(dst[channel] * (src[channel] / 255 + 1 - src[3] / 255), 1.1),
        );
      }
      expect(actual[3], dst[3]);
      expect(actual.sublist(4), [0, 0, 0, 0]);
    },
  );

  test(
    'package layer mapping reaches the existing character compositor',
    () async {
      final package = YuyuPackage.active = await YuyuPackage.open(fixture);
      addTearDown(() async {
        CharacterCompositeCache.instance.clear();
        await package.close();
      });
      final mapping = await package.layerMapping;
      final pose = mapping.resolvePose(
        request(mapping, ['shirt', 'dusk']),
        null,
      );
      final layers = await CharacterLayerParser.parseCharacterLayers(
        resourceId: 'e',
        pose: pose,
        expression: '__none',
      );
      expect(layers.last.blend, 'multiplyPreserveAlpha');
      final image = await CharacterCompositeCache.instance.preload(
        'e',
        pose,
        '__none',
      );
      expect(image, isNotNull);
      expect([image!.width, image.height], [16, 32]);
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      expect(rgba[3], 128);
      // The shirt is (200,100,30,128); the filter is (180,110,160,110).
      for (var i = 0; i < 3; i++) {
        final expected =
            [200, 100, 30][i] *
            128 /
            255 *
            ([180, 110, 160][i] / 255 * 110 / 255 + 1 - 110 / 255);
        expect(rgba[i], closeTo(expected, 1.5));
      }
    },
  );

  testWidgets(
    'mapped show inherits attributes and motion; hide resets; snapshots retain the resolved pose',
    (tester) async {
      final manager = GameManager(defaultSceneTransitionType: 'none');
      addTearDown(manager.dispose);
      late YuyuPackage package;
      late ScriptNode script;
      late YuyuLayerMapping mapping;
      await tester.runAsync(() async {
        package = YuyuPackage.active = await YuyuPackage.open(fixture);
        mapping = await package.layerMapping;
        configureRuntimeProject(
          projectName: package.gameId,
          packageDigest: package.digest,
        );
        manager.characterConfigs.addAll(
          ConfigParser().parseCharacters(
            await package.loadText('GameScript/configs/characters.sks'),
          ),
        );
        manager.poseConfigs.addAll(
          ConfigParser().parsePoses(
            await package.loadText('GameScript/configs/poses.sks'),
          ),
        );
        AnimationManager.loadAnimationsFromStringForTesting(
          await package.loadText('GameScript/configs/animation.sks'),
        );
        final parsed = SksParser().parse(
          await package.loadText('GameScript/labels/start.sks'),
        );
        // Exercise the mapped display statements along one branch in the actual VM.
        final shows = parsed.children.whereType<ShowNode>().toList();
        script = ScriptNode([
          shows[0],
          SayNode(dialogue: 'first'),
          shows[1],
          SayNode(dialogue: 'inherited'),
          shows[3],
          SayNode(dialogue: 'removed'),
          parsed.children.whereType<HideNode>().single,
          shows[4],
          SayNode(dialogue: 'reset'),
        ]);
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
      await tester.runAsync(() => manager.startTestScript(script));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final first = manager.currentState.characters.values.single;
      expect(first.animationProperties!['xcenter'], closeTo(.5078125, .0001));
      await tester.runAsync(() async {
        final changed = manager.gameStateStream.firstWhere(
          (state) => state.dialogue == 'inherited',
        );
        manager.next();
        await changed.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      final inherited = manager.currentState.characters.values.single;
      expect(
        mapping.layersFor('e:${inherited.pose}:__none').first['assetName'],
        contains('shirt'),
      );
      expect(
        inherited.animationProperties!['xcenter'],
        closeTo(.5078125, .0001),
      );
      final snapshot = GameStateSnapshot(
        scriptIndex: 1,
        currentState: manager.currentState,
      );
      final restored = BinarySerializer.deserializeGameStateSnapshot(
        BinarySerializer.serializeGameStateSnapshot(snapshot),
      );
      expect(
        restored.currentState.characters.values.single.pose,
        inherited.pose,
      );
      await tester.runAsync(() async {
        final changed = manager.gameStateStream.firstWhere(
          (state) => state.dialogue == 'removed',
        );
        manager.next();
        await changed.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final stopped = manager.currentState.characters.values.single;
      expect(mapping.layersFor('e:${stopped.pose}:__none'), hasLength(2));
      expect(stopped.animationProperties!['xcenter'], closeTo(.3, .0001));
      await tester.runAsync(() async {
        final changed = manager.gameStateStream.firstWhere(
          (state) => state.dialogue == 'reset',
        );
        manager.next();
        await changed.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final reset = manager.currentState.characters.values.single;
      expect(
        mapping.layersFor('e:${reset.pose}:__none').first['assetName'],
        contains('base'),
      );
      expect(reset.animationProperties!['xcenter'], closeTo(.5078125, .0001));
      manager.dispose();
      await tester.runAsync(package.close);
    },
  );
}
