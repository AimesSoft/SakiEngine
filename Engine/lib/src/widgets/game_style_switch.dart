import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

class GameStyleSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double scale;
  final SakiEngineConfig config;

  const GameStyleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.scale,
    required this.config,
  });

  @override
  State<GameStyleSwitch> createState() => _GameStyleSwitchState();
}

class _GameStyleSwitchState extends State<GameStyleSwitch> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _pulseController;
  late Animation<Color?> _colorAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  bool _isHovered = false;
  final _uiSoundManager = UISoundManager();

  @override
  void initState() {
    super.initState();
    
    // 主动画控制器 - 控制开关状态切换
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // 脉冲动画控制器 - 控制悬浮时的呼吸效果
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // 滑动动画 - 指示器的位置
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    // 缩放动画 - 点击时的弹性效果
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
    ));

    // 颜色动画
    _colorAnimation = ColorTween(
      begin: widget.config.themeColors.onSurfaceVariant.withOpacity(0.3),
      end: widget.config.themeColors.primary.withOpacity(0.8),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // 脉冲动画 - 开启状态时的呼吸效果
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // 发光动画
    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    if (widget.value) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(GameStyleSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 重新初始化颜色动画以响应主题变化
    _colorAnimation = ColorTween(
      begin: widget.config.themeColors.onSurfaceVariant.withOpacity(0.3),
      end: widget.config.themeColors.primary.withOpacity(0.8),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _animationController.forward();
      } else {
        _animationController.reverse();
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _uiSoundManager.playButtonClick();
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final switchWidth = 120 * widget.scale;
    final switchHeight = 48 * widget.scale;
    final knobSize = 36 * widget.scale;
    final padding = 6 * widget.scale;
    final knobTravel = switchWidth - knobSize - padding * 2;
    final knobBaseTop = (switchHeight - knobSize) / 2 - 2 * widget.scale;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _uiSoundManager.playButtonHover();
        if (widget.value) {
          _pulseController.repeat(reverse: true);
        }
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _pulseController.stop();
        _pulseController.reset();
      },
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_animationController, _pulseController]),
          builder: (context, child) {
            return Transform.scale(
              scale: _isHovered ? 1.05 : 1.0,
              child: Container(
                width: switchWidth,
                height: switchHeight,
                decoration: BoxDecoration(
                  color: widget.config.themeColors.surface.withOpacity(0.5),
                  border: Border.all(
                    color: _isHovered 
                      ? widget.config.themeColors.primary.withOpacity(0.8)
                      : widget.config.themeColors.primary.withOpacity(0.4),
                    width: 2 * widget.scale,
                  ),
                  boxShadow: [
                    // 基础阴影
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4 * widget.scale,
                      offset: Offset(0, 2 * widget.scale),
                    ),
                    // 发光效果（仅在激活且悬浮时）
                    if (widget.value && _isHovered)
                      BoxShadow(
                        color: widget.config.themeColors.primary.withOpacity(0.3 * _glowAnimation.value * _pulseAnimation.value),
                        blurRadius: 12 * widget.scale * _pulseAnimation.value,
                        offset: Offset(0, 0),
                      ),
                    // 悬停时的额外发光
                    if (_isHovered)
                      BoxShadow(
                        color: widget.config.themeColors.primary.withOpacity(0.2),
                        blurRadius: 8 * widget.scale,
                        offset: Offset(0, 2 * widget.scale),
                      ),
                  ],
                ),
                child: Stack(
                  children: [
                    // 动态背景渐变
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _colorAnimation.value!.withOpacity(0.1),
                            _colorAnimation.value!.withOpacity(0.3 * _glowAnimation.value),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                    // 滑动的指示器 - 使用弹性动画
                    AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        return Positioned(
                          left: padding + knobTravel * _slideAnimation.value,
                          top: knobBaseTop,
                          child: Transform.scale(
                            scale: 1.0 + 0.1 * _scaleAnimation.value,
                            child: Container(
                              width: knobSize,
                              height: knobSize,
                              decoration: BoxDecoration(
                                color: widget.config.themeColors.background,
                                border: Border.all(
                                  color: widget.config.themeColors.primary.withOpacity(0.8),
                                  width: 2 * widget.scale,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4 * widget.scale,
                                    offset: Offset(0, 2 * widget.scale),
                                  ),
                                  if (widget.value && _isHovered)
                                    BoxShadow(
                                      color: widget.config.themeColors.primary.withOpacity(0.4 * _pulseAnimation.value),
                                      blurRadius: 8 * widget.scale * _pulseAnimation.value,
                                      offset: Offset(0, 0),
                                    ),
                                ],
                              ),
                              child: Center(
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: widget.value && _isHovered ? _pulseAnimation.value : 1.0,
                                      child: Container(
                                        width: knobSize * 0.45,
                                        height: knobSize * 0.45,
                                        decoration: BoxDecoration(
                                          color: _colorAnimation.value,
                                          boxShadow: widget.value && _isHovered
                                              ? [
                                                  BoxShadow(
                                                    color: _colorAnimation.value!.withOpacity(0.6),
                                                    blurRadius: 4 * widget.scale,
                                                    offset: Offset(0, 0),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
