import 'package:flutter/material.dart';
import '../animation/character_animation_system.dart';
import '../animation/character_animation_controller.dart';

/// 动画化的角色显示组件
class AnimatedCharacterWidget extends StatefulWidget {
  final String characterId;
  final String? imagePath;
  final double width;
  final double height;
  final double x;
  final double y;
  final double scale;
  final double opacity;
  final String? animationName;
  final VoidCallback? onAnimationComplete;
  
  const AnimatedCharacterWidget({
    super.key,
    required this.characterId,
    this.imagePath,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.animationName,
    this.onAnimationComplete,
  });
  
  @override
  State<AnimatedCharacterWidget> createState() => _AnimatedCharacterWidgetState();
}

class _AnimatedCharacterWidgetState extends State<AnimatedCharacterWidget> 
    with TickerProviderStateMixin {
  CharacterAnimationController? _animationController;
  CharacterTransform? _currentTransform;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimation();
  }
  
  @override
  void didUpdateWidget(AnimatedCharacterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果动画名称改变，播放新动画
    if (widget.animationName != oldWidget.animationName) {
      _playAnimation();
    }
    
    // 如果位置或属性改变，更新基础变换
    if (widget.x != oldWidget.x || 
        widget.y != oldWidget.y ||
        widget.scale != oldWidget.scale ||
        widget.opacity != oldWidget.opacity) {
      _updateBaseTransform();
    }
  }
  
  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }
  
  /// 初始化动画
  void _initializeAnimation() {
    final baseTransform = CharacterTransform(
      x: widget.x,
      y: widget.y,
      scale: widget.scale,
      rotation: 0.0,
      opacity: widget.opacity,
    );
    
    _animationController = CharacterAnimationController(
      vsync: this,
      characterId: widget.characterId,
      baseTransform: baseTransform,
      variables: {
        'xcenter': widget.x,
        'ycenter': widget.y,
        'scale': widget.scale,
        'rotation': 0.0,
        'opacity': widget.opacity,
      },
    );
    
    _currentTransform = baseTransform;
    
    // 如果有动画名称，立即播放
    _playAnimation();
  }
  
  /// 播放动画
  void _playAnimation() {
    if (widget.animationName != null && widget.animationName!.isNotEmpty) {
      _animationController?.playAnimation(
        widget.animationName!,
        onComplete: widget.onAnimationComplete,
      );
    }
  }
  
  /// 更新基础变换
  void _updateBaseTransform() {
    final baseTransform = CharacterTransform(
      x: widget.x,
      y: widget.y,
      scale: widget.scale,
      rotation: 0.0,
      opacity: widget.opacity,
    );
    
    _animationController?.updateBaseTransform(baseTransform);
    _animationController?.updateVariables({
      'xcenter': widget.x,
      'ycenter': widget.y,
      'scale': widget.scale,
      'rotation': 0.0,
      'opacity': widget.opacity,
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_animationController == null) {
      return const SizedBox.shrink();
    }
    
    return AnimatedBuilder(
      animation: _animationController!.controller ?? const AlwaysStoppedAnimation(0.0),
      builder: (context, child) {
        final transform = _animationController!.getCurrentTransform();
        
        return Positioned(
          left: transform.x - (widget.width * transform.scale) / 2,
          top: transform.y - (widget.height * transform.scale) / 2,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..scale(transform.scale)
              ..rotateZ(transform.rotation),
            child: Opacity(
              opacity: transform.opacity.clamp(0.0, 1.0),
              child: widget.imagePath != null
                ? Image.asset(
                    widget.imagePath!,
                    width: widget.width,
                    height: widget.height,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: widget.width,
                        height: widget.height,
                        color: Colors.grey.withOpacity(0.3),
                        child: const Icon(
                          Icons.person,
                          color: Colors.grey,
                        ),
                      );
                    },
                  )
                : Container(
                    width: widget.width,
                    height: widget.height,
                    color: Colors.grey.withOpacity(0.3),
                    child: Center(
                      child: Text(
                        widget.characterId,
                        style: const TextStyle(color: Colors.grey),
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