import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/effects/scene_filter.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() {
    storage = Directory.systemTemp.createTempSync('branch-presentation-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => storage.path);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    storage.deleteSync(recursive: true);
  });

  test(
    'legacy saves remain readable and new snapshots distinguish silence from missing music',
    () {
      final legacy = BinarySerializer.deserializeSaveSlot(
        File('test/fixtures/yuyu/native-v18-nvl.sakisav').readAsBytesSync(),
      );
      expect(legacy.snapshot.currentState.hasMusicState, isFalse);
      for (final music in <MusicRegion?>[
        null,
        MusicRegion(
          musicFile: 'route-theme',
          startScriptIndex: 12,
          endScriptIndex: 30,
        ),
      ]) {
        final restored = BinarySerializer.deserializeGameStateSnapshot(
          BinarySerializer.serializeGameStateSnapshot(
            GameStateSnapshot(
              scriptIndex: 80,
              currentState: GameState(
                currentMusicRegion: music,
                sceneFilter: const SceneFilter(
                  type: FilterType.snowMosaic,
                  intensity: 0.8,
                  animation: AnimationType.fade,
                  duration: 1.8,
                ),
              ),
            ),
          ),
        );
        expect(restored.currentState.hasMusicState, isTrue);
        expect(restored.currentState.currentMusicRegion, music);
        expect(restored.currentState.sceneFilter?.type, FilterType.snowMosaic);
        expect(restored.currentState.sceneFilter?.intensity, 0.8);
        expect(restored.currentState.sceneFilter?.duration, 1.8);
      }
    },
  );

  test(
    'menu and its jump keep the current dialogue and snapshot identity',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        ScriptNode([
          SayNode(dialogue: 'Earlier line'),
          SayNode(
            character: 'unknown',
            dialogue: 'My name',
            dialogueTag: 'happy',
          ),
          MenuNode([ChoiceOptionNode('Thanks', 'reply')]),
          LabelNode('reply'),
          SayNode(character: 'known', dialogue: 'Wait'),
          MenuNode([ChoiceOptionNode('Thanks again', 'end')]),
          LabelNode('end'),
          SayNode(dialogue: 'Done'),
        ]),
        characterConfigs: {
          'unknown': CharacterConfig(
            id: 'unknown',
            name: 'Unknown',
            resourceId: 'narrator',
          ),
          'known': CharacterConfig(
            id: 'known',
            name: 'Noe',
            resourceId: 'narrator',
          ),
        },
      );
      manager.next();
      await Future<void>.delayed(Duration.zero);
      expect(manager.currentState.dialogue, 'My name');
      expect(manager.currentState.speakerAlias, 'unknown');
      expect(
        manager.getDialogueHistory().last.stateSnapshot.currentState.dialogue,
        'My name',
      );
      final states = <GameState>[];
      final subscription = manager.gameStateStream.listen(states.add);
      addTearDown(subscription.cancel);
      await manager.jumpToLabel('reply');
      await Future<void>.delayed(Duration.zero);
      expect(
        states.map((state) => state.dialogue),
        isNot(contains('Earlier line')),
      );
      expect(manager.currentState.dialogue, 'Wait');
      expect(manager.currentState.speakerAlias, 'known');
      final snapshot = BinarySerializer.deserializeGameStateSnapshot(
        BinarySerializer.serializeGameStateSnapshot(
          manager.saveStateSnapshot(),
        ),
      );
      expect(snapshot.currentState.dialogue, 'Wait');
      expect(snapshot.dialogueHistory.last.dialogue, 'Wait');
    },
  );

  test(
    'normal branch execution never consumes music cues in an unvisited branch',
    () async {
      final manager = GameManager();
      addTearDown(manager.dispose);
      await manager.startTestScript(
        ScriptNode([
          SayNode(dialogue: 'At the choice'),
          StopMusicNode(),
          LabelNode('join'),
          SayNode(dialogue: 'Joined'),
          SayNode(dialogue: 'Still playing'),
        ]),
        initialState: GameState(
          currentMusicRegion: MusicRegion(
            musicFile: 'route-theme',
            startScriptIndex: 0,
          ),
        ),
        disableRuntimeSideEffects: false,
      );
      await manager.jumpToLabel('join');
      expect(manager.currentState.currentMusicRegion?.musicFile, 'route-theme');
      manager.next();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(manager.currentState.currentMusicRegion?.musicFile, 'route-theme');
      final snapshot = BinarySerializer.deserializeGameStateSnapshot(
        BinarySerializer.serializeGameStateSnapshot(
          manager.saveStateSnapshot(),
        ),
      );
      expect(
        snapshot.currentState.currentMusicRegion?.musicFile,
        'route-theme',
      );
    },
  );
}
