import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

class AnimatedTooltip extends StatefulWidget {
  final String text;
  final double scale;
  final SakiEngineConfig config;
  final GlobalKey menuKey;
  final int buttonIndex;
  final bool isVisible;

  const AnimatedTooltip({
    super.key,
    required this.text,
    required this.scale,
    required this.config,
    required this.menuKey,
    required this.buttonIndex,
    required this.isVisible,
  });

  @override
  State<AnimatedTooltip> createState() => _AnimatedTooltipState();
}

class _AnimatedTooltipState extends State<AnimatedTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-10.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    // 根据初始状态决定动画方向
    if (widget.isVisible) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 更新按钮尺寸参数以匹配新的正方形按钮
    const double buttonSize = 48.0; // 正方形按钮尺寸
    const double buttonVerticalMargin = 4.0; // 按钮上下边距
    
    // 计算每个按钮单元的总高度(按钮 + 上下边距)
    final buttonUnitHeight = (buttonSize + buttonVerticalMargin * 2) * widget.scale;
    
    // 计算气泡的垂直位置：菜单顶部偏移 + 按钮索引 * 单元高度 + 按钮中心位置
    double topOffset = 20 * widget.scale + (widget.buttonIndex * buttonUnitHeight) + (buttonSize * widget.scale / 2) - 15 * widget.scale;

    return Positioned(
      left: (20 + 60) * widget.scale,
      top: topOffset,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return IgnorePointer(
            ignoring: true, // 始终忽略触摸事件，避免阻挡底层的鼠标检测
            child: Transform.translate(
              offset: Offset(_slideAnimation.value.dx * widget.scale, _slideAnimation.value.dy),
              child: Transform.scale(
                scale: _scaleAnimation.value,
                alignment: Alignment.centerLeft,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16 * widget.scale,
                      vertical: 10 * widget.scale,
                    ),
                    decoration: BoxDecoration(
                      color: widget.config.themeColors.background.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(widget.config.baseWindowBorder > 0 
                          ? widget.config.baseWindowBorder * widget.scale 
                          : 0 * widget.scale),
                      border: Border.all(
                        color: widget.config.themeColors.primary.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: (0.25 * _opacityAnimation.value).clamp(0.0, 1.0)),
                          blurRadius: 12 * widget.scale * _opacityAnimation.value,
                          offset: Offset(-2 * widget.scale, 2 * widget.scale),
                        ),
                        BoxShadow(
                          color: widget.config.themeColors.primary.withValues(alpha: (0.1 * _opacityAnimation.value).clamp(0.0, 1.0)),
                          blurRadius: 6 * widget.scale * _opacityAnimation.value,
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 4 * widget.scale,
                          height: 20 * widget.scale,
                          decoration: BoxDecoration(
                            color: widget.config.themeColors.primary.withValues(alpha: (0.6 * _opacityAnimation.value).clamp(0.0, 1.0)),
                            borderRadius: BorderRadius.circular(2 * widget.scale),
                          ),
                        ),
                        SizedBox(width: 12 * widget.scale),
                        Text(
                          widget.text.isEmpty ? ' ' : widget.text, // 防止空文本导致布局问题
                          style: widget.config.quickMenuTextStyle.copyWith(
                            fontSize: widget.config.quickMenuTextStyle.fontSize! * widget.scale * 1.1,
                            color: widget.config.themeColors.primary.withValues(alpha: (0.9 * _opacityAnimation.value).clamp(0.0, 1.0)),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}