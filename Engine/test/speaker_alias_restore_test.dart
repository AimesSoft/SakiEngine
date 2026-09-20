import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/script_merger.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ScriptNode script;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('speaker-alias-restore-');
    Directory('${directory.path}/Assets').createSync();
    final source = File('${directory.path}/GameScript/labels/start.sks');
    source.parent.createSync(recursive: true);
    source.writeAsStringSync(
      'label start\n'
      'aru_voice "First line"\n'
      'me "Second line"\n'
      '"Narration with staging" aru2 normal\n'
      '"Plain narration"\n',
    );
    configureRuntimeProject(
      projectName: 'Speaker-Alias-Test',
      gamePath: directory.path,
    );
    GamePathResolver.clearCache();
    ScriptMerger().clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    script = await ScriptMerger().getMergedScript();
  });

  tearDownAll(() {
    ScriptMerger().clearCache();
    GamePathResolver.clearCache();
    clearRuntimeProjectConfig();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  for (final testCase in [
    (dialogue: 'First line', alias: 'aru_voice', speaker: '鴉るる'),
    (dialogue: 'Second line', alias: 'me', speaker: 'わたし'),
    (dialogue: 'Narration with staging', alias: 'aru2', speaker: null),
    (dialogue: 'Plain narration', alias: null, speaker: null),
  ]) {
    test(
      'restores identity from the authored node: ${testCase.dialogue}',
      () async {
        final manager = GameManager();
        addTearDown(manager.dispose);
        manager.characterConfigs.addAll({
          'aru_voice': CharacterConfig(
            id: 'aru_voice',
            name: '鴉るる',
            resourceId: 'narrator',
          ),
          'me': CharacterConfig(id: 'me', name: 'わたし', resourceId: 'narrator'),
        });
        final index = script.children.indexWhere(
          (node) => node is SayNode && node.dialogue == testCase.dialogue,
        );
        expect(index, greaterThanOrEqualTo(0));
        final saved = BinarySerializer.deserializeGameStateSnapshot(
          BinarySerializer.serializeGameStateSnapshot(
            GameStateSnapshot(
              scriptIndex: index + 1,
              currentState: GameState(
                dialogue: testCase.dialogue,
                speaker: 'old display name',
                speakerAlias: 'stale_alias',
              ),
            ),
          ),
        );
        // Existing save versions do not persist ADV speakerAlias.
        expect(saved.currentState.speakerAlias, isNull);
        await manager.restoreFromSnapshot(
          'start',
          saved,
          shouldReExecute: false,
          reloadCharacterConfigs: false,
          restoreDialogueVoice: false,
        );
        expect(manager.currentState.speakerAlias, testCase.alias);
        expect(manager.currentState.speaker, testCase.speaker);
        expect(manager.currentState.dialogue, testCase.dialogue);
      },
    );
  }
}
