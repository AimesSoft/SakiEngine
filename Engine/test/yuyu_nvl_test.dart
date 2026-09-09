import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_game_module.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_nvl.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_package.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_story_bridge.dart';
import 'package:sakiengine/src/compat/yuyu/yuyu_validator.dart';
import 'package:sakiengine/src/config/config_parser.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fixture = 'test/fixtures/yuyu/nvl.yuyu';

  test(
    'NVL package validates six mapped modes with the actual parser',
    () async {
      final package = await YuyuPackage.open(fixture);
      addTearDown(package.close);
      expect((await validateYuyuPackage(package))['nodes'], 35);
      expect(
        package.nvlMapping.blocks.values.map((v) => v.mode).toSet(),
        YuyuNvlMapping.modes,
      );
      final native = SksParser().parse('nvl\nendnvl').children.first as NvlNode;
      expect(native.presentation, isNull);
      expect(native.accumulate, isTrue);
      expect(native.preserve, isFalse);
    },
  );

  test(
    'strict validator rejects ignored NVL flags and undeclared metadata',
    () async {
      final package = await YuyuPackage.open(fixture);
      addTearDown(package.close);
      final scriptFile = package.entryFile('saki/GameScript/labels/start.sks')!;
      final original = await scriptFile.readAsString();
      await scriptFile.writeAsString(
        original.replaceFirst(' preserve', ' misspelled'),
      );
      await expectLater(validateYuyuPackage(package), throwsFormatException);
      await scriptFile.writeAsString(original);
      (package.manifest['compatibility']['requiredCapabilities'] as List)
          .remove('ui.yuyuball-web-nvl@1');
      await expectLater(validateYuyuPackage(package), throwsFormatException);
    },
  );

  test('NVL metadata checks precomputed typography, not just JSON shape', () {
    expect(
      () => YuyuNvlMapping({
        'version': 1,
        'blocks': {
          'bad': {
            'mode': 'nvl2',
            'expectedLines': [
              {'who': '', 'what': 'Hi', 'text': 'Hi'},
            ],
          },
        },
      }),
      throwsFormatException,
    );
    expect(
      YuyuNvlMapping.cleanText(' 【测试】  {b}Hi{/b}\n //voice-abc '),
      '测试 Hi',
    );
  });

  test(
    'v19 saves retain per-line mode and alias inside history and live state',
    () {
      final lines = [
        NvlDialogue(
          speaker: '测试',
          speakerAlias: 'e',
          dialogue: 'Quoted',
          presentation: 'yuyu_nvl2',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      ];
      final state = GameState(
        isNvlMode: true,
        isNvlOverlayVisible: true,
        nvlPresentation: 'yuyu_nvl6',
        nvlLayout: 'layout',
        nvlDialogues: lines,
      );
      final snapshot = GameStateSnapshot(
        scriptIndex: 5,
        currentState: state,
        isNvlMode: true,
        isNvlOverlayVisible: true,
        nvlDialogues: lines,
      );
      final history = DialogueHistoryEntry(
        dialogue: 'Quoted',
        timestamp: DateTime.now(),
        scriptIndex: 4,
        stateSnapshot: snapshot,
      );
      final save = SaveSlot(
        id: 1,
        saveTime: DateTime.now(),
        currentScript: 'start',
        dialoguePreview: 'Quoted',
        snapshot: GameStateSnapshot(
          scriptIndex: 5,
          currentState: state,
          dialogueHistory: [history],
          isNvlMode: true,
          isNvlOverlayVisible: true,
          nvlDialogues: lines,
        ),
      );
      final restored = BinarySerializer.deserializeSaveSlot(
        BinarySerializer.serializeSaveSlot(save),
      );
      for (final value in [
        restored.snapshot,
        restored.snapshot.dialogueHistory.single.stateSnapshot,
      ]) {
        expect(value.currentState.nvlPresentation, 'yuyu_nvl6');
        expect(value.currentState.nvlLayout, 'layout');
        expect(
          value.currentState.nvlDialogues.single.presentation,
          'yuyu_nvl2',
        );
        expect(value.nvlDialogues.single.speakerAlias, 'e');
      }
      final adv = state.copyWith(isNvlMode: false);
      expect(adv.nvlPresentation, isNull);
      expect(adv.nvlLayout, isNull);
      expect(adv.nvlAccumulate, isTrue);
    },
  );

  test(
    'v18 native NVL saves and nested history still load and can be saved as v19',
    () {
      final bytes = File(
        'test/fixtures/yuyu/native-v18-nvl.sakisav',
      ).readAsBytesSync();
      expect(bytes[4], 18);
      var save = BinarySerializer.deserializeSaveSlot(bytes);
      for (var round = 0; round < 2; round++) {
        for (final snapshot in [
          save.snapshot,
          save.snapshot.dialogueHistory.single.stateSnapshot,
        ]) {
          expect(snapshot.currentState.nvlDialogues.single.dialogue, 'Old NVL');
          expect(snapshot.currentState.nvlPresentation, isNull);
          expect(snapshot.currentState.nvlLayout, isNull);
          expect(snapshot.currentState.nvlAccumulate, isTrue);
        }
        save = BinarySerializer.deserializeSaveSlot(
          BinarySerializer.serializeSaveSlot(save),
        );
      }
    },
  );

  testWidgets(
    'mapped modes execute in GameManager and emit original-shaped Web packets',
    (tester) async {
      late YuyuPackage package;
      late ScriptNode script;
      late List<dynamic> reference;
      final manager = GameManager();
      await tester.runAsync(() async {
        package = await YuyuPackage.open(fixture);
        reference =
            jsonDecode(
                  await File(
                    'test/fixtures/yuyu/nvl-web-reference.json',
                  ).readAsString(),
                )
                as List;
        manager.characterConfigs.addAll(
          ConfigParser().parseCharacters(
            await package.loadText('GameScript/configs/characters.sks'),
          ),
        );
        script = SksParser().parse(
          await package.loadText('GameScript/labels/start.sks'),
        );
      });
      final bridge = YuyuStoryBridge(nvl: package.nvlMapping);
      addTearDown(bridge.dispose);
      addTearDown(manager.dispose);
      final events = <Map<String, dynamic>>[];
      await bridge.channel.attach((v) async {
        events.add(v);
      });
      bridge.attachManager(manager);
      final progression = DialogueProgressionManager(gameManager: manager);
      bridge.bindProgression(progression);
      await bridge.pageReady();
      await tester.runAsync(() async {
        final first = manager.gameStateStream.firstWhere(
          (v) => v.dialogue == 'ADV before',
        );
        await manager.startTestScript(script);
        await first.timeout(const Duration(seconds: 5));
      });
      bridge.presentDialogue(
        text: 'ADV before',
        speaker: '测试',
        scriptIndex: 1,
        progressionManager: progression,
      );
      Map<dynamic, dynamic> lastPacket() =>
          events.lastWhere((v) => v['type'] == 'game:dialogue')['dialogue']
              as Map;
      final observed = <Map<dynamic, dynamic>>[];
      void capture() {
        final value = Map<dynamic, dynamic>.from(lastPacket());
        value.remove('id');
        value.remove('seen');
        observed.add(value);
      }

      await bridge.pageReady();
      capture();
      Future<void> advanceTo(String text) async {
        await tester.runAsync(() async {
          final changed = manager.gameStateStream.firstWhere(
            (v) =>
                v.dialogue == text ||
                (v.nvlDialogues.isNotEmpty &&
                    v.nvlDialogues.last.dialogue == text),
          );
          manager.next();
          await changed.timeout(const Duration(seconds: 5));
        });
        await bridge
            .pageReady(); // Drain and verify the same snapshot survives page reload.
        if (manager.currentState.isNvlMode) capture();
      }

      await advanceTo('First');
      expect(lastPacket()['mode'], 'nvl');
      expect(lastPacket()['what'], '测试：First');
      expect(progression.canProgressDirectly, isFalse);
      await bridge.handle({
        'type': 'web:typewriterState',
        'dialogueId': lastPacket()['id'],
        'complete': true,
      });
      expect(progression.canProgressDirectly, isTrue);
      await advanceTo('Second');
      expect(lastPacket()['what'], '测试：First\nSecond');
      await advanceTo('Third');
      expect(
        lastPacket()['lines'],
        hasLength(3),
      ); // Same-mode begin preserves the block.
      await advanceTo('Quoted');
      expect(lastPacket()['what'], '测试：First\nSecond\n测试：Third\n“Quoted”');
      expect(lastPacket()['expectedLineCount'], 2);
      await advanceTo('Centered');
      expect(lastPacket()['currentLineIndex'], 4);
      final centered = manager.getDialogueHistory().last.stateSnapshot;
      expect(centered.currentState.nvlDialogues, hasLength(5));
      expect(centered.currentState.nvlPresentation, 'yuyu_nvl2');
      await advanceTo('New block');
      expect(
        lastPacket()['lines'],
        hasLength(1),
      ); // End/begin within one frame clears.
      expect(
        events.any(
          (v) =>
              v['type'] == 'game:dialogue' &&
              v['dialogue']['mode'] == 'nvl2' &&
              v['dialogue']['visible'] == false,
        ),
        isTrue,
      );
      await advanceTo('No quotes');
      expect(
        lastPacket()['what'],
        '“New block”\nNo quotes',
      ); // Previous line keeps its own formatting.
      await advanceTo('Random first');
      expect(lastPacket()['mode'], 'nvl3');
      expect(lastPacket()['lines'], hasLength(1));
      await advanceTo('Random second');
      expect(lastPacket()['lines'], hasLength(1));
      expect(lastPacket()['what'], '测试：Random second');
      await advanceTo('Fourth mode');
      expect(lastPacket()['mode'], 'nvl4');
      await advanceTo('Fifth mode');
      expect(lastPacket()['mode'], 'nvl5');
      await advanceTo('Sixth mode');
      expect(lastPacket()['expectedLines'], [
        {'who': '', 'what': 'Sixth mode', 'text': 'Sixth mode'},
        {
          'who': '',
          'what': 'Final centered line',
          'text': 'Final centered line',
        },
      ]);
      await advanceTo('Final centered line');
      final id = lastPacket()['id'];
      bridge.observeState(manager.currentState.copyWith());
      await bridge.pageReady();
      expect(lastPacket()['id'], id); // Animation ticks cannot restart typing.
      await advanceTo('ADV after');
      expect(lastPacket()['visible'], isFalse);
      bridge.presentDialogue(
        text: 'ADV after',
        speaker: '测试',
        scriptIndex: 34,
        progressionManager: progression,
      );
      await bridge.pageReady();
      expect(lastPacket()['mode'], 'adv');
      capture();
      expect(
        observed,
        reference,
        reason:
            'Matches original web_overlay.show_dialogue packets for every fixture Say',
      );
      // History recovery gets a fresh id and all original accumulated lines.
      bridge.observeState(centered.currentState);
      await bridge.pageReady();
      expect(lastPacket()['mode'], 'nvl2');
      expect(lastPacket()['currentLineIndex'], 4);
      expect(lastPacket()['id'], isNot(id));
      bridge.dispose();
      manager.dispose();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(package.close);
    },
  );

  testWidgets('NVL-first scripts bind external typing without an ADV widget', (
    tester,
  ) async {
    late YuyuPackage package;
    await tester.runAsync(() async {
      package = await YuyuPackage.open(fixture);
    });
    final module = YuyuGameModule(package);
    final manager = GameManager();
    final progression = DialogueProgressionManager(gameManager: manager);
    await tester.pumpWidget(
      module.createNvlPresentation(
        gameState: GameState(isNvlMode: true, nvlPresentation: 'yuyu_nvl'),
        progressionManager: progression,
      )!,
    );
    await tester.pump();
    expect(progression.externalTypewriterComplete, isNotNull);
    expect(progression.canProgressDirectly, isFalse);
    await tester.pumpWidget(const SizedBox());
    module.bridge.dispose();
    expect(progression.externalTypewriterComplete, isNull);
    manager.dispose();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(package.close);
  });
}
