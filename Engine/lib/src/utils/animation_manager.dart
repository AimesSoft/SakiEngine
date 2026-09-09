import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';

export 'animation_config.dart';
import 'animation_config.dart';

class AnimationManager {
  static final Map<String, AnimationDefinition> _animations = {};
  static bool _isLoaded = false;

  static Future<void> loadAnimations() async {
    if (_isLoaded) return;

    try {
      final content = await AssetManager().loadString(
        'assets/GameScript/configs/animation.sks',
      );
      //print('[AnimationManager] 开始解析动画配置文件');
      _parseAnimations(content);
      _isLoaded = true;
    } catch (e) {
      print('[AnimationManager] 无法加载动画文件: $e');
    }
  }

  /// 清除动画缓存，用于热更新
  static void clearCache() {
    _animations.clear();
    _isLoaded = false;
  }

  static void _parseAnimations(String content) {
    _animations.addAll(AnimationConfigParser().parse(content));
  }

  static AnimationDefinition? getAnimation(String name) {
    return _animations[name];
  }

  static bool hasAnimation(String name) {
    return _animations.containsKey(name);
  }

  static List<String> getAnimationNames() {
    return _animations.keys.toList();
  }

  /// 计算有限动画完成后的确定状态。
  ///
  /// 关键帧偏移始终相对于传入的舞台基础属性；没有被后续关键帧覆盖的
  /// 预设或属性会继续保留。这与 [CharacterAnimationController] 的播放
  /// 语义一致，也让快进可以直接落到动画末帧。
  static Map<String, double>? resolveFinalProperties(
    String name,
    Map<String, double> baseProperties,
  ) {
    final animation = _animations[name];
    if (animation == null) return null;

    final result = Map<String, double>.from(baseProperties);
    for (final entry in animation.presetProperties.entries) {
      result[entry.key] = (baseProperties[entry.key] ?? 0.0) + entry.value;
    }
    for (final keyframe in animation.keyframes) {
      for (final entry in keyframe.properties.entries) {
        result[entry.key] = (baseProperties[entry.key] ?? 0.0) + entry.value;
      }
    }
    return result;
  }

  @visibleForTesting
  static void loadAnimationsFromStringForTesting(String content) {
    _animations.clear();
    _parseAnimations(content);
    _isLoaded = true;
  }

  /// 获取动画的预设属性
  static Map<String, double> getAnimationPresetProperties(String name) {
    return _animations[name]?.presetProperties ?? {};
  }
}

/// A finite, build-time-mapped sequence sampled against one monotonic clock.
/// This keeps the existing Saki property model; it does not interpret ATL.
class YuyuSequence {
  final AnimationDefinition definition;
  final Map<String, double> base;

  YuyuSequence(this.definition, Map<String, double> base)
    : base = Map.unmodifiable(base) {
    for (final frame in definition.keyframes) {
      if (!frame.duration.isFinite ||
          frame.duration < 0 ||
          !const {
            'linear',
            'ease',
            'easein',
            'easeout',
            'hold',
          }.contains(frame.type) ||
          frame.properties.values.any((v) => !v.isFinite) ||
          (frame.type == 'hold' && frame.properties.isNotEmpty)) {
        throw FormatException('Invalid sequence ${definition.name}');
      }
    }
  }

  double get duration =>
      definition.keyframes.fold(0, (v, frame) => v + frame.duration);

  static double warp(String type, double t) => switch (type) {
    'linear' => t,
    'ease' => .5 - math.cos(math.pi * t) / 2,
    'easein' => math.cos((1 - t) * math.pi / 2),
    'easeout' => 1 - math.cos(math.pi * t / 2),
    'hold' => 0,
    _ => throw FormatException('Unknown warper: $type'),
  };

  Map<String, double> sample(double seconds, {bool subsequentCycle = false}) {
    if (!seconds.isFinite || seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    final values = subsequentCycle
        ? sample(duration)
        : Map<String, double>.from(base);
    for (final entry in definition.presetProperties.entries) {
      values[entry.key] = (base[entry.key] ?? 0) + entry.value;
    }
    var remaining = seconds;
    for (final frame in definition.keyframes) {
      final fraction = frame.duration == 0
          ? 1.0
          : (remaining / frame.duration).clamp(0.0, 1.0);
      final progress = warp(frame.type, fraction);
      for (final property in frame.properties.entries) {
        final start = values[property.key] ?? base[property.key] ?? 0;
        final end = (base[property.key] ?? 0) + property.value;
        values[property.key] = start + (end - start) * progress;
      }
      if (remaining < frame.duration) break;
      remaining -= frame.duration;
    }
    return values;
  }
}

class YuyuSequencePlayback {
  final YuyuSequence sequence;
  final ValueChanged<Map<String, double>> onUpdate;
  Ticker? _ticker;
  Completer<bool>? _completion;
  bool _disposed = false;

