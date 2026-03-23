import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'dart:math' as math;

/// 带波动效果的文本组件
class WaveText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final AnimationController animationController;
  
  const WaveText({
    super.key,
    required this.text,
    required this.style,
    required this.animationController,
  });
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animationController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: _buildAnimatedCharacters(),
        );
      },
    );
  }
  
  List<Widget> _buildAnimatedCharacters() {
    List<Widget> widgets = [];
    
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      
      // 只对点号应用波动效果
      if (char == '.') {
        // 为每个点创建不同的相位偏移，产生波浪效果
        final phaseOffset = i * 0.3;
        final animationValue = animationController.value * 2 * math.pi;
        final offsetY = math.sin(animationValue + phaseOffset) * 3.0;
        
        widgets.add(
          Transform.translate(
            offset: Offset(0, offsetY),
            child: Text(
              char,
              style: style,
            ),
          ),
        );
      } else {
        widgets.add(
          Text(
            char,
            style: style,
          ),
        );
      }
    }
    
    return widgets;
  }
}

/// 通用指示器组件
/// 
/// 可以显示各种状态的指示器，如快进、自动播放等
class CommonIndicator extends StatefulWidget {
  final bool isVisible;
  final IconData icon;
  final String text;
  final Duration animationDuration;
  
  const CommonIndicator({
    super.key,
    required this.isVisible,
    required this.icon,
    required this.text,
    this.animationDuration = const Duration(milliseconds: 300),
  });
  
  @override
  State<CommonIndicator> createState() => _CommonIndicatorState();
}

class _CommonIndicatorState extends State<CommonIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _iconAnimationController;
  late AnimationController _textAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _iconScaleAnimation;
  late Animation<double> _iconRotationAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    // 图标动画控制器 - 持续循环
    _iconAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    // 文字波动动画控制器 - 示波器效果
    _textAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // 图标缩放动画 - 轻微的脉冲效果
    _iconScaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _iconAnimationController,
      curve: Curves.easeInOut,
    ));
    
    // 图标轻微旋转动画
    _iconRotationAnimation = Tween<double>(
      begin: -0.05,
      end: 0.05,
    ).animate(CurvedAnimation(
      parent: _iconAnimationController,
      curve: Curves.easeInOut,
    ));
    
    // 根据初始状态设置动画
    if (widget.isVisible) {
      _animationController.forward();
      _startIconAnimation();
    }
  }
  
  void _startIconAnimation() {
    _iconAnimationController.repeat(reverse: true);
    _textAnimationController.repeat();
  }
  
  void _stopIconAnimation() {
    _iconAnimationController.stop();
    _textAnimationController.stop();
  }
  
  @override
  void didUpdateWidget(CommonIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.isVisible != widget.isVisible) {
      if (widget.isVisible) {
        _animationController.forward();
        _startIconAnimation();
      } else {
        _animationController.reverse();
        _stopIconAnimation();
      }
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _iconAnimationController.dispose();
    _textAnimationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.menu);
    
    return AnimatedBuilder(
      animation: Listenable.merge([_animationController, _iconAnimationController, _textAnimationController]),
      builder: (context, child) {
        // 不可见时完全隐藏
        if (!widget.isVisible && _opacityAnimation.value <= 0.0) {
          return const SizedBox.shrink();
        }
        
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: widget.isVisible ? 1.0 : _opacityAnimation.value,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 14 * scale, // 从 12 增加到 14
                vertical: 10 * scale    // 从 8 增加到 10
              ),
              decoration: BoxDecoration(
                color: config.themeColors.background.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(
                  config.baseWindowBorder > 0 
                      ? config.baseWindowBorder * scale 
                      : 0 * scale
                ),
                border: Border.all(
                  color: config.themeColors.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8 * scale,
                    offset: Offset(0, 4 * scale),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 带动画效果的图标
                  Transform.scale(
                    scale: _iconScaleAnimation.value,
                    child: Transform.rotate(
                      angle: _iconRotationAnimation.value,
                      child: Icon(
                        widget.icon,
                        color: config.themeColors.primary,
                        size: 40 * scale, // 从 18 增加到 24
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale), // 从 6 增加到 8
                  // 带波动效果的文本
                  WaveText(
                    text: widget.text,
                    style: config.quickMenuTextStyle.copyWith(
                      color: config.themeColors.primary,
                      fontSize: config.quickMenuTextStyle.fontSize! * scale,
                    ),
                    animationController: _textAnimationController,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}