import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/effects/scene_presentation_theme.dart';

/// 全局转场覆盖层管理器
/// 使用覆盖层方式实现黑场过渡，与场景切换分离
class TransitionOverlayManager {
  static TransitionOverlayManager? _instance;
  static TransitionOverlayManager get instance => _instance ??= TransitionOverlayManager._();
  
  TransitionOverlayManager._();
  
  OverlayEntry? _overlayEntry;
  bool _isTransitioning = false;
  Completer<void>? _completer;

  /// 执行转场过渡
  /// [context] 用于创建覆盖层的上下文
  /// [onMidTransition] 在黑屏最深时执行的回调（切换场景时机）
  /// [duration] 总过渡时长
  ///
  /// 调用方（剧情执行器）会 await 返回的 Future 才会继续推进，所以这里必须保证
  /// 任何情况下 Future 都会完成、且 [onMidTransition] 一定会被调用。少了任何
  /// 一个，剧情就会停在一个"永远不会结束的转场"上：对白不再出现、点击也毫无
  /// 反应，只能强杀进程。
  Future<void> transition({
    required BuildContext context,
    required VoidCallback onMidTransition,
    Duration duration = const Duration(milliseconds: 800),
  }) async {
    if (_isTransitioning) {
      // 已有一个转场在播。不要静默丢弃这次请求，否则本次场景切换会丢失且
      // 调用方永远等不到 onMidTransition：立刻提交状态并报告完成。
      _invokeSafely(onMidTransition);
      return;
    }

    _isTransitioning = true;
    final completer = Completer<void>();
    _completer = completer;

    try {
      final backdropColor = ScenePresentationTheme.backdropColorOf(context);
      // 创建覆盖层
      _overlayEntry = OverlayEntry(
        builder: (context) => _TransitionOverlay(
          backdropColor: backdropColor,
          duration: duration,
          onMidTransition: () => _invokeSafely(onMidTransition),
          onComplete: _finishTransition,
        ),
      );

      // 插入覆盖层
      Overlay.of(context).insert(_overlayEntry!);
    } catch (error, stackTrace) {
      // 界面已销毁导致取不到 Overlay 等异常，绝不能让 _isTransitioning 永远
      // 停在 true：那会丢弃之后所有转场，让剧情再也无法恢复。
      debugPrint('[TransitionManager] 创建转场覆盖层失败: $error\n$stackTrace');
      _invokeSafely(onMidTransition);
      _finishTransition();
    }

    return completer.future;
  }

  /// 结束转场：清理覆盖层、复位状态并唤醒等待中的调用方。
  void _finishTransition() {
    _removeOverlay();
    _isTransitioning = false;
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _invokeSafely(VoidCallback callback) {
    try {
      callback();
    } catch (error, stackTrace) {
      debugPrint('[TransitionManager] 转场回调异常: $error\n$stackTrace');
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  bool get isTransitioning => _isTransitioning;
}

/// Scene转场管理器（独立于全局转场）
class SceneTransitionManager {
  static SceneTransitionManager? _instance;
  static SceneTransitionManager get instance => _instance ??= SceneTransitionManager._();
  
  SceneTransitionManager._();
  
  OverlayEntry? _overlayEntry;
  bool _isTransitioning = false;
  Completer<void>? _completer;

  /// 执行Scene转场过渡
  ///
  /// 与 [TransitionOverlayManager] 同样保证：Future 必定完成、[onMidTransition]
  /// 必定被调用，任何异常都不会把 [_isTransitioning] 永久留在 true。
  Future<void> transition({
    required BuildContext context,
    required VoidCallback onMidTransition,
    Duration duration = const Duration(milliseconds: 800),
  }) async {
    if (_isTransitioning) {
      _invokeSafely(onMidTransition);
      return;
    }

    _isTransitioning = true;
    final completer = Completer<void>();
    _completer = completer;

    try {
      final backdropColor = ScenePresentationTheme.backdropColorOf(context);
      // 创建覆盖层
      _overlayEntry = OverlayEntry(
        builder: (context) => _TransitionOverlay(
          backdropColor: backdropColor,
          duration: duration,
          onMidTransition: () => _invokeSafely(onMidTransition),
          onComplete: _finishTransition,
        ),
      );

      // 插入覆盖层
      Overlay.of(context).insert(_overlayEntry!);
    } catch (error, stackTrace) {
      debugPrint('[SceneTransition] 创建转场覆盖层失败: $error\n$stackTrace');
      _invokeSafely(onMidTransition);
      _finishTransition();
    }

    return completer.future;
  }

  void _finishTransition() {
    _removeOverlay();
    _isTransitioning = false;
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _invokeSafely(VoidCallback callback) {
    try {
      callback();
    } catch (error, stackTrace) {
      debugPrint('[SceneTransition] 转场回调异常: $error\n$stackTrace');
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  bool get isTransitioning => _isTransitioning;
}

/// 转场覆盖层Widget
class _TransitionOverlay extends StatefulWidget {
  final Color backdropColor;
  final Duration duration;
  final VoidCallback onMidTransition;
  final VoidCallback onComplete;
  
  const _TransitionOverlay({
    required this.backdropColor,
    required this.duration,
    required this.onMidTransition,
    required this.onComplete,
  });
  
  @override
  State<_TransitionOverlay> createState() => _TransitionOverlayState();
}

class _TransitionOverlayState extends State<_TransitionOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeOutAnimation;
  late Animation<double> _fadeInAnimation;
  bool _midTransitionExecuted = false;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    
    // 前半段：淡出到黑屏 (0 -> 1)
    _fadeOutAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
    ));
    
    // 后半段：从黑屏淡入 (1 -> 0)
    _fadeInAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));
    
    _controller.addListener(_onAnimationUpdate);
    _controller.addStatusListener(_onAnimationStatus);
    
    // 开始动画
    _controller.forward();
  }
  
  void _onAnimationUpdate() {
    // 在动画中点执行场景切换
    if (!_midTransitionExecuted && _controller.value >= 0.5) {
      _midTransitionExecuted = true;
      widget.onMidTransition();
    }
  }
  
  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onComplete();
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 计算当前黑屏不透明度
        double opacity;
        if (_controller.value <= 0.5) {
          // 前半段：淡出到黑屏
          opacity = _fadeOutAnimation.value;
        } else {
          // 后半段：从黑屏淡入
          opacity = _fadeInAnimation.value;
        }
        
        return Material(
          color: widget.backdropColor.withValues(alpha: opacity),
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
          ),
        );
      },
    );
  }
}

/// 便捷的转场Widget包装器（如果需要局部使用）
class TransitionWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTransitionRequested;
  
  const TransitionWrapper({
    super.key,
    required this.child,
    this.onTransitionRequested,
  });
  
  @override
  Widget build(BuildContext context) {
    return child;
  }
}
