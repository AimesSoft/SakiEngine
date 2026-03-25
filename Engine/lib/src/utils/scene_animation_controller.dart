import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/utils/animation_manager.dart';

class SceneAnimationController {
  final String sceneId;
  final VoidCallback? onComplete;
  final void Function(Map<String, double>)? onAnimationUpdate;
  
  AnimationController? _controller;
  Animation<double>? _animation;
  Map<String, double> _baseProperties = {};
  Map<String, double> _currentProperties = {};
  Map<String, double> _originalBaseProperties = {}; // 保存真正的初始基础位置，永不改变
  bool _shouldStop = false; // 用于控制无限循环的停止
  
  SceneAnimationController({
    required this.sceneId,
    this.onComplete,
    this.onAnimationUpdate,
  });

  /// 播放场景背景动画
  Future<void> playAnimation(
    String animationName,
    TickerProvider vsync,
    Map<String, double> baseProperties, {
    int? repeatCount,
  }) async {
    final animDef = AnimationManager.getAnimation(animationName);
    if (animDef == null) {
      //print('[SceneAnimationController] 动画不存在: $animationName');
      onComplete?.call();
      return;
    }

    //print('[SceneAnimationController] 开始播放场景动画: $animationName, repeat: ${repeatCount == null ? "1(默认)" : (repeatCount == 0 ? "无限(repeat=0)" : repeatCount.toString())}');
    
    // 应用预设属性到基础属性上
    _baseProperties = Map.from(baseProperties);
    final presetProperties = animDef.presetProperties;
    //print('[SceneAnimationController] 场景动画 $animationName 的预设属性: $presetProperties');
    //print('[SceneAnimationController] 原始基础属性: $baseProperties');
    for (final entry in presetProperties.entries) {
      final currentValue = _baseProperties[entry.key] ?? 0.0;
      _baseProperties[entry.key] = currentValue + entry.value;
      //print('[SceneAnimationController] 应用预设 ${entry.key}: $currentValue + ${entry.value} = ${_baseProperties[entry.key]}');
    }
    //print('[SceneAnimationController] 最终基础属性: $_baseProperties');
    
    _currentProperties = Map.from(_baseProperties);
    _originalBaseProperties = Map.from(baseProperties); // 保存真正的初始位置（不包含预设属性）
    _shouldStop = false; // 重置停止标志
    
    // 根据repeatCount决定播放次数
    if (repeatCount == 0) {
      // repeat 0 表示无限循环播放
      await _playInfiniteLoop(animDef.keyframes, vsync);
    } else if (repeatCount == null || repeatCount == 1) {
      // 不写repeat或repeat 1，播放一次
      await _playKeyframes(animDef.keyframes, vsync);
    } else if (repeatCount > 1) {
      // 循环播放指定次数
      // 每次循环都基于真正的初始基础位置计算偏移，避免累积
      for (int i = 0; i < repeatCount; i++) {
        await _playKeyframes(animDef.keyframes, vsync);
      }
    }
    
    //print('[SceneAnimationController] 场景动画播放完成: $animationName');
    onComplete?.call();
  }

  /// 播放回到基础位置的平滑动画
  Future<void> _playReturnToBaseAnimation(TickerProvider vsync) async {
    // 检查当前属性是否与基础属性不同
    bool needsReturn = false;
    for (final key in _currentProperties.keys) {
      if ((_currentProperties[key] ?? 0.0) != (_baseProperties[key] ?? 0.0)) {
        needsReturn = true;
        break;
      }
    }
    
    if (!needsReturn) return;
    
    // 创建回到基础位置的关键帧（0.3秒平滑过渡）
    final returnKeyframe = AnimationKeyframe(
      type: 'ease',
      duration: 0.3,
      properties: {}, // 空属性表示回到基础值
    );
    
    await _playKeyframe(returnKeyframe, vsync, isReturnAnimation: true);
  }

