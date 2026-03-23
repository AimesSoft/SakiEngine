import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/widgets/mobile_quick_menu.dart';

/// 移动端触屏控制器
/// 处理移动端特有的触屏交互：
/// - 点击快捷菜单区域唤出菜单
/// - 长按屏幕隐藏UI
/// - 点击其他区域时触发菜单延迟隐藏
class MobileTouchController extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLongPress; // 长按回调
  final VoidCallback? onOtherAreaTap; // 其他区域点击回调（用于推进对话等）
  final double quickMenuAreaWidth; // 快捷菜单区域宽度（从左侧开始）
  final bool hasOverlayOpen; // 是否有弹窗打开（新增参数）

  const MobileTouchController({
    super.key,
    required this.child,
    this.onLongPress,
    this.onOtherAreaTap,
    this.quickMenuAreaWidth = 100.0,
    this.hasOverlayOpen = false, // 默认为false
  });

  @override
  State<MobileTouchController> createState() => _MobileTouchControllerState();
}

class _MobileTouchControllerState extends State<MobileTouchController> {
  Timer? _longPressTimer;
  Offset? _pressStartPosition;
  static const Duration _longPressDuration = Duration(milliseconds: 500);
  static const double _longPressMoveThreshold = 10.0; // 长按时允许的最大移动距离
  bool _isLongPressing = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    // 记录按下位置
    _pressStartPosition = event.position;
    _isLongPressing = false;

    // 启动长按计时器
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (mounted && _pressStartPosition != null) {
        _isLongPressing = true;
        // 触发长按回调
        widget.onLongPress?.call();
      }
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    // 如果移动距离超过阈值，取消长按
    if (_pressStartPosition != null && !_isLongPressing) {
      final distance = (event.position - _pressStartPosition!).distance;
      if (distance > _longPressMoveThreshold) {
        _longPressTimer?.cancel();
        _pressStartPosition = null;
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    // 取消长按计时器
    _longPressTimer?.cancel();

    // 如果是长按，不处理点击事件
    if (_isLongPressing) {
      _isLongPressing = false;
      _pressStartPosition = null;
      return;
    }

    // 如果有弹窗打开，不处理点击事件（防止点击穿透）
    if (widget.hasOverlayOpen) {
      _pressStartPosition = null;
      return;
    }

    // 检查是否是快速点击（非长按）
    if (_pressStartPosition != null) {
      final tapPosition = event.position;

      // 检查是否点击在快捷菜单区域
      if (tapPosition.dx < widget.quickMenuAreaWidth) {
        // 点击快捷菜单区域，显示菜单
        MobileQuickMenu.showMenu();
      } else {
        // 点击其他区域（例如推进对话）
        widget.onOtherAreaTap?.call();
        // 触发快捷菜单延迟隐藏
        _scheduleQuickMenuHide();
      }
    }

    _pressStartPosition = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    // 取消时清理状态
    _longPressTimer?.cancel();
    _pressStartPosition = null;
    _isLongPressing = false;
  }

  /// 延迟隐藏快捷菜单（如果已显示）
  void _scheduleQuickMenuHide() {
    // 通过快捷菜单的静态方法触发延迟隐藏
    MobileQuickMenu.scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}