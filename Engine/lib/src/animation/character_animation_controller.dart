import 'package:flutter/material.dart';
import 'character_animation_system.dart';

/// 角色动画状态
enum AnimationState {
  idle,
  playing,
  paused,
  finished,
}

/// 角色动画控制器
class CharacterAnimationController {
  final TickerProvider vsync;
  final String characterId;
  
  AnimationController? _controller;
  
  AnimationController? get controller => _controller;
  CharacterAnimationDef? _currentAnimation;
  AnimationState _state = AnimationState.idle;
  
  // 基础变换和变量
  CharacterTransform _baseTransform;
  final Map<String, double> _variables;
  
  // 回调
  VoidCallback? _onComplete;
  
  CharacterAnimationController({
    required this.vsync,
    required this.characterId,
    required CharacterTransform baseTransform,
    Map<String, double>? variables,
  }) : _baseTransform = baseTransform,
       _variables = variables ?? {};
  
  AnimationState get state => _state;
  CharacterAnimationDef? get currentAnimation => _currentAnimation;
  double get progress => _controller?.value ?? 0.0;
  
  /// 更新基础变换
  void updateBaseTransform(CharacterTransform transform) {
    _baseTransform = transform;
    _updateVariables();
  }
  
  /// 更新变量（如角色位置信息）
  void updateVariables(Map<String, double> variables) {
    _variables.addAll(variables);
  }
  
  /// 播放动画
  void playAnimation(
    String animationName, {
    VoidCallback? onComplete,
  }) {
    final animationSystem = CharacterAnimationSystem();
    final animationDef = animationSystem.getAnimation(animationName);
    
    if (animationDef == null) {
      print('[CharacterAnimationController] 动画不存在: $animationName');
      return;
    }
    
    _currentAnimation = animationDef;
    _onComplete = onComplete;
    
    // 停止当前动画
    _controller?.dispose();
    
    // 创建新的动画控制器
    _controller = AnimationController(
      duration: Duration(milliseconds: (animationDef.duration * 1000).round()),
      vsync: vsync,
    );
    
    // 设置监听器
    _controller!.addStatusListener(_onAnimationStatusChanged);
    
    _state = AnimationState.playing;
    
    if (animationDef.loop) {
      if (animationDef.alternate) {
        _controller!.repeat(reverse: true);
      } else {
        _controller!.repeat();
      }
    } else {
      _controller!.forward();
    }
    
    print('[CharacterAnimationController] 播放动画: $animationName (${characterId})');
  }
  
  /// 停止动画
  void stopAnimation() {
    if (_controller != null) {
      _controller!.stop();
      _state = AnimationState.idle;
      print('[CharacterAnimationController] 停止动画: ${characterId}');
    }
  }
  
  /// 暂停动画
  void pauseAnimation() {
    if (_controller != null && _state == AnimationState.playing) {
      _controller!.stop();
      _state = AnimationState.paused;
    }
  }
  
  /// 恢复动画
  void resumeAnimation() {
    if (_controller != null && _state == AnimationState.paused) {
      _controller!.forward();
      _state = AnimationState.playing;
    }
  }
  
  /// 获取当前变换
  CharacterTransform getCurrentTransform() {
    if (_controller == null || _currentAnimation == null) {
      return _baseTransform;
    }
    
    final animationSystem = CharacterAnimationSystem();
    return animationSystem.calculateTransform(
      _currentAnimation!.name,
      _controller!.value,
      _baseTransform,
      _variables,
    );
  }
  
  /// 动画状态改变回调
  void _onAnimationStatusChanged(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        if (!(_currentAnimation?.loop ?? false)) {
          _state = AnimationState.finished;
          _onComplete?.call();
        }
        break;
      case AnimationStatus.dismissed:
        _state = AnimationState.idle;
        break;
      default:
        break;
    }
  }
  
  /// 更新内置变量
  void _updateVariables() {
    _variables['xcenter'] = _baseTransform.x;
    _variables['ycenter'] = _baseTransform.y;
    _variables['scale'] = _baseTransform.scale;
    _variables['rotation'] = _baseTransform.rotation;
    _variables['opacity'] = _baseTransform.opacity;
  }
  
  /// 销毁控制器
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _state = AnimationState.idle;
  }
}