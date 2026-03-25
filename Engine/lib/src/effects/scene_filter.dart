import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

enum FilterType {
  dreamy,
  blur,
  nostalgic,
}

enum AnimationType {
  none,
  pulse,
  fade,
  wave,
}

class SceneFilter {
  final FilterType type;
  final double intensity;
  final AnimationType animation;
  final double duration;

  const SceneFilter({
    required this.type,
    this.intensity = 0.5,
    this.animation = AnimationType.none,
    this.duration = 3.0,
  });

  static SceneFilter? fromString(String filterString) {
    final parts = filterString.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    final typeString = parts[0];
    FilterType? filterType;
    
    switch (typeString) {
      case 'dreamy':
        filterType = FilterType.dreamy;
        break;
      case 'blur':
        filterType = FilterType.blur;
        break;
      case 'nostalgic':
        filterType = FilterType.nostalgic;
        break;
      default:
        return null;
    }

    double intensity = 0.5;
    AnimationType animation = AnimationType.pulse; // 默认使用脉冲动画
    double duration = 3.0;

    for (int i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (part.startsWith('intensity:')) {
        final value = double.tryParse(part.substring(10));
        if (value != null && value >= 0.0 && value <= 1.0) {
          intensity = value;
        }
      } else if (part.startsWith('animation:')) {
        final animationString = part.substring(10);
        switch (animationString) {
          case 'pulse':
            animation = AnimationType.pulse;
            break;
          case 'fade':
            animation = AnimationType.fade;
            break;
          case 'wave':
            animation = AnimationType.wave;
            break;
          case 'none':
            animation = AnimationType.none;
            break;
        }
      } else if (part.startsWith('duration:')) {
        final value = double.tryParse(part.substring(9));
        if (value != null && value > 0) {
          duration = value;
        }
      }
    }

    return SceneFilter(
      type: filterType,
      intensity: intensity,
      animation: animation,
      duration: duration,
    );
  }
}

class FilterRenderer {
  static Widget applyFilter({
    required Widget child,
    required SceneFilter filter,
    required Animation<double>? animationController,
  }) {
    switch (filter.type) {
      case FilterType.dreamy:
        return _applyDreamyFilter(child, filter, animationController);
      case FilterType.blur:
        return _applyBlurFilter(child, filter, animationController);
      case FilterType.nostalgic:
        return _applyNostalgicFilter(child, filter, animationController);
    }
  }

  static Widget _applyDreamyFilter(
    Widget child,
    SceneFilter filter,
    Animation<double>? animationController,
  ) {
    return AnimatedBuilder(
      animation: animationController ?? const AlwaysStoppedAnimation(0.5),
      builder: (context, _) {
        double animatedIntensity = filter.intensity;
        
        if (animationController != null) {
          switch (filter.animation) {
            case AnimationType.pulse:
              // 明显的呼吸效果：从0.2到1.0之间变化
              final breathValue = 0.2 + 0.8 * (1 + math.sin(animationController.value * 2 * math.pi)) / 2;
              animatedIntensity = filter.intensity * breathValue;
              break;
            case AnimationType.fade:
              animatedIntensity = filter.intensity * animationController.value;
              break;
            case AnimationType.wave:
              // 波浪式朦胧
              final waveValue = 0.4 + 0.6 * (1 + math.sin(animationController.value * 4 * math.pi)) / 2;
              animatedIntensity = filter.intensity * waveValue;
              break;
            case AnimationType.none:
              break;
          }
        }

        return Container(
          child: Stack(
            children: [
              child,
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.0 + 0.4 * animatedIntensity, // 径向大小呼吸变化
                      colors: [
                        Colors.white.withOpacity(0.15 * animatedIntensity),
                        Colors.purple.withOpacity(0.08 * animatedIntensity),
                        Colors.blue.withOpacity(0.12 * animatedIntensity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 添加朦胧光晕层
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1 * animatedIntensity),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _applyBlurFilter(
    Widget child,
    SceneFilter filter,
    Animation<double>? animationController,
  ) {
    return AnimatedBuilder(
      animation: animationController ?? const AlwaysStoppedAnimation(0.5),
      builder: (context, _) {
        double animatedIntensity = filter.intensity;
        
        if (animationController != null) {
          switch (filter.animation) {
            case AnimationType.pulse:
              animatedIntensity = filter.intensity * 
                (0.5 + 0.5 * (1 + math.sin(animationController.value * 2 * math.pi)) / 2);
              break;
            case AnimationType.fade:
              animatedIntensity = filter.intensity * animationController.value;
              break;
            case AnimationType.wave:
              animatedIntensity = filter.intensity * 
                (0.7 + 0.3 * (1 + math.sin(animationController.value * 3 * math.pi)) / 2);
              break;
            case AnimationType.none:
              break;
          }
        }

        final blurValue = 5.0 * animatedIntensity;
        
        return Container(
          child: Stack(
            children: [
              child,
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurValue,
                    sigmaY: blurValue,
                  ),
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _applyNostalgicFilter(
    Widget child,
    SceneFilter filter,
    Animation<double>? animationController,
  ) {
    return AnimatedBuilder(
      animation: animationController ?? const AlwaysStoppedAnimation(0.5),
      builder: (context, _) {
        double animatedIntensity = filter.intensity;
        
        if (animationController != null) {
          switch (filter.animation) {
            case AnimationType.pulse:
              // 更明显的呼吸效果：从0.3到1.0之间变化
              final breathValue = 0.3 + 0.7 * (1 + math.sin(animationController.value * 2 * math.pi)) / 2;
              animatedIntensity = filter.intensity * breathValue;
              break;
            case AnimationType.fade:
              animatedIntensity = filter.intensity * animationController.value;
              break;
            case AnimationType.wave:
              // 波浪式呼吸
              final waveValue = 0.4 + 0.6 * (1 + math.sin(animationController.value * 3 * math.pi)) / 2;
              animatedIntensity = filter.intensity * waveValue;
              break;
            case AnimationType.none:
              break;
          }
        }

        return Container(
          child: Stack(
            children: [
              child,
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.0 + 0.3 * animatedIntensity, // 径向大小也会呼吸
                      colors: [
                        Colors.amber.withOpacity(0.25 * animatedIntensity),
                        Colors.orange.withOpacity(0.2 * animatedIntensity),
                        Colors.brown.withOpacity(0.15 * animatedIntensity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // 添加第二层呼吸光晕
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1 * animatedIntensity),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}