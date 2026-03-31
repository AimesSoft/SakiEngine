import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/utils/dialogue_progression_manager.dart';

/// 快进管理器
/// 
/// 负责处理视觉小说的快进功能：
/// - 监听Ctrl键的按下和释放
/// - 在快进模式下自动推进对话
/// - 管理快进速度和状态
class FastForwardManager {
  final DialogueProgressionManager dialogueProgressionManager;
  
  // 快进状态
  bool _isFastForwarding = false;
  Timer? _fastForwardTimer;
  
  // 快进配置
  static const Duration _fastForwardInterval = Duration(milliseconds: 50); // 快进间隔，50ms推进一次，非常快
  static const Duration _initialDelay = Duration(milliseconds: 50); // 初始延迟减少，更快响应
  
  // Ctrl键状态监听
  bool _isCtrlPressed = false;
  Timer? _keyHoldTimer;
  
  // 状态回调
  final ValueChanged<bool>? onFastForwardStateChanged;
  final bool Function()? canFastForward; // 检查是否可以快进的回调
  final Function(bool)? setGameManagerFastForward; // 设置GameManager快进状态的回调
  
  FastForwardManager({
    required this.dialogueProgressionManager,
    this.onFastForwardStateChanged,
    this.canFastForward,
    this.setGameManagerFastForward,
  });
  
  /// 获取当前快进状态
  bool get isFastForwarding => _isFastForwarding;
  
  /// 开始监听键盘事件
  void startListening() {
    // 在上级Widget中处理键盘监听，这里提供检查方法
  }
  
  /// 停止监听键盘事件
  void stopListening() {
    _stopFastForward();
  }
  
  /// 处理键盘按键事件
  bool handleKeyEvent(KeyEvent event) {
    // 检查是否是Ctrl键
    final isCtrlKey = event.logicalKey == LogicalKeyboardKey.controlLeft ||
                      event.logicalKey == LogicalKeyboardKey.controlRight;
    
    if (!isCtrlKey) return false;
    
    if (event is KeyDownEvent) {
      _handleCtrlPressed();
    } else if (event is KeyUpEvent) {
      _handleCtrlReleased();
    }
    
    return true; // 表示已处理该键盘事件
  }
  
  /// 处理Ctrl键按下
  void _handleCtrlPressed() {
    if (_isCtrlPressed) return; // 避免重复处理
    
    _isCtrlPressed = true;
    
    // 设置延迟，避免误触快进
    _keyHoldTimer?.cancel();
    _keyHoldTimer = Timer(_initialDelay, () {
      if (_isCtrlPressed && !_isFastForwarding) {
        _startFastForward();
      }
    });
  }
  
  /// 处理Ctrl键释放
  void _handleCtrlReleased() {
    _isCtrlPressed = false;
    _keyHoldTimer?.cancel();
    _keyHoldTimer = null;
    
    if (_isFastForwarding) {
      _stopFastForward();
    }
  }
  
  /// 开始快进
  void _startFastForward() {
    if (_isFastForwarding) return;
    
    // 检查是否可以快进
    if (canFastForward != null && !canFastForward!()) {
      return;
    }
    
    //print('🚀 开始快进');
    _isFastForwarding = true;
    onFastForwardStateChanged?.call(true);
    setGameManagerFastForward?.call(true); // 通知GameManager进入快进模式
    
    // 立即执行第一次推进
    _performFastForwardStep();
    
    // 启动快进计时器
    _fastForwardTimer = Timer.periodic(_fastForwardInterval, (timer) {
      _performFastForwardStep();
    });
  }
  
  /// 停止快进
  void _stopFastForward() {
    if (!_isFastForwarding) return;
    
    //print('⏹️  停止快进');
    _isFastForwarding = false;
    onFastForwardStateChanged?.call(false);
    setGameManagerFastForward?.call(false); // 通知GameManager退出快进模式
    
    _fastForwardTimer?.cancel();
    _fastForwardTimer = null;
  }
  
  /// 执行快进步骤
  void _performFastForwardStep() {
    // 检查是否还在快进状态
    if (!_isFastForwarding) return;
    
    // 再次检查是否可以快进（可能状态已改变）
    if (canFastForward != null && !canFastForward!()) {
      _stopFastForward();
      return;
    }
    
    // 推进对话
    try {
      dialogueProgressionManager.progressDialogue(isAutomated: true);
    } catch (e) {
      print('快进推进对话时发生错误: $e');
      // 出错时停止快进
      _stopFastForward();
    }
  }
  
  /// 手动开始快进（用于UI按钮等）
  void startFastForward() {
    _isCtrlPressed = true; // 模拟Ctrl键按下
    _startFastForward();
  }
  
  /// 手动停止快进（用于UI按钮等）
  void stopFastForward() {
    _isCtrlPressed = false;
    _stopFastForward();
  }
  
  /// 切换快进状态
  void toggleFastForward() {
    if (_isFastForwarding) {
      stopFastForward();
    } else {
      startFastForward();
    }
  }
  
  /// 强制停止快进（由外部逻辑调用，如检测到章节场景）
  void forceStopFastForward() {
    _isCtrlPressed = false;
    _stopFastForward();
    print('[FastForward] 快进被强制停止（检测到重要场景）');
  }
  
  /// 清理资源
  void dispose() {
    _stopFastForward();
    _keyHoldTimer?.cancel();
    _keyHoldTimer = null;
  }
}
