import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';
import 'package:sakiengine/src/utils/read_text_tracker.dart';

/// 已读文本快进管理器
/// 
/// 只跳过已经阅读过的文本内容，区别于Ctrl的强制快进
/// 这是主流视觉小说的标准功能
class ReadTextSkipManager {
  final GameManager gameManager;
  final DialogueProgressionManager dialogueProgressionManager;
  final ReadTextTracker readTextTracker;
  
  // 快进状态
  bool _isSkipping = false;
  Timer? _skipTimer;
  StreamSubscription<GameState>? _gameStateSubscription;
  
  // 快进配置 - 比强制快进稍慢，让用户看清内容
  static const Duration _skipInterval = Duration(milliseconds: 100); // 比强制快进慢一些
  static const Duration _initialDelay = Duration(milliseconds: 100);

  /// 连续遇到"当前没有对白可推进"时最多容忍的步数。
  ///
  /// 转场、视频、脚本等待期间短暂没有对白是正常的；但若长期没有对白，说明
  /// 剧情已经卡住，继续空转只会烧掉 UI 线程，此时必须主动停止快进。
  static const int _maxIdleSteps = 40;

  /// 防止同一时刻重入 `_performSkipStep`。
  bool _isStepping = false;

  /// 连续没有对白可推进的步数。
  int _idleSteps = 0;
  
  // 状态回调
  final ValueChanged<bool>? onSkipStateChanged;
  final bool Function()? canSkip; // 检查是否可以快进的回调
  
  ReadTextSkipManager({
    required this.gameManager,
    required this.dialogueProgressionManager,
    required this.readTextTracker,
    this.onSkipStateChanged,
    this.canSkip,
  }) {
    // 监听GameManager状态变化
    _gameStateSubscription = gameManager.gameStateStream.listen((gameState) {
      // 如果GameManager的快进状态为false，但我们还在跳过，强制停止跳过
      if (!gameState.isFastForwarding && _isSkipping) {
        print('[ReadTextSkip] GameManager停止快进，同步停止已读文本跳过');
        stopSkipping();
      }
    });
  }
  
  /// 获取当前快进状态
  bool get isSkipping => _isSkipping;
  
  /// 开始跳过已读文本
  void startSkipping() {
    if (_isSkipping) return;
    
    // 检查是否可以快进
    if (canSkip != null && !canSkip!()) {
      return;
    }
    
    //print('📖 开始跳过已读文本 - ReadTextSkipManager实例hashCode: ${hashCode}');
    //print('📖 ReadTextTracker实例hashCode: ${readTextTracker.hashCode}');
    //print('📖 ReadTextTracker当前已读数量: ${readTextTracker.readCount}');
    _isSkipping = true;
    _idleSteps = 0;
    onSkipStateChanged?.call(true);
    
    // 设置GameManager为快进模式（用于跳过动画等）
    gameManager.setFastForwardMode(true);
    
    // 启动快进计时器
    _skipTimer = Timer.periodic(_skipInterval, (timer) {
      _performSkipStep();
    });
  }
  
  /// 停止跳过已读文本
  void stopSkipping() {
    if (!_isSkipping) return;
    
    //print('⏹️  停止跳过已读文本');
    _isSkipping = false;
    _idleSteps = 0;
    onSkipStateChanged?.call(false);
    
    // 退出GameManager快进模式
    gameManager.setFastForwardMode(false);
    
    _skipTimer?.cancel();
    _skipTimer = null;
  }
  
  /// 执行跳过步骤
  ///
  /// 只由 [_skipTimer] 驱动。这里**绝对不能**再排一个自递归的延迟回调来重试：
  /// 定时器每 100ms 触发一次，每次触发在"暂无对白"分支都会再拉起一条独立的
  /// 50ms 自递归链，两条链相互叠加会让调用频率随时间无上限增长（每 100ms 新增
  /// 一条链，每条链每 50ms 再调用一次），最终把 UI 线程彻底占满：画面不再刷新、
  /// 点击毫无反应，只能强杀进程。推进节奏统一交给定时器即可，天然有上界。
  void _performSkipStep() {
    // 检查是否还在跳过状态
    if (!_isSkipping || _isStepping) {
      return;
    }

    _isStepping = true;
    try {
      // 再次检查是否可以跳过
      if (canSkip != null && !canSkip!()) {
        ////print('📖 [DEBUG] canSkip返回false，停止跳过');
        stopSkipping();
        return;
      }

      // 检查当前对话是否已读（推进前检查）
      final currentState = gameManager.currentState;

      if (currentState.dialogue != null && currentState.dialogue!.isNotEmpty) {
        final isCurrentRead = readTextTracker.isRead(
          currentState.speaker,
          currentState.dialogue!,
          gameManager.currentScriptIndex,
        );

        // 如果当前对话未读，停止跳过
        if (!isCurrentRead) {
          //print('📖 遇到未读文本，停止跳过');
          stopSkipping();
          return;
        }
      } else if (currentState.nvlDialogues.isNotEmpty) {
        // NVL模式：检查所有NVL对话是否已读
        final allRead = currentState.nvlDialogues.every((dialogue) {
          return readTextTracker.isRead(
            dialogue.speaker ?? currentState.speaker,
            dialogue.dialogue,
            gameManager.currentScriptIndex,
          );
        });

        if (!allRead) {
          stopSkipping();
          return;
        }
        // 所有NVL文本已读，允许推进
      } else {
        // 当前没有对白（转场/视频/脚本等待中），等定时器的下一次 tick 再看。
        // 但一直等不到对白说明剧情已卡住，主动停止避免空转烧掉 UI 线程。
        _idleSteps++;
        if (_idleSteps >= _maxIdleSteps) {
          print('[ReadTextSkip] 连续 $_idleSteps 步没有可推进的对白，判定剧情停滞并停止快进');
          stopSkipping();
        }
        return;
      }

      _idleSteps = 0;

      // 推进对话（只有确认已读后才推进）
      try {
        dialogueProgressionManager.progressDialogue(isAutomated: true);
      } catch (e) {
        print('跳过已读文本时发生错误: $e');
        stopSkipping();
      }
    } finally {
      _isStepping = false;
    }
  }
  
  /// 切换跳过状态
  void toggleSkipping() {
    if (_isSkipping) {
      stopSkipping();
    } else {
      startSkipping();
    }
  }
  
  /// 检查是否应该自动跳过当前对话
  /// 这个方法可以在对话显示时调用，用于自动跳过已读内容
  bool shouldAutoSkip() {
    if (!_isSkipping) return false;
    
    final currentState = gameManager.currentState;
    if (currentState.dialogue == null || currentState.dialogue!.isEmpty) {
      return false;
    }
    
    return readTextTracker.isRead(
      currentState.speaker, 
      currentState.dialogue!, 
      gameManager.currentScriptIndex
    );
  }
  
  /// 强制停止跳过（由外部逻辑调用）
  void forceStopSkipping() {
    stopSkipping();
    print('[ReadTextSkip] 已读文本跳过被强制停止');
  }
  
  /// 清理资源
  void dispose() {
    stopSkipping();
    _gameStateSubscription?.cancel();
    _gameStateSubscription = null;
  }
}
