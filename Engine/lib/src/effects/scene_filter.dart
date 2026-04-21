import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';

enum FilterType {
  dreamy,
  blur,
  nostalgic,
  snowMosaic,
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
      case 'snowmosaic':
      case 'snow_mosaic':
      case 'snow':
        filterType = FilterType.snowMosaic;
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
      case FilterType.snowMosaic:
        return _applySnowMosaicFilter(child, filter, animationController);
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

  static Widget _applySnowMosaicFilter(
    Widget child,
    SceneFilter filter,
    Animation<double>? animationController,
  ) {
    return AnimatedBuilder(
      animation: animationController ?? const AlwaysStoppedAnimation(0.5),
      builder: (context, _) {
        double animatedIntensity = filter.intensity.clamp(0.0, 1.0);

        if (animationController != null) {
          switch (filter.animation) {
            case AnimationType.pulse:
              final pulse =
                  0.4 + 0.6 * (1 + math.sin(animationController.value * 2 * math.pi)) / 2;
              animatedIntensity = (filter.intensity * pulse).clamp(0.0, 1.0);
              break;
            case AnimationType.fade:
              animatedIntensity =
                  (filter.intensity * animationController.value).clamp(0.0, 1.0);
              break;
            case AnimationType.wave:
              final wave =
                  0.3 + 0.7 * (1 + math.sin(animationController.value * 8 * math.pi)) / 2;
              animatedIntensity = (filter.intensity * wave).clamp(0.0, 1.0);
              break;
            case AnimationType.none:
              break;
          }
        }

        // 电视无信号风格：更重的雪花、偏冷色闪烁与明显模糊。
        final blurSigma = 1.6 + (animatedIntensity * 6.4);
        final overlayAlpha = 0.10 + (animatedIntensity * 0.30);
        final flicker =
            0.65 + 0.35 * (1 + math.sin((animationController?.value ?? 0.5) * 26 * math.pi)) / 2;
        final tintedAlpha = (overlayAlpha * flicker).clamp(0.0, 0.9);

        return Stack(
          children: [
            child,
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _SnowMosaicPainter(
                  intensity: animatedIntensity,
                  phase: animationController?.value ?? 0.5,
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                color: const Color(0xFFEAF2FF).withOpacity(tintedAlpha),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SnowMosaicPainter extends CustomPainter {
  final double intensity;
  final double phase;

  const _SnowMosaicPainter({
    required this.intensity,
    required this.phase,
  });

  static double _hashToUnit(int x) {
    var v = x;
    v = (v ^ 61) ^ (v >> 16);
    v = v + (v << 3);
    v = v ^ (v >> 4);
    v = v * 0x27d4eb2d;
    v = v ^ (v >> 15);
    return (v & 0x7fffffff) / 0x7fffffff;
  }

  static double _noise(int x, int y, int t) {
    final key = x * 73856093 ^ y * 19349663 ^ t * 83492791;
    return _hashToUnit(key);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.0 || size.isEmpty) {
      return;
    }

    final t = (phase * 1000).floor();

    final coarseStep = math.max(4.0, 14.0 - intensity * 9.0);
    final coarseDensity = 0.16 + intensity * 0.64;
    final coarseAlphaBase = 0.12 + intensity * 0.42;
    final coarsePaint = Paint()..style = PaintingStyle.fill;

    for (double y = 0; y < size.height; y += coarseStep) {
      final iy = (y / coarseStep).floor();
      for (double x = 0; x < size.width; x += coarseStep) {
        final ix = (x / coarseStep).floor();
        final n = _noise(ix, iy, t);
        if (n > coarseDensity) {
          continue;
        }

        final n2 = _noise(ix + 17, iy + 31, t + 13);
        final blockScale = 0.9 + n2 * 1.9;
        final w = coarseStep * blockScale;
        final h = coarseStep * (0.8 + n2 * 1.2);
        final alpha = (coarseAlphaBase * (0.5 + n2 * 0.8)).clamp(0.0, 1.0);

        coarsePaint.color =
            Color.fromRGBO(245 + (10 * n2).round(), 248, 255, alpha);
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), coarsePaint);
      }
    }

    final flakeStep = math.max(3.0, 8.0 - intensity * 4.8);
    final flakeDensity = 0.08 + intensity * 0.36;
    final flakePaint = Paint()..style = PaintingStyle.fill;

    for (double y = 0; y < size.height; y += flakeStep) {
      final iy = (y / flakeStep).floor();
      for (double x = 0; x < size.width; x += flakeStep) {
        final ix = (x / flakeStep).floor();
        final n = _noise(ix + 101, iy + 151, t + 29);
        if (n > flakeDensity) {
          continue;
        }

        final n2 = _noise(ix + 211, iy + 17, t + 59);
        final radius = 0.5 + n2 * (1.1 + intensity * 2.2);
        final alpha = (0.20 + intensity * 0.48) * (0.45 + 0.7 * n2);
        flakePaint.color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), radius, flakePaint);
      }
    }

    // 稀疏的横向扫描干扰线，增强 CRT 无信号感。
    final scanPaint = Paint()..style = PaintingStyle.fill;
    final lineGap = math.max(2.0, 8.0 - intensity * 5.0);
    final lineAlphaBase = (0.03 + intensity * 0.16).clamp(0.0, 0.35);
    final lineOffset = (phase * lineGap * 10) % lineGap;
    for (double y = -lineGap + lineOffset; y < size.height; y += lineGap) {
      final ny = (y / lineGap).floor();
      final n = _noise(ny, t, ny + 91);
      final alpha = (lineAlphaBase * (0.6 + n * 0.9)).clamp(0.0, 0.45);
      scanPaint.color = Color.fromRGBO(230, 238, 255, alpha);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.0), scanPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowMosaicPainter oldDelegate) {
    return oldDelegate.intensity != intensity || oldDelegate.phase != phase;
  }
}