  /// 无限循环播放动画
  Future<void> _playInfiniteLoop(List<AnimationKeyframe> keyframes, TickerProvider vsync) async {
    // 实现真正的无限循环播放
    // 每次循环都基于真正的初始基础位置计算偏移，避免累积
    while (!_shouldStop) {
      // 播放完整的动画序列
      await _playKeyframes(keyframes, vsync);
      
      // 如果被标记为停止，则跳出循环
      if (_shouldStop) break;
      
      // 添加短暂的延迟避免过于频繁的循环（可选）
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 平滑地重置到基础位置
  Future<void> _smoothResetToBasePosition(TickerProvider vsync) async {
    // 检查是否需要重置
    bool needsReset = false;
    for (final key in _currentProperties.keys) {
      if ((_currentProperties[key] ?? 0.0) != (_baseProperties[key] ?? 0.0)) {
        needsReset = true;
        break;
      }
    }
    
    if (!needsReset) return;
    
    // 创建一个快速的平滑过渡回到基础位置
    final resetDuration = 100; // 100ms 快速重置
    _controller?.dispose();
    _controller = AnimationController(
      duration: Duration(milliseconds: resetDuration),
      vsync: vsync,
    );

    final startProperties = Map<String, double>.from(_currentProperties);
    final endProperties = Map<String, double>.from(_baseProperties);
    
    final curvedAnimation = CurvedAnimation(
      parent: _controller!,
      curve: Curves.easeInOut,
    );

    final animation = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation);
    
    animation.addListener(() {
      final progress = animation.value;
      
      for (final propName in _currentProperties.keys) {
        final startValue = startProperties[propName] ?? 0.0;
        final endValue = endProperties[propName] ?? 0.0;
        _currentProperties[propName] = startValue + (endValue - startValue) * progress;
      }
      
      onAnimationUpdate?.call(Map.from(_currentProperties));
    });

    final completer = Completer<void>();
    _controller!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        completer.complete();
      }
    });

    await _controller!.forward();
    await completer.future;
  }

  Future<void> _playKeyframes(List<AnimationKeyframe> keyframes, TickerProvider vsync) async {
    for (final keyframe in keyframes) {
      // 检查是否应该停止
      if (_shouldStop) break;
      await _playKeyframe(keyframe, vsync);
    }
  }

  Future<void> _playKeyframe(AnimationKeyframe keyframe, TickerProvider vsync, {bool isReturnAnimation = false}) async {
    _controller?.dispose();
    _controller = AnimationController(
      duration: Duration(milliseconds: (keyframe.duration * 1000).round()),
      vsync: vsync,
    );

    final startProperties = Map<String, double>.from(_currentProperties); // 从当前位置开始
    final endProperties = Map<String, double>.from(_currentProperties);
    
    if (isReturnAnimation) {
      // 复原动画：从当前位置回到基础属性值
      for (final key in _currentProperties.keys) {
        startProperties[key] = _currentProperties[key] ?? 0.0; // 从当前位置开始
        endProperties[key] = _baseProperties[key] ?? 0.0; // 回到基础位置
      }
    } else {
      // 正常动画：基于真正的初始基础位置计算偏移量
      // 确保每个关键帧的偏移都是相对于最初传入值，避免累积
      for (final entry in keyframe.properties.entries) {
        final propName = entry.key;
        final offset = entry.value;
        endProperties[propName] = (_originalBaseProperties[propName] ?? 0.0) + offset;
      }
    }

    // 创建动画
    late final CurvedAnimation curvedAnimation;
    if (keyframe.type == 'ease') {
      curvedAnimation = CurvedAnimation(
        parent: _controller!,
        curve: Curves.easeInOut,
      );
    } else {
      curvedAnimation = CurvedAnimation(
        parent: _controller!,
        curve: Curves.linear,
      );
    }

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation);
    
    _animation!.addListener(() {
      final progress = _animation!.value;
      
      if (isReturnAnimation) {
        // 复原动画：插值到基础位置
        for (final propName in _currentProperties.keys) {
          final startValue = startProperties[propName] ?? 0.0;
          final endValue = endProperties[propName] ?? 0.0;
          _currentProperties[propName] = startValue + (endValue - startValue) * progress;
        }
      } else {
        // 正常动画：只更新关键帧中定义的属性
        for (final entry in keyframe.properties.entries) {
          final propName = entry.key;
          final startValue = startProperties[propName] ?? 0.0;
          final endValue = endProperties[propName] ?? 0.0;
          _currentProperties[propName] = startValue + (endValue - startValue) * progress;
        }
      }
      
      // 调用实时更新回调
      onAnimationUpdate?.call(Map.from(_currentProperties));
    });

    final completer = Completer<void>();
    _controller!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        completer.complete();
      }
    });

    await _controller!.forward();
    await completer.future;
  }

  Map<String, double> get currentProperties => Map.from(_currentProperties);

  /// 停止无限循环动画
  void stopInfiniteLoop() {
    _shouldStop = true;
  }

  void dispose() {
    _shouldStop = true; // 确保停止任何正在运行的无限循环
    _controller?.dispose();
  }
}