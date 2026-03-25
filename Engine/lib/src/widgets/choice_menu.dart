import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

class ChoiceMenu extends StatefulWidget {
  final MenuNode menuNode;
  final Function(String) onChoiceSelected;
  final bool isFastForwarding; // 新增：快进状态

  const ChoiceMenu({
    super.key,
    required this.menuNode,
    required this.onChoiceSelected,
    this.isFastForwarding = false, // 新增：默认不快进
  });

  @override
  State<ChoiceMenu> createState() => _ChoiceMenuState();
}

class _ChoiceMenuState extends State<ChoiceMenu>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // 开始入场动画
    if (widget.isFastForwarding) {
      // 快进模式下直接跳到结尾
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 处理选择时的退出动画
  void _handleChoice(String targetLabel) async {
    if (widget.isFastForwarding) {
      // 快进模式下跳过退出动画
      if (mounted) {
        widget.onChoiceSelected(targetLabel);
      }
    } else {
      await _controller.reverse();
      if (mounted) {
        widget.onChoiceSelected(targetLabel);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = context.scaleFor(ComponentType.menu);
    final config = SakiEngineConfig();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.menuNode.choices
                    .asMap()
                    .entries
                    .map(
                      (entry) {
                        final index = entry.key;
                        final choice = entry.value;
                        return TweenAnimationBuilder<double>(
                          duration: widget.isFastForwarding 
                              ? Duration.zero // 快进模式下跳过动画
                              : Duration(milliseconds: 100 + index * 50),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            // 快进模式下直接显示完成状态
                            final animValue = widget.isFastForwarding ? 1.0 : value;
                            return Transform.translate(
                              offset: Offset(0, 20 * (1 - animValue)),
                              child: Opacity(
                                opacity: animValue,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12 * scale),
                                  child: _ChoiceButton(
                                    text: choice.text,
                                    onPressed: () => _handleChoice(choice.targetLabel),
                                    scale: scale,
                                    config: config,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChoiceButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final double scale;
  final SakiEngineConfig config;

  const _ChoiceButton({
    required this.text,
    required this.onPressed,
    required this.scale,
    required this.config,
  });

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _hoverController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  final _uiSoundManager = UISoundManager();

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
    ));
    
    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _hoverController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _uiSoundManager.playButtonClick();
                widget.onPressed();
              },
              onHover: (hovering) {
                setState(() => _isHovered = hovering);
                if (hovering) {
                  _uiSoundManager.playButtonHover();
                  _hoverController.forward();
                } else {
                  _hoverController.reverse();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: MediaQuery.of(context).size.width * 0.5,
                padding: EdgeInsets.symmetric(
                  horizontal: 24 * widget.scale,
                  vertical: 16 * widget.scale,
                ),
                decoration: BoxDecoration(
                  color: _isHovered 
                    ? HSLColor.fromColor(widget.config.themeColors.background)
                        .withLightness((HSLColor.fromColor(widget.config.themeColors.background).lightness - 0.1).clamp(0.0, 1.0))
                        .toColor().withOpacity(0.9)
                    : widget.config.themeColors.background.withOpacity(0.9),
                  border: Border.all(
                    color: widget.config.themeColors.primary.withOpacity(0.5 + 0.3 * _glowAnimation.value),
                    width: 1 + _glowAnimation.value,
                  ),
                  borderRadius: BorderRadius.circular(widget.config.baseWindowBorder > 0 
                      ? widget.config.baseWindowBorder * widget.scale 
                      : 0 * widget.scale),
                  boxShadow: _isHovered ? [
                    BoxShadow(
                      color: widget.config.themeColors.primary.withOpacity(0.3 * _glowAnimation.value),
                      blurRadius: 8 * widget.scale * _glowAnimation.value,
                      spreadRadius: 2 * widget.scale * _glowAnimation.value,
                    ),
                  ] : null,
                ),
                child: Text(
                  widget.text,
                  textAlign: TextAlign.center,
                  style: widget.config.choiceTextStyle.copyWith(
                    fontSize: widget.config.choiceTextStyle.fontSize! * widget.scale,
                    color: widget.config.themeColors.primary,
                    fontWeight: _isHovered ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
