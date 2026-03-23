import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

/// 按钮布局配置
class MenuButtonsLayoutConfig {
  final bool isVertical;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisAlignment mainAxisAlignment;
  final double spacing;
  final EdgeInsetsGeometry? padding;
  final Alignment? alignment;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const MenuButtonsLayoutConfig({
    this.isVertical = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisAlignment = MainAxisAlignment.end,
    this.spacing = 20,
    this.padding,
    this.alignment,
    this.top,
    this.bottom,
    this.left,
    this.right,
  });
}

/// 可配置的菜单按钮配置类
class MenuButtonConfig {
  final String text;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? hoverColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final BoxBorder? border;
  final List<BoxShadow>? shadows;
  final TextStyle? textStyle;
  final Widget? icon;
  final bool enableHoverAnimation;
  final Duration animationDuration;

  const MenuButtonConfig({
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.hoverColor,
    this.borderRadius,
    this.padding,
    this.border,
    this.shadows,
    this.textStyle,
    this.icon,
    this.enableHoverAnimation = true,
    this.animationDuration = const Duration(milliseconds: 200),
  });
}

/// 可配置的菜单按钮控件
class ConfigurableMenuButton extends StatefulWidget {
  final MenuButtonConfig config;
  final double scale;

  const ConfigurableMenuButton({
    super.key,
    required this.config,
    required this.scale,
  });

  @override
  State<ConfigurableMenuButton> createState() => _ConfigurableMenuButtonState();
}

class _ConfigurableMenuButtonState extends State<ConfigurableMenuButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  AnimationController? _animationController;
  Animation<double>? _scaleAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.config.enableHoverAnimation) {
      _animationController = AnimationController(
        duration: widget.config.animationDuration,
        vsync: this,
      );
      _scaleAnimation = Tween<double>(
        begin: 1.0,
        end: 1.05,
      ).animate(CurvedAnimation(
        parent: _animationController!,
        curve: Curves.easeInOut,
      ));
    }
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.config.onPressed,
        onHover: (hovering) {
          setState(() => _isHovered = hovering);
          if (widget.config.enableHoverAnimation && _animationController != null) {
            if (hovering) {
              _animationController!.forward();
            } else {
              _animationController!.reverse();
            }
          }
        },
        child: Container(
          width: 200 * widget.scale,
          padding: widget.config.padding ?? EdgeInsets.symmetric(
            horizontal: 24 * widget.scale,
            vertical: 16 * widget.scale,
          ),
          decoration: BoxDecoration(
            color: _isHovered && widget.config.hoverColor != null
                ? widget.config.hoverColor
                : widget.config.backgroundColor ?? Colors.grey.withValues(alpha: 0.8),
            border: widget.config.border,
            borderRadius: BorderRadius.circular(
              widget.config.borderRadius ?? 0,
            ),
            boxShadow: widget.config.shadows,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.config.icon != null) ...[
                widget.config.icon!,
                SizedBox(width: 8 * widget.scale),
              ],
              Text(
                widget.config.text,
                textAlign: TextAlign.center,
                style: widget.config.textStyle ?? TextStyle(
                  fontFamily: 'SourceHanSansCN',
                  fontSize: 28 * widget.scale,
                  color: widget.config.textColor ?? Colors.white,
                  letterSpacing: 2,
                  fontWeight: _isHovered ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 如果启用动画且有动画控制器，添加动画效果
    if (widget.config.enableHoverAnimation && _scaleAnimation != null) {
      return AnimatedBuilder(
        animation: _scaleAnimation!,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation!.value,
            child: button,
          );
        },
      );
    }

    return button;
  }
}