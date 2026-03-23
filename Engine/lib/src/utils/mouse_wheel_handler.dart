import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

/// 鼠标滚轮处理器
/// 负责处理游戏中的鼠标滚轮事件:
/// - 向前滚动(向上): 推进对话
/// - 向后滚动(向下): 回退剧情
class MouseWheelHandler {
  /// 向前滚动回调 (推进对话)
  final VoidCallback? onScrollForward;

  /// 向后滚动回调 (回退剧情)
  final VoidCallback? onScrollBackward;

  /// 是否允许处理滚轮事件的检查函数
  final bool Function()? shouldHandleScroll;

  MouseWheelHandler({
    this.onScrollForward,
    this.onScrollBackward,
    this.shouldHandleScroll,
  });

  /// 处理指针信号事件
  void handlePointerSignal(PointerSignalEvent pointerSignal) {
    // 检查是否允许处理滚轮事件
    if (shouldHandleScroll != null && !shouldHandleScroll!()) {
      return;
    }

    // 处理标准的PointerScrollEvent（鼠标滚轮）
    if (pointerSignal is PointerScrollEvent) {
      // 向上滚动 (dy < 0): 前进剧情
      if (pointerSignal.scrollDelta.dy < 0) {
        onScrollForward?.call();
      }
      // 向下滚动 (dy > 0): 回滚剧情
      else if (pointerSignal.scrollDelta.dy > 0) {
        onScrollBackward?.call();
      }
    }
    // 处理macOS触控板事件
    else if (pointerSignal.toString().contains('Scroll')) {
      // 触控板滚动事件，默认推进剧情
      onScrollForward?.call();
    }
  }
}

/// 鼠标滚轮监听器Widget
/// 包装一个子Widget并添加鼠标滚轮事件处理
class MouseWheelListener extends StatelessWidget {
  final Widget child;
  final MouseWheelHandler handler;

  const MouseWheelListener({
    super.key,
    required this.child,
    required this.handler,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: handler.handlePointerSignal,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
