import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

/// 动画关键帧数据
class AnimationKeyframe {
  final double time; // 0.0 到 1.0
  final Map<String, dynamic> properties;
  
  AnimationKeyframe({
    required this.time,
    required this.properties,
  });
}

/// 动画定义
class CharacterAnimationDef {
  final String name;
  final List<AnimationKeyframe> keyframes;
  final double duration; // 秒
  final Curve curve;
  final bool loop;
  final bool alternate; // 是否往返循环
  
  CharacterAnimationDef({
    required this.name,
    required this.keyframes,
    required this.duration,
    this.curve = Curves.linear,
    this.loop = false,
    this.alternate = false,
  });
}

/// 角色位置和属性数据
class CharacterTransform {
  final double x;
  final double y; 
  final double scale;
  final double rotation;
  final double opacity;
  
  CharacterTransform({
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.opacity,
  });
  
  /// 线性插值
  CharacterTransform lerp(CharacterTransform other, double t) {
    return CharacterTransform(
      x: x + (other.x - x) * t,
      y: y + (other.y - y) * t,
      scale: scale + (other.scale - scale) * t,
      rotation: rotation + (other.rotation - rotation) * t,
      opacity: opacity + (other.opacity - opacity) * t,
    );
  }
}

/// 角色动画系统
class CharacterAnimationSystem {
  static final CharacterAnimationSystem _instance = CharacterAnimationSystem._internal();
  factory CharacterAnimationSystem() => _instance;
  CharacterAnimationSystem._internal();
  
  final Map<String, CharacterAnimationDef> _animations = {};
  bool _isLoaded = false;
  
  /// 加载动画配置文件
  Future<void> loadAnimations(String gamePath) async {
    if (_isLoaded) return;
    
    try {
      // 尝试从游戏路径加载
      String content;
      try {
        content = await rootBundle.loadString('$gamePath/GameScript/configs/animations.sks');
      } catch (e) {
        // 如果游戏路径加载失败，使用默认路径
        content = await rootBundle.loadString('assets/GameScript/configs/animations.sks');
      }
      
      _parseAnimationsFile(content);
      _isLoaded = true;
      print('[CharacterAnimationSystem] 动画配置加载成功，共 ${_animations.length} 个动画');
    } catch (e) {
      print('[CharacterAnimationSystem] 动画配置加载失败: $e');
      // 加载默认动画
      _loadDefaultAnimations();
    }
  }
  
  /// 解析动画配置文件
  void _parseAnimationsFile(String content) {
    final lines = content.split('\n');
    String? currentAnimationName;
    List<AnimationKeyframe> currentKeyframes = [];
    double currentDuration = 1.0;
    Curve currentCurve = Curves.linear;
    bool currentLoop = false;
    bool currentAlternate = false;
    
    for (String line in lines) {
      final trimmedLine = line.trim();
      
      // 跳过空行和注释
      if (trimmedLine.isEmpty || trimmedLine.startsWith('//')) {
        continue;
      }
      
      // 检查动画定义开始 [animation_name]
      final animationMatch = RegExp(r'^\[([^\]]+)\]$').firstMatch(trimmedLine);
      if (animationMatch != null) {
        // 保存前一个动画
        if (currentAnimationName != null) {
          _animations[currentAnimationName] = CharacterAnimationDef(
            name: currentAnimationName,
            keyframes: List.from(currentKeyframes),
            duration: currentDuration,
            curve: currentCurve,
            loop: currentLoop,
            alternate: currentAlternate,
          );
        }
        
        // 开始新动画
        currentAnimationName = animationMatch.group(1)!;
        currentKeyframes.clear();
        currentDuration = 1.0;
        currentCurve = Curves.linear;
        currentLoop = false;
        currentAlternate = false;
        continue;
      }
      
      // 解析关键帧 keyframe time property:value property:value
      if (trimmedLine.startsWith('keyframe ')) {
        final parts = trimmedLine.substring(9).split(' ');
        if (parts.isNotEmpty) {
          final time = double.tryParse(parts[0]) ?? 0.0;
          final properties = <String, dynamic>{};
          
          for (int i = 1; i < parts.length; i++) {
            final prop = parts[i];
            if (prop.contains(':')) {
              final colonIndex = prop.indexOf(':');
              final key = prop.substring(0, colonIndex);
              final value = prop.substring(colonIndex + 1);
              
              // 解析数值或表达式
              properties[key] = _parsePropertyValue(value);
            }
          }
          
          currentKeyframes.add(AnimationKeyframe(
            time: time,
            properties: properties,
          ));
        }
        continue;
      }
      
      // 解析其他属性
      if (trimmedLine.startsWith('duration ')) {
        currentDuration = double.tryParse(trimmedLine.substring(9)) ?? 1.0;
      } else if (trimmedLine.startsWith('ease ')) {
        currentCurve = _parseCurve(trimmedLine.substring(5));
      } else if (trimmedLine == 'loop true') {
        currentLoop = true;
      } else if (trimmedLine == 'alternate true') {
        currentAlternate = true;
      }
    }
    
    // 保存最后一个动画
    if (currentAnimationName != null) {
      _animations[currentAnimationName] = CharacterAnimationDef(
        name: currentAnimationName,
        keyframes: currentKeyframes,
        duration: currentDuration,
        curve: currentCurve,
        loop: currentLoop,
        alternate: currentAlternate,
      );
    }
  }
  