  YuyuSequencePlayback({
    required AnimationDefinition definition,
    required Map<String, double> base,
    required this.onUpdate,
  }) : sequence = YuyuSequence(definition, base);

  Future<bool> play(TickerProvider vsync, {int? repeatCount}) {
    if (_disposed || _completion != null) {
      throw StateError('Playback already used');
    }
    final count = repeatCount ?? 1;
    if (count < 0 || (count == 0 && sequence.duration == 0)) {
      throw ArgumentError('An infinite sequence must advance time');
    }
    final completion = _completion = Completer<bool>();
    onUpdate(sequence.sample(0));
    if (sequence.duration == 0) {
      completion.complete(true);
      return completion.future;
    }
    _ticker = vsync.createTicker((elapsed) {
      final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      final finished = count > 0 && seconds >= sequence.duration * count;
      if (finished) {
        onUpdate(
          sequence.sample(sequence.duration, subsequentCycle: count > 1),
        );
        _ticker?.stop();
        completion.complete(true);
      } else {
        onUpdate(
          sequence.sample(
            seconds % sequence.duration,
            subsequentCycle: seconds >= sequence.duration,
          ),
        );
      }
    });
    _ticker!.start();
    return completion.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.dispose();
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete(false);
    }
  }
}

class CharacterAnimationController {
  final String characterId;
  final VoidCallback? onComplete;
  final void Function(Map<String, double>)? onAnimationUpdate;

  String? animationName; // 添加当前播放的动画名称

  AnimationController? _controller;
  Animation<double>? _animation;
  Map<String, double> _baseProperties = {};
  Map<String, double> _currentProperties = {};
  Map<String, double> _originalBaseProperties = {}; // 保存真正的初始基础位置，永不改变
  double _layoutXOffset = 0;
  bool _shouldStop = false; // 用于控制无限循环的停止
  bool _isInfiniteLoop = false;
  YuyuSequencePlayback? _yuyuPlayback;

  CharacterAnimationController({
    required this.characterId,
    this.onComplete,
    this.onAnimationUpdate,
  });

  /// 播放角色动画
  Future<void> playAnimation(
    String animationName,
    TickerProvider vsync,
    Map<String, double> baseProperties, {
    int? repeatCount,
  }) {
    // 设置当前播放的动画名称
    this.animationName = animationName;

    final animDef = AnimationManager.getAnimation(animationName);
    if (animDef == null) {
      onComplete?.call();
      return Future<void>.value();
    }

    // 应用预设属性到基础属性上
    _baseProperties = Map.from(baseProperties);
    final presetProperties = animDef.presetProperties;
    //print('[AnimationManager] 动画 $animationName 的预设属性: $presetProperties');
    //print('[AnimationManager] 原始基础属性: $baseProperties');
    for (final entry in presetProperties.entries) {
      final currentValue = _baseProperties[entry.key] ?? 0.0;
      _baseProperties[entry.key] = currentValue + entry.value;
      //print('[AnimationManager] 应用预设 ${entry.key}: $currentValue + ${entry.value} = ${_baseProperties[entry.key]}');
    }
    //print('[AnimationManager] 最终基础属性: $_baseProperties');

    _currentProperties = Map.from(_baseProperties);
    _originalBaseProperties = Map.from(baseProperties); // 保存真正的初始位置（不包含预设属性）
    _layoutXOffset = 0;
    _shouldStop = false; // 重置停止标志
    _isInfiniteLoop = repeatCount == 0;
    // Ren'Py ATL 会先应用 transform 的初始属性，再开始关键帧。
    // 立即发布预设状态，避免上一段动画的最终状态残留一帧。
    onAnimationUpdate?.call(currentProperties);

    _yuyuPlayback?.dispose();
    _yuyuPlayback = null;
    if (animDef.profile == 'yuyuball-sequence-v1') {
      _controller?.stop();
      final playback = YuyuSequencePlayback(
        definition: animDef,
        base: _originalBaseProperties,
        onUpdate: (values) {
          _currentProperties = values;
          onAnimationUpdate?.call(currentProperties);
        },
      );
      _yuyuPlayback = playback;
      return playback.play(vsync, repeatCount: repeatCount).then((completed) {
        if (completed) onComplete?.call();
      });
    }

    return _playConfiguredAnimation(animDef.keyframes, vsync, repeatCount);
  }

