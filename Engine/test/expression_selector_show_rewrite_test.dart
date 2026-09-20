import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/character_layer_parser.dart';
import 'package:sakiengine/src/utils/expression_selector_manager.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/key_sequence_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('角色 show 写入', () {
    late Directory directory;
    late File scriptFile;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('saki_show_rewrite_');
      Directory('${directory.path}/Assets').createSync(recursive: true);
      scriptFile = File('${directory.path}/GameScript/labels/start.sks');
      scriptFile.parent.createSync(recursive: true);
    });

    tearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test('说话人不是被改角色时插入新的 show 行', () async {
      await scriptFile.writeAsString(
        'label start\n'
        'l "玩家在说话"\n',
      );

      final ok = await ScriptContentModifier.modifyCharacterShowNearDialogue(
        scriptFilePath: scriptFile.path,
        characterId: 'noe',
        pose: 'pose1',
        expression: 'happy --mask',
        targetLineNumber: 2,
        targetDialogue: '玩家在说话',
      );

      expect(ok, isTrue);
      final lines = (await scriptFile.readAsString())
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(lines, contains('show noe pose1 happy --mask'));
      // show 必须插在说话行之前，而不是写到玩家行里。
      expect(
        lines.indexOf('show noe pose1 happy --mask'),
        lessThan(lines.indexOf('l "玩家在说话"')),
      );
      expect(lines, isNot(contains('l happy --mask "玩家在说话"')));
    });

    test('紧邻的同角色 show 只更新那一条', () async {
      await scriptFile.writeAsString(
        'label start\n'
        'show noe pose1 normal\n'
        'play sound pekori\n'
        'l "换差分"\n',
      );

      final ok = await ScriptContentModifier.modifyCharacterShowNearDialogue(
        scriptFilePath: scriptFile.path,
        characterId: 'noe',
        pose: 'pose1',
        expression: 'angry --mask',
        targetLineNumber: 4,
        targetDialogue: '换差分',
      );

      expect(ok, isTrue);
      final content = await scriptFile.readAsString();
      expect(content, contains('show noe pose1 angry --mask'));
      expect(content, isNot(contains('show noe pose1 normal')));
      // 不应额外插入新的 show 行。
      expect('show noe'.allMatches(content).length, 1);
    });

    test('行号失效时仍按对话内容定位锚点', () async {
      await scriptFile.writeAsString(
        'label start\n'
        'l "前面的对话"\n'
        'l "目标对话"\n',
      );

      final ok = await ScriptContentModifier.modifyCharacterShowNearDialogue(
        scriptFilePath: scriptFile.path,
        characterId: 'noe',
        pose: 'pose1',
        expression: 'happy',
        // 故意给一个错误的行号。
        targetLineNumber: 1,
        targetDialogue: '目标对话',
      );

      expect(ok, isTrue);
      final lines = (await scriptFile.readAsString())
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      expect(
        lines.indexOf('show noe pose1 happy'),
        lessThan(lines.indexOf('l "目标对话"')),
      );
      expect(
        lines.indexOf('show noe pose1 happy'),
        greaterThan(lines.indexOf('l "前面的对话"')),
      );
    });

    test('保留已有 show 的位置、动画与 repeat', () async {
      await scriptFile.writeAsString(
        'label start\n'
        'show noe pose2 normal at xiayo1poseleft an jump repeat 3\n'
        'l "保持运动"\n',
      );

      await ScriptContentModifier.modifyCharacterShowNearDialogue(
        scriptFilePath: scriptFile.path,
        characterId: 'noe',
        pose: 'pose2',
        expression: 'sad --mask',
        targetLineNumber: 3,
        targetDialogue: '保持运动',
      );

      final content = await scriptFile.readAsString();
      expect(
        content,
        contains(
          'show noe pose2 sad --mask at xiayo1poseleft an jump repeat 3',
        ),
      );
    });
  });

  group('差分选择器的写入位置', () {
    late Directory directory;
    late File scriptFile;
    late GameManager manager;
    late ExpressionSelectorManager selector;
    late ScriptNode script;

    final noeConfig = CharacterConfig(
      id: 'noe',
      name: '弥黑埜爱',
      resourceId: 'noe',
      slotId: 'noe',
    );
    final playerConfig = CharacterConfig(
      id: 'l',
      name: '主角',
      resourceId: 'narrator',
      slotId: 'player',
    );

    setUp(() {
      directory = Directory.systemTemp.createTempSync('saki_selector_write_');
      Directory('${directory.path}/Assets').createSync(recursive: true);
      scriptFile = File('${directory.path}/GameScript/labels/start.sks');
      scriptFile.parent.createSync(recursive: true);
      configureRuntimeProject(gamePath: directory.path);
      GamePathResolver.clearCache();
      CharacterLayerParser.clearCache();
    });

    tearDown(() {
      selector.dispose();
      CharacterLayerParser.clearCache();
      clearRuntimeProjectConfig();
      GamePathResolver.clearCache();
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    /// 直接构造"谁在说话 + 谁在台上"的状态，避免在测试里跑完整演出循环。
    Future<void> prepare({
      required String scriptText,
      required List<SksNode> nodes,
      required String dialogue,
      required String? speaker,
      required String? speakerAlias,
      required Map<String, CharacterConfig> configs,
    }) async {
      await scriptFile.writeAsString(scriptText);
      script = ScriptNode(nodes);
      manager = GameManager(defaultSceneTransitionType: 'none');
      manager.characterConfigs.addAll(configs);
      selector = ExpressionSelectorManager(
        gameManager: manager,
        showNotificationCallback: (_) {},
        triggerReloadCallback: () {},
        setExpressionSelectorVisibility: (_) {},
        getCurrentGameState: () => manager.currentState,
      );

      final index = nodes.indexWhere(
        (node) => node is SayNode && node.dialogue == dialogue,
      );
      expect(index, greaterThanOrEqualTo(0));

      await manager.restoreFromSnapshot(
        'start',
        GameStateSnapshot(
          scriptIndex: index + 1,
          currentState: GameState(
            dialogue: dialogue,
            speaker: speaker,
            speakerAlias: speakerAlias,
            characters: {
              'slot:noe': CharacterState(
                resourceId: 'noe',
                pose: 'pose1',
                expression: 'normal',
              ),
            },
          ),
        ),
        shouldReExecute: false,
        reloadCharacterConfigs: false,
        restoreDialogueVoice: false,
      );
      expect(manager.currentState.dialogue, dialogue);
    }

    test('说话人不是被改角色时不写进玩家对话行', () async {
      await prepare(
        // 目标对话放在第一个 SayNode：恢复状态时不会因为对齐历史而回退到
        // 前面的旁白。
        scriptText: 'label start\nl "玩家在说话"\nnoe "弥黑埜爱在说话"\n',
        nodes: [
          SayNode(character: 'l', dialogue: '玩家在说话'),
          SayNode(
            character: 'noe',
            dialogue: '弥黑埜爱在说话',
            pose: 'pose1',
            expression: 'normal',
          ),
        ],
        dialogue: '玩家在说话',
        speaker: '主角',
        speakerAlias: 'l',
        configs: {'noe': noeConfig, 'l': playerConfig},
      );

      await selector.handleExpressionSelectionChanged(
        'noe',
        'pose1',
        'happy --mask',
        null,
      );

      final content = await scriptFile.readAsString();
      expect(content, contains('show noe pose1 happy --mask'));
      expect(content, isNot(contains('l happy --mask')));
      expect(content, isNot(contains('"玩家在说话" happy')));
    });

    test('说话人就是被改角色时更新对话行', () async {
      await prepare(
        scriptText: 'label start\n"开场旁白"\nnoe normal "弥黑埜爱在说话"\n',
        nodes: [
          SayNode(dialogue: '开场旁白'),
          SayNode(
            character: 'noe',
            dialogue: '弥黑埜爱在说话',
            pose: 'pose1',
            expression: 'normal',
          ),
        ],
        dialogue: '弥黑埜爱在说话',
        speaker: '弥黑埜爱',
        speakerAlias: 'noe',
        configs: {'noe': noeConfig},
      );

      await selector.handleExpressionSelectionChanged(
        'noe',
        'pose1',
        'happy --mask',
        null,
      );

      final content = await scriptFile.readAsString();
      expect(content, contains('noe pose1 happy --mask'));
      expect(content, isNot(contains('show noe')));
    });
  });
}
