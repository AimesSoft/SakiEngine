import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/utils/key_sequence_detector.dart';

/// 表情选择器管理器
/// 负责处理Debug模式下的C键检测和表情选择器的显示逻辑
class ExpressionSelectorManager {
  final GameManager gameManager;
  final Function(String message) showNotificationCallback;
  final Function() triggerReloadCallback;
  final Function(bool show) setExpressionSelectorVisibility;
  final Function() getCurrentGameState;

  bool _isExpressionSelectorVisible = false;

  ExpressionSelectorManager({
    required this.gameManager,
    required this.showNotificationCallback,
    required this.triggerReloadCallback,
    required this.setExpressionSelectorVisibility,
    required this.getCurrentGameState,
  });

  /// 初始化Shift+C快捷键检测（仅在Debug模式下）
  void initialize() {
    if (!kEngineDebugMode) return;

    // 使用Shift+C快捷键，避免与其他功能冲突
    _setupShiftCHotkey();
  }

  /// 设置Shift+C快捷键
  void _setupShiftCHotkey() {
    // 注册到HardwareKeyboard而不是使用LongPressKeyDetector
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// 处理键盘事件
  bool _handleKeyEvent(KeyEvent event) {
    if (!kEngineDebugMode) return false;

    // 检查Shift+C组合键
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isShiftPressed) {
      _handleShiftCPress();
      return true;
    }

    return false;
  }

  /// 处理Shift+C按键事件
  void _handleShiftCPress() {
    _requestShowExpressionSelector();
  }