  Future<void> _playConfiguredAnimation(
    List<AnimationKeyframe> keyframes,
    TickerProvider vsync,
    int? repeatCount,
  ) async {
    // 根据repeatCount决定播放次数
    if (repeatCount == 0) {
      // repeat 0 表示无限循环播放
      await _playInfiniteLoop(keyframes, vsync);
    } else if (repeatCount == null || repeatCount == 1) {
      // 不写repeat或repeat 1，播放一次
      await _playKeyframes(keyframes, vsync);
    } else if (repeatCount > 1) {
      // 循环播放指定次数
      // 每次循环都基于真正的初始基础位置计算偏移，避免累积
      for (int i = 0; i < repeatCount; i++) {
        await _playKeyframes(keyframes, vsync);
      }
    }

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
  Future<void> _playInfiniteLoop(
    List<AnimationKeyframe> keyframes,
    TickerProvider vsync,
  ) async {
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

    final animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(curvedAnimation);

    animation.addListener(() {
      final progress = animation.value;

      for (final propName in _currentProperties.keys) {
        final startValue = startProperties[propName] ?? 0.0;
        final endValue = endProperties[propName] ?? 0.0;
        _currentProperties[propName] =
            startValue + (endValue - startValue) * progress;
      }

      onAnimationUpdate?.call(currentProperties);
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

  Future<void> _playKeyframes(
    List<AnimationKeyframe> keyframes,
    TickerProvider vsync,
  ) async {
    for (final keyframe in keyframes) {
      await _playKeyframe(keyframe, vsync);
    }
  }

  Future<void> _playKeyframe(
    AnimationKeyframe keyframe,
    TickerProvider vsync, {
    bool isReturnAnimation = false,
  }) async {
    _controller?.dispose();
    _controller = AnimationController(
      duration: Duration(milliseconds: (keyframe.duration * 1000).round()),
      vsync: vsync,
    );

    final startProperties = Map<String, double>.from(
      _currentProperties,
    ); // 从当前位置开始
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
        endProperties[propName] =
            (_originalBaseProperties[propName] ?? 0.0) + offset;
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
          _currentProperties[propName] =
              startValue + (endValue - startValue) * progress;
        }
      } else {
        // 正常动画：只更新关键帧中定义的属性
        for (final entry in keyframe.properties.entries) {
          final propName = entry.key;
          final startValue = startProperties[propName] ?? 0.0;
          final endValue = endProperties[propName] ?? 0.0;
          _currentProperties[propName] =
              startValue + (endValue - startValue) * progress;
        }
      }

      // 调用实时更新回调
      onAnimationUpdate?.call(currentProperties);
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

  /// Move the active animation with its layout slot without restarting its
  /// keyframes. Subsequent ticks and history snapshots share the new origin.
  void rebaseXCenter(double xcenter) {
    _layoutXOffset = xcenter - (_currentProperties['xcenter'] ?? 0.0);
  }

  Map<String, double> _withLayoutOffset(Map<String, double> properties) => {
    ...properties,
    if (properties.containsKey('xcenter'))
      'xcenter': properties['xcenter']! + _layoutXOffset,
  };

  Map<String, double> get currentProperties =>
      _withLayoutOffset(_currentProperties);

  /// 返回有限动画应写入历史快照的确定末帧。
  ///
  /// 对话历史会在动画仍播放时立即生成。如果直接复制当前插值状态，回退后
  /// 会恢复到动画开头或中途。无限循环没有确定末帧，因此保持实时快照语义。
  Map<String, double>? get finiteFinalProperties {
    final name = animationName;
    if (_isInfiniteLoop || name == null || _originalBaseProperties.isEmpty) {
      return null;
    }
    final properties = AnimationManager.resolveFinalProperties(
      name,
      _originalBaseProperties,
    );
    return properties == null ? null : _withLayoutOffset(properties);
  }

  /// 停止无限循环动画
  void stopInfiniteLoop() {
    _shouldStop = true;
    _yuyuPlayback?.dispose();
  }

  void dispose() {
    _yuyuPlayback?.dispose();
    _shouldStop = true; // 确保停止任何正在运行的无限循环
    _controller?.dispose();
  }
}