  /// 解析属性值（支持表达式如 xcenter+0.1）
  dynamic _parsePropertyValue(String value) {
    // 如果是纯数值，直接返回
    final numValue = double.tryParse(value);
    if (numValue != null) {
      return numValue;
    }
    
    // 如果包含表达式，保存为字符串稍后计算
    return value;
  }
  
  /// 解析缓动曲线
  Curve _parseCurve(String curveName) {
    switch (curveName.toLowerCase()) {
      case 'linear': return Curves.linear;
      case 'ease_in': return Curves.easeIn;
      case 'ease_out': return Curves.easeOut;
      case 'ease_in_out': return Curves.easeInOut;
      case 'bounce': return Curves.bounceOut;
      case 'in_out_bounce': return Curves.bounceInOut;
      case 'elastic_out': return Curves.elasticOut;
      case 'in_out_quad': return Curves.easeInOutQuad;
      case 'out_cubic': return Curves.easeOutCubic;
      case 'out_back': return Curves.easeOutBack;
      case 'in_back': return Curves.easeInBack;
      case 'in_out_sine': return Curves.easeInOutSine;
      default: return Curves.linear;
    }
  }
  
  /// 加载默认动画
  void _loadDefaultAnimations() {
    _animations['jump'] = CharacterAnimationDef(
      name: 'jump',
      keyframes: [
        AnimationKeyframe(time: 0.0, properties: {'y': 'ycenter'}),
        AnimationKeyframe(time: 0.5, properties: {'y': 'ycenter-0.2', 'scale': 'scale+0.1'}),
        AnimationKeyframe(time: 1.0, properties: {'y': 'ycenter', 'scale': 'scale'}),
      ],
      duration: 1.0,
      curve: Curves.bounceOut,
    );
    
    _animations['shake'] = CharacterAnimationDef(
      name: 'shake',
      keyframes: [
        AnimationKeyframe(time: 0.0, properties: {'x': 'xcenter'}),
        AnimationKeyframe(time: 0.2, properties: {'x': 'xcenter+0.05'}),
        AnimationKeyframe(time: 0.4, properties: {'x': 'xcenter-0.05'}),
        AnimationKeyframe(time: 0.6, properties: {'x': 'xcenter+0.03'}),
        AnimationKeyframe(time: 0.8, properties: {'x': 'xcenter-0.03'}),
        AnimationKeyframe(time: 1.0, properties: {'x': 'xcenter'}),
      ],
      duration: 1.0,
      curve: Curves.easeInOutQuad,
    );
  }
  
  /// 获取动画定义
  CharacterAnimationDef? getAnimation(String name) {
    return _animations[name];
  }
  
