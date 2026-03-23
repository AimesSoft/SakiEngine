import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

/// 全局转场覆盖层管理器
/// 使用覆盖层方式实现黑场过渡，与场景切换分离
class TransitionOverlayManager {
  static TransitionOverlayManager? _instance;
  static TransitionOverlayManager get instance => _instance ??= TransitionOverlayManager._();
  
  TransitionOverlayManager._();
  
  OverlayEntry? _overlayEntry;
  bool _isTransitioning = false;
  
  /// 执行转场过渡
  /// [context] 用于创建覆盖层的上下文
  /// [onMidTransition] 在黑屏最深时执行的回调（切换场景时机）
  /// [duration] 总过渡时长
  Future<void> transition({
    required BuildContext context,
    required VoidCallback onMidTransition,
    Duration duration = const Duration(milliseconds: 800),
  }) async {
    //print('[TransitionManager] 请求转场，当前状态: isTransitioning=$_isTransitioning');
    if (_isTransitioning) return;
    
    _isTransitioning = true;
    //print('[TransitionManager] 开始转场，时长: ${duration.inMilliseconds}ms');
    
    final completer = Completer<void>();
    
    // 创建覆盖层
    _overlayEntry = OverlayEntry(
      builder: (context) => _TransitionOverlay(
        duration: duration,
        onMidTransition: onMidTransition,
        onComplete: () {
          //print('[TransitionManager] 转场完成，移除覆盖层');
          _removeOverlay();
          _isTransitioning = false;
          completer.complete();
        },
      ),
    );
    
    // 插入覆盖层
    //print('[TransitionManager] 插入转场覆盖层');
    Overlay.of(context).insert(_overlayEntry!);
    
    return completer.future;
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
  
  /// 执行Scene转场过渡
  Future<void> transition({
    required BuildContext context,
    required VoidCallback onMidTransition,
    Duration duration = const Duration(milliseconds: 800),
  }) async {
    //print('[SceneTransition] 请求scene转场，当前状态: isTransitioning=$_isTransitioning');
    if (_isTransitioning) return;
    
    _isTransitioning = true;
    //print('[SceneTransition] 开始scene转场，时长: ${duration.inMilliseconds}ms');
    
    final completer = Completer<void>();
    
    // 创建覆盖层
    _overlayEntry = OverlayEntry(
      builder: (context) => _TransitionOverlay(
        duration: duration,
        onMidTransition: onMidTransition,
        onComplete: () {
          //print('[SceneTransition] scene转场完成，移除覆盖层');
          _removeOverlay();
          _isTransitioning = false;
          completer.complete();
        },
      ),
    );
    
    // 插入覆盖层
    //print('[SceneTransition] 插入scene转场覆盖层');
    Overlay.of(context).insert(_overlayEntry!);
    
    return completer.future;
  }
  
  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
  
  bool get isTransitioning => _isTransitioning;
}

/// 转场覆盖层Widget
class _TransitionOverlay extends StatefulWidget {
  final Duration duration;
  final VoidCallback onMidTransition;
  final VoidCallback onComplete;
  
  const _TransitionOverlay({
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
          color: Colors.black.withOpacity(opacity),
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