  /// 释放资源
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }

  /// 设置表情选择器可见性状态
  void setExpressionSelectorVisible(bool visible) {
    _isExpressionSelectorVisible = visible;
  }

  /// 检查当前是否可以显示表情选择器
  bool canShowExpressionSelector({
    required bool showSaveOverlay,
    required bool showLoadOverlay,
    required bool showReviewOverlay,
    required bool showSettings,
    required bool showDeveloperPanel,
    required bool showDebugPanel,
    required bool isShowingMenu,
  }) {
    return !showSaveOverlay &&
        !showLoadOverlay &&
        !showReviewOverlay &&
        !showSettings &&
        !showDeveloperPanel &&
        !showDebugPanel &&
        !_isExpressionSelectorVisible &&
        !isShowingMenu;
  }

  /// 请求显示表情选择器（需要调用方进行状态检查）
  void _requestShowExpressionSelector() {
    try {
      // 获取当前游戏状态
      final gameStateValue = getCurrentGameState();
      if (gameStateValue == null ||
          gameStateValue.speaker == null ||
          gameStateValue.speaker!.isEmpty) {
        showNotificationCallback('没有当前说话角色');
        return;
      }

      // 查找当前说话角色的信息
      final speakerInfo = _findCurrentSpeakerInfo(gameStateValue);
      if (speakerInfo == null) {
        showNotificationCallback('无法找到角色信息: ${gameStateValue.speaker}');
        return;
      }

      if (kEngineDebugMode) {
        //print('表情选择器: 检测到说话角色 ${speakerInfo.speakerName} (${speakerInfo.characterId})');
        print(
            '当前pose: ${speakerInfo.currentPose}, expression: ${speakerInfo.currentExpression}');
      }

      // 通知调用方显示表情选择器
      setExpressionSelectorVisibility(true);
    } catch (e) {
      if (kEngineDebugMode) {
        //print('表情选择器: 获取角色信息失败: $e');
      }
      showNotificationCallback('获取角色信息失败');
    }
  }

  /// 获取当前说话角色信息
  SpeakerInfo? getCurrentSpeakerInfo() {
    final gameStateValue = getCurrentGameState();
    if (gameStateValue == null ||
        gameStateValue.speaker == null ||
        gameStateValue.speaker!.isEmpty) {
      return null;
    }

    return _findCurrentSpeakerInfo(gameStateValue);
  }

  /// 查找当前说话角色的信息
  SpeakerInfo? _findCurrentSpeakerInfo(dynamic gameState) {
    final currentSpeaker = gameState.speaker as String;

    // 获取角色配置
    final characterConfigs = gameManager.characterConfigs;

    // 首先通过角色名称在配置中查找对应的key和resourceId
    String? characterKey;
    String? targetResourceId;

    for (final entry in characterConfigs.entries) {
      if (entry.value.name == currentSpeaker) {
        characterKey = entry.key;
        targetResourceId = entry.value.resourceId;
        break;
      }
    }

    // 如果通过配置找到了角色信息，使用resourceId查找差分，但保留characterKey用于脚本修改
    if (characterKey != null && targetResourceId != null) {
      // 从场景中找到对应resourceId的角色状态信息
      for (final entry in gameState.characters.entries) {
        final characterState = entry.value;
        final resourceId = characterState.resourceId as String;

        // 跳过narrator
        if (resourceId == 'narrator') continue;

        // 找到匹配的resourceId
        if (resourceId == targetResourceId) {
          return SpeakerInfo(
            characterId: targetResourceId, // 使用resourceId来查找差分文件
            speakerName: currentSpeaker,
            currentPose: characterState.pose ?? 'pose1',
            currentExpression: characterState.expression ?? 'happy',
            scriptCharacterKey: characterKey, // 保留characterKey用于脚本修改
          );
        }
      }

      // 如果没找到完全匹配的resourceId，使用第一个非narrator角色作为fallback
      for (final entry in gameState.characters.entries) {
        final characterState = entry.value;
        final resourceId = characterState.resourceId as String;

        if (resourceId != 'narrator') {
          return SpeakerInfo(
            characterId: resourceId, // 使用实际的resourceId来查找差分文件
            speakerName: currentSpeaker,
            currentPose: characterState.pose ?? 'pose1',
            currentExpression: characterState.expression ?? 'happy',
            scriptCharacterKey: characterKey, // 保留characterKey用于脚本修改
          );
        }
      }
    }

    // 如果配置中没找到，使用fallback逻辑
    for (final entry in gameState.characters.entries) {
      final characterState = entry.value;
      final resourceId = characterState.resourceId as String;

      // 跳过narrator角色
      if (resourceId == 'narrator') {
        continue;
      }

      return SpeakerInfo(
        characterId: resourceId,
        speakerName: currentSpeaker,
        currentPose: characterState.pose ?? 'pose1',
        currentExpression: characterState.expression ?? 'happy',
      );
    }

    return null;
  }

  /// 处理表情选择变更
  Future<void> handleExpressionSelectionChanged(
      String characterId, String pose, String expression) async {
    try {
      if (kEngineDebugMode) {
        print(
            'ExpressionSelector: 开始处理表情选择变更 - characterId: $characterId, pose: $pose, expression: $expression');
      }

      // 获取当前对话文本
      final currentDialogue = gameManager.currentDialogueText;
      if (kEngineDebugMode) {
        print('ExpressionSelector: 当前对话文本: "$currentDialogue"');
      }

      if (currentDialogue.isEmpty) {
        if (kEngineDebugMode) {
          print('ExpressionSelector: 对话文本为空，尝试从当前状态获取');
        }
        // 尝试从当前状态获取对话
        final gameState = getCurrentGameState();
        final stateDialogue = gameState?.dialogue ?? '';
        if (stateDialogue.isEmpty) {
          showNotificationCallback('没有当前对话文本');
          return;
        }
        // 使用状态中的对话文本
        await _processExpressionChange(
            stateDialogue, characterId, pose, expression);
        return;
      }

      await _processExpressionChange(
          currentDialogue, characterId, pose, expression);
    } catch (e) {
      if (kEngineDebugMode) {
        print('ExpressionSelector: 处理表情选择变更失败: $e');
      }
      showNotificationCallback('应用差分失败: $e');
    }
  }

  /// 处理表情变更的核心逻辑
  Future<void> _processExpressionChange(String dialogue, String characterId,
      String pose, String expression) async {
    try {
      if (kEngineDebugMode) {
        print(
            'ExpressionSelector: 处理表情变更 - dialogue: "$dialogue", characterId: $characterId');
      }

      final sourceLine = gameManager.currentDialogueSourceLine;
      final sourceScriptFile = gameManager.currentDialogueSourceScriptFile;
      final scriptFileForWrite =
          (sourceScriptFile != null && sourceScriptFile.trim().isNotEmpty)
              ? sourceScriptFile
              : gameManager.currentScriptFile;

      // 获取当前脚本文件路径（优先使用当前对话记录的来源文件）
      final scriptPath = await ScriptContentModifier.getCurrentScriptFilePath(
          scriptFileForWrite);
      if (kEngineDebugMode) {
        print('ExpressionSelector: 脚本文件路径: $scriptPath');
      }

      if (scriptPath == null) {
        showNotificationCallback('无法获取脚本文件路径');
        return;
      }

      // 获取当前说话角色信息，确定用于脚本修改的characterKey
      final speakerInfo = getCurrentSpeakerInfo();
      final scriptCharacterKey = speakerInfo?.scriptCharacterKey ?? characterId;
      if (kEngineDebugMode) {
        print('ExpressionSelector: 脚本角色Key: $scriptCharacterKey');
        print(
            'ExpressionSelector: 当前对话来源 sourceScriptFile=$sourceScriptFile, sourceLine=$sourceLine');
        print('ExpressionSelector: 目标脚本文件名: $scriptFileForWrite');
      }

      // 修改脚本文件 - 需要创建新的方法来同时修改pose和expression
      final success = await ScriptContentModifier.modifyDialogueLineWithPose(
        scriptFilePath: scriptPath,
        targetDialogue: dialogue,
        characterId: scriptCharacterKey,
        newPose: pose,
        newExpression: expression,
        targetLineNumber: sourceLine,
      );

      if (kEngineDebugMode) {
        print('ExpressionSelector: 脚本修改结果: $success');
      }

      if (success) {
        showNotificationCallback('已应用差分: $pose / $expression');

        // 触发脚本重载
        if (kEngineDebugMode) {
          print('ExpressionSelector: 触发脚本重载');
        }
        triggerReloadCallback();
      } else {
        showNotificationCallback('修改脚本失败');
      }
    } catch (e) {
      if (kEngineDebugMode) {
        print('ExpressionSelector: 处理表情变更异常: $e');
      }
      showNotificationCallback('处理表情变更失败: $e');
    }
  }
}

/// 说话角色信息
class SpeakerInfo {
  final String characterId; // 用于查找差分文件的resourceId
  final String speakerName;
  final String currentPose;
  final String currentExpression;
  final String? scriptCharacterKey; // 用于脚本修改的角色key

  const SpeakerInfo({
    required this.characterId,
    required this.speakerName,
    required this.currentPose,
    required this.currentExpression,
    this.scriptCharacterKey,
  });
}
