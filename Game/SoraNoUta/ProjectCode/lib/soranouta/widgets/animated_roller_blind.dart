import 'package:flutter/material.dart';

/// 菜单项渐显动画包装器（视觉小说风格）
/// 从右侧轻微滑入并淡入，支持延迟启动
class AnimatedRollerBlind extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final bool startAnimation; // 控制动画是否开始
  final int index; // 新增：按钮索引，用于错开动画时机

  const AnimatedRollerBlind({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600), // 缩短为600ms
    this.curve = Curves.easeOutCubic,
    this.startAnimation = true, // 默认立即开始
    this.index = 0, // 默认索引为0
  });

  @override
  State<AnimatedRollerBlind> createState() => _AnimatedRollerBlindState();
}

class _AnimatedRollerBlindState extends State<AnimatedRollerBlind>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    // 淡入动画
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    // 轻微的从右滑入动画（只移动少量距离）
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.03, 0), // 从右侧3%的位置开始，更轻微
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // 使用更柔和的缓动曲线
    ));

    // 根据索引延迟启动动画，制造错落效果
    if (widget.startAnimation) {
      Future.delayed(Duration(milliseconds: widget.index * 100), () { // 改为100ms间隔，更从容
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void didUpdateWidget(AnimatedRollerBlind oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当 startAnimation 从 false 变为 true 时，启动动画
    if (!oldWidget.startAnimation && widget.startAnimation) {
      Future.delayed(Duration(milliseconds: widget.index * 100), () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