  /// 计算动画在指定时间的变换
  CharacterTransform calculateTransform(
    String animationName,
    double progress,
    CharacterTransform baseTransform,
    Map<String, double> variables,
  ) {
    final animation = getAnimation(animationName);
    if (animation == null) return baseTransform;
    
    // 应用缓动曲线
    final easedProgress = animation.curve.transform(progress);
    
    // 找到当前时间对应的关键帧
    AnimationKeyframe? prevFrame, nextFrame;
    
    for (int i = 0; i < animation.keyframes.length; i++) {
      final frame = animation.keyframes[i];
      if (frame.time <= easedProgress) {
        prevFrame = frame;
      }
      if (frame.time >= easedProgress && nextFrame == null) {
        nextFrame = frame;
        break;
      }
    }
    
    if (prevFrame == null && nextFrame == null) {
      return baseTransform;
    }
    
    // 计算插值
    Map<String, double> interpolatedProperties = {};
    
    if (prevFrame == null) {
      // 只有下一个关键帧
      interpolatedProperties = _evaluateProperties(nextFrame!.properties, variables);
    } else if (nextFrame == null) {
      // 只有前一个关键帧
      interpolatedProperties = _evaluateProperties(prevFrame.properties, variables);
    } else {
      // 插值计算
      final t = prevFrame.time == nextFrame.time ? 0.0 : 
                (easedProgress - prevFrame.time) / (nextFrame.time - prevFrame.time);
      
      final prevProps = _evaluateProperties(prevFrame.properties, variables);
      final nextProps = _evaluateProperties(nextFrame.properties, variables);
      
      for (final key in {...prevProps.keys, ...nextProps.keys}) {
        final prevValue = prevProps[key] ?? _getBaseValue(key, baseTransform);
        final nextValue = nextProps[key] ?? _getBaseValue(key, baseTransform);
        interpolatedProperties[key] = prevValue + (nextValue - prevValue) * t;
      }
    }
    
    // 应用变换
    return CharacterTransform(
      x: interpolatedProperties['x'] ?? baseTransform.x,
      y: interpolatedProperties['y'] ?? baseTransform.y,
      scale: interpolatedProperties['scale'] ?? baseTransform.scale,
      rotation: interpolatedProperties['rotation'] ?? baseTransform.rotation,
      opacity: interpolatedProperties['opacity'] ?? baseTransform.opacity,
    );
  }
  
  /// 计算属性表达式的值
  Map<String, double> _evaluateProperties(Map<String, dynamic> properties, Map<String, double> variables) {
    final result = <String, double>{};
    
    for (final entry in properties.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is double) {
        result[key] = value;
      } else if (value is String) {
        result[key] = _evaluateExpression(value, variables);
      }
    }
    
    return result;
  }
  
  /// 计算表达式（支持简单的加减乘除）
  double _evaluateExpression(String expression, Map<String, double> variables) {
    String expr = expression.trim();
    
    // 替换变量
    for (final variable in variables.keys) {
      expr = expr.replaceAll(variable, variables[variable].toString());
    }
    
    // 简单的表达式求值（支持 +, -, *, /）
    try {
      // 这里使用简单的正则表达式解析
      final operatorMatch = RegExp(r'([+-]?\d*\.?\d+)\s*([+\-*/])\s*([+-]?\d*\.?\d+)').firstMatch(expr);
      if (operatorMatch != null) {
        final num1 = double.parse(operatorMatch.group(1)!);
        final operator = operatorMatch.group(2)!;
        final num2 = double.parse(operatorMatch.group(3)!);
        
        switch (operator) {
          case '+': return num1 + num2;
          case '-': return num1 - num2;
          case '*': return num1 * num2;
          case '/': return num1 / num2;
        }
      }
      
      // 如果没有运算符，直接解析数值
      return double.parse(expr);
    } catch (e) {
      print('[CharacterAnimationSystem] 表达式解析失败: $expression -> $expr');
      return 0.0;
    }
  }
  
  /// 获取基础变换的值
  double _getBaseValue(String property, CharacterTransform transform) {
    switch (property) {
      case 'x': return transform.x;
      case 'y': return transform.y;
      case 'scale': return transform.scale;
      case 'rotation': return transform.rotation;
      case 'opacity': return transform.opacity;
      default: return 0.0;
    }
  }
}