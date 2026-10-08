import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/localization/script_text_localizer.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/game/script_dialogue_resolver.dart';

/// NVL模式状态管理器
/// 负责NVL模式的状态恢复和刷新逻辑
class NvlStateManager {
  /// 从存档恢复NVL对话列表
  ///
  /// 重要：NVL模式读档时不能使用 _scriptIndex 来刷新对话内容
  /// 因为 _scriptIndex 在执行完对话后已经 ++ 指向下一句
  /// 如果用 _scriptIndex 获取对话会导致显示下一句而不是当前句
  ///
  /// 参数：
  /// - snapshot: 游戏状态快照
  /// - script: 当前脚本节点列表
  /// - characterConfigs: 角色配置
  /// - scriptIndex: 当前脚本索引（注意：已经指向下一句）
  ///
  /// 返回：刷新后的NVL对话列表，如果不需要刷新则返回null
  static List<NvlDialogue>? restoreNvlDialogues({
    required GameStateSnapshot snapshot,
    required ScriptNode script,
    required Map<String, CharacterConfig> characterConfigs,
    required int scriptIndex,
    List<DialogueHistoryEntry>? playedHistory,
    String Function(String)? resolveText,
  }) {
    // 如果不是NVL模式或没有对话，直接返回null
    if (!snapshot.isNvlMode || snapshot.nvlDialogues.isEmpty) {
      return null;
    }

    final originals = snapshot.nvlDialogues;
    final history = playedHistory ?? snapshot.dialogueHistory;
    final indices = List<int?>.filled(originals.length, null);

    // An NVL page contains the most recently played dialogue entries. Use
    // their real execution order, which may cross jumps or skip conditions.
    var target = originals.length - 1;
    for (var i = history.length - 1; i >= 0 && target >= 0; i--) {
      indices[target--] = history[i].scriptIndex;
    }

    // Older history snapshots omit history to avoid recursive serialization.
    // Without an execution trace, only infer an uninterrupted NVL block. Never
    // walk across a jump/label/conditional and accidentally reveal an unplayed
    // branch. Preserve unmatched old lines rather than guessing their source.
    if (history.isEmpty) {
      for (var i = scriptIndex - 1; i >= 0 && target >= 0; i--) {
        if (i >= script.children.length) continue;
        final node = script.children[i];
        if (node is SayNode) {
          indices[target--] = i;
        } else if (node is LabelNode ||
            node is JumpNode ||
            node is MenuNode ||
            node is ConditionalSayNode ||
            node is NvlNode ||
            node is NvlnNode ||
            node is NvlMovieNode ||
            node is EndNvlNode ||
            node is EndNvlnNode ||
            node is EndNvlMovieNode ||
            node is ReturnNode) {
          break;
        }
      }
    }

    return List.generate(originals.length, (i) {
      final original = originals[i];
      final index = indices[i];
      final node = index == null
          ? null
          : ScriptDialogueResolver.at(script, index);
      if (node == null) return original;
      return NvlDialogue(
        speaker: node.character == null
            ? null
            : characterConfigs[node.character]?.name,
        speakerAlias: node.character ?? node.tailCharacter,
        dialogue:
            resolveText?.call(node.dialogue) ??
            ScriptTextLocalizer.resolve(node.dialogue),
        dialogueTag: node.dialogueTag,
        timestamp: original.timestamp,
        presentation: original.presentation,
      );
    });
  }

  /// 刷新当前状态的对话文本（仅用于非NVL模式）
  ///
  /// 这个方法只应该在非NVL模式下调用
  /// NVL模式应该直接使用存档中的 nvlDialogues
  ///
  /// 参数：
  /// - snapshot: 游戏状态快照
  /// - script: 当前脚本节点列表
  /// - characterConfigs: 角色配置
  /// - scriptIndex: 当前脚本索引
  /// - currentState: 当前游戏状态
  ///
  /// 返回：包含刷新后对话和说话人的Map
  static Map<String, String?>? refreshCurrentDialogue({
    required GameStateSnapshot snapshot,
    required ScriptNode script,
    required Map<String, CharacterConfig> characterConfigs,
    required int scriptIndex,
    required GameState currentState,
  }) {
    // NVL模式不应该调用这个方法
    if (snapshot.isNvlMode) {
      return null;
    }

    // 检查索引是否有效
    if (scriptIndex < 0 || scriptIndex >= script.children.length) {
      return null;
    }

    final node = script.children[scriptIndex];
    String? newDialogue;
    String? newSpeaker;

    // 根据节点类型提取最新的对话文本（只处理SayNode）
    if (node is SayNode) {
      newDialogue = ScriptTextLocalizer.resolve(node.dialogue);
      if (node.character != null) {
        final characterConfig = characterConfigs[node.character];
        newSpeaker = characterConfig?.name;
      }
    }

    if (newDialogue != null) {
      return {'dialogue': newDialogue, 'speaker': newSpeaker};
    }

    return null;
  }

  /// 验证NVL模式状态是否需要刷新
  ///
  /// 用于调试和验证，确保NVL模式读档后状态正确
  static bool shouldRefreshNvlState(GameStateSnapshot snapshot) {
    return snapshot.isNvlMode && snapshot.nvlDialogues.isNotEmpty;
  }

  /// 获取NVL模式的上下文类型
  ///
  /// 注意：返回类型为动态Map，调用方需要根据isNvlMode/isNvlMovieMode/isNvlnMode自行设置
  /// 这样避免暴露私有的 _NvlContextMode 枚举
  static Map<String, bool> getNvlContextFlags({
    required bool isNvlMode,
    required bool isNvlMovieMode,
    required bool isNvlnMode,
  }) {
    return {
      'isNvlMode': isNvlMode,
      'isNvlMovieMode': isNvlMovieMode,
      'isNvlnMode': isNvlnMode,
    };
  }
}
