import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

class SquareIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double? size;
  final double? iconSize;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final Color? hoverBackgroundColor;
  final Color? hoverBorderColor;
  final Color? hoverIconColor;
  final bool enabled;
  final double borderRadius;
  final double borderWidth;
  final Duration animationDuration;
  final Curve animationCurve;
  final double hoverScale;

  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size,
    this.iconSize,
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.hoverBackgroundColor,
    this.hoverBorderColor,
    this.hoverIconColor,
    this.enabled = true,
    this.borderRadius = 0.5,
    this.borderWidth = 1,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeInOut,
    this.hoverScale = 1.1,
  });

  @override
  State<SquareIconButton> createState() => _SquareIconButtonState();
}

class _SquareIconButtonState extends State<SquareIconButton> {
  bool _isHovered = false;
  final _uiSoundManager = UISoundManager();

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final buttonSize = widget.size ?? 24.0;
    final iconSize = widget.iconSize ?? buttonSize * 0.6;

    final backgroundColor = widget.backgroundColor ??
        config.themeColors.background.withOpacity(0.9);
    final borderColor = widget.borderColor ??
        config.themeColors.primary.withOpacity(0.3);
    final iconColor = widget.iconColor ??
        config.themeColors.primary.withOpacity(0.7);

    final hoverBackgroundColor = widget.hoverBackgroundColor ??
        config.themeColors.primary.withOpacity(0.15);
    final hoverBorderColor = widget.hoverBorderColor ??
        config.themeColors.primary.withOpacity(0.6);
    final hoverIconColor = widget.hoverIconColor ??
        config.themeColors.primary;

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.enabled ? () {
          _uiSoundManager.playButtonClick();
          widget.onTap();
        } : null,
        onHover: widget.enabled ? (hovering) {
          if (mounted) {
            setState(() {
              _isHovered = hovering;
            });
            if (hovering) {
              _uiSoundManager.playButtonHover();
            }
          }
        } : null,
        borderRadius: BorderRadius.circular(
          config.baseWindowBorder * widget.borderRadius
        ),
        child: AnimatedContainer(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: _isHovered ? hoverBackgroundColor : backgroundColor,
            borderRadius: BorderRadius.circular(
              config.baseWindowBorder * widget.borderRadius
            ),
            border: Border.all(
              color: _isHovered ? hoverBorderColor : borderColor,
              width: widget.borderWidth,
            ),
          ),
          child: AnimatedScale(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
            scale: _isHovered && widget.enabled ? widget.hoverScale : 1.0,
            child: Icon(
              widget.icon,
              size: iconSize,
              color: widget.enabled
                  ? (_isHovered ? hoverIconColor : iconColor)
                  : iconColor.withOpacity(0.3),
            ),
          ),
        ),
      ),
    );

    return button;
  }
}