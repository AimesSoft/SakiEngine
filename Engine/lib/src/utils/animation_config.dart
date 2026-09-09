class AnimationKeyframe {
  final String type; // 'ease' or 'linear'
  final double duration;
  final Map<String, double> properties;

  AnimationKeyframe({
    required this.type,
    required this.duration,
    required this.properties,
  });
}

class AnimationDefinition {
  final String name;
  final List<AnimationKeyframe> keyframes;
  final Map<String, double> presetProperties; // 新增：预设属性
  final String profile;

  AnimationDefinition({
    required this.name,
    required this.keyframes,
    this.presetProperties = const {},
    this.profile = 'saki',
  });
}

class AnimationConfigParser {
  final Map<String, AnimationDefinition> _animations = {};
  bool _strict = false;
  Map<String, AnimationDefinition> parse(
    String content, {
    bool strict = false,
  }) {
    _strict = strict;
    _animations.clear();
    _parseAnimations(content);
    return Map.unmodifiable(_animations);
  }

  void _parseAnimations(String content) {
    final lines = content.split('\n');
    String? currentAnimationName;
    List<AnimationKeyframe> currentKeyframes = [];
    Map<String, double> currentPresetProperties = {};
    var currentProfile = 'saki';
    final declared = <String>{};
    void requireBody() {
      if (_strict &&
          currentAnimationName != null &&
          currentKeyframes.isEmpty &&
          currentPresetProperties.isEmpty) {
        throw FormatException('Empty animation: $currentAnimationName');
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('//')) continue;

      if (trimmed.startsWith('profile ')) {
        currentProfile = trimmed.substring('profile '.length).trim();
        if (currentAnimationName == null ||
            currentProfile != 'yuyuball-sequence-v1') {
          throw FormatException('Unsupported animation profile: $trimmed');
        }
        continue;
      }

      if (!trimmed.startsWith('ease') &&
          !trimmed.startsWith('linear') &&
          !trimmed.startsWith('hold ') &&
          !_isPropertyLine(trimmed)) {
        if (_strict && !RegExp(r'^\w+$').hasMatch(trimmed)) {
          throw FormatException('Invalid animation declaration: $trimmed');
        }
        // 这是动画名称
        requireBody();
        if (_strict && !declared.add(trimmed)) {
          throw FormatException('Duplicate animation: $trimmed');
        }
        if (currentAnimationName != null &&
            (currentKeyframes.isNotEmpty ||
                currentPresetProperties.isNotEmpty)) {
          _animations[currentAnimationName] = AnimationDefinition(
            name: currentAnimationName,
            keyframes: List.from(currentKeyframes),
            presetProperties: Map.from(currentPresetProperties),
            profile: currentProfile,
          );
        }
        currentAnimationName = trimmed;
        currentKeyframes.clear();
        currentPresetProperties.clear();
        currentProfile = 'saki';
      } else if (_isPropertyLine(trimmed)) {
        // 这是预设属性行（如：scale+0.1）
        final property = _parsePropertyLine(trimmed);
        if (_strict &&
            (currentAnimationName == null ||
                property == null ||
                !const {
                  'scale',
                  'xcenter',
                  'ycenter',
                  'rotation',
                  'alpha',
                }.contains(property.key) ||
                !property.value.isFinite)) {
          throw FormatException('Invalid animation preset: $trimmed');
        }
        if (property != null) {
          currentPresetProperties[property.key] = property.value;
          //print('[AnimationManager] 解析预设属性: ${property.key} = ${property.value}');
        }
      } else {
        // 这是关键帧定义
        final keyframe = _parseKeyframe(trimmed);
        if (_strict && currentAnimationName == null) {
          throw FormatException('Keyframe has no animation: $trimmed');
        }
        if (currentProfile == 'yuyuball-sequence-v1' &&
            (keyframe == null ||
                !const {
                  'ease',
                  'easein',
                  'easeout',
                  'linear',
                  'hold',
                }.contains(keyframe.type) ||
                !keyframe.duration.isFinite ||
                keyframe.duration < 0)) {
          throw FormatException('Invalid YuYuball keyframe: $trimmed');
        }
        if (keyframe != null) {
          currentKeyframes.add(keyframe);
        }
      }
    }

    // 处理最后一个动画
    requireBody();
    if (currentAnimationName != null &&
        (currentKeyframes.isNotEmpty || currentPresetProperties.isNotEmpty)) {
      _animations[currentAnimationName] = AnimationDefinition(
        name: currentAnimationName,
        keyframes: List.from(currentKeyframes),
        presetProperties: Map.from(currentPresetProperties),
        profile: currentProfile,
      );
    }
  }

  /// 检查是否是属性行（如：scale+0.1, xcenter-0.5）
  bool _isPropertyLine(String line) {
    return RegExp(r'^\w+[+-]\d*\.?\d+$').hasMatch(line);
  }

  /// 解析属性行
  MapEntry<String, double>? _parsePropertyLine(String line) {
    final match = RegExp(r'^(\w+)([+-])(\d*\.?\d+)$').firstMatch(line);
    if (match != null) {
      final propName = match.group(1)!;
      final operator = match.group(2)!;
      final value = double.parse(match.group(3)!);
      return MapEntry(propName, operator == '+' ? value : -value);
    }
    return null;
  }

  AnimationKeyframe? _parseKeyframe(String line) {
    final parts = line.split(' ');
    if (parts.length == 2 && parts[0] == 'hold') {
      final duration = double.tryParse(parts[1]);
      if (duration == null) return null;
      return AnimationKeyframe(
        type: 'hold',
        duration: duration,
        properties: {},
      );
    }
    if (parts.length < 3) return null;

    final type = parts[0]; // 'ease' or 'linear'
    final duration = double.tryParse(parts[1]);
    if (duration == null) return null;

    final properties = <String, double>{};

    // 解析属性变化 如: ycenter-0.5, xcenter+0.1
    for (int i = 2; i < parts.length; i++) {
      final prop = parts[i];
      final match = RegExp(r'^(\w+)([+-])(\d*\.?\d+)$').firstMatch(prop);
      if (_strict &&
          (match == null ||
              !const {
                'scale',
                'xcenter',
                'ycenter',
                'rotation',
                'alpha',
              }.contains(match[1]))) {
        throw FormatException('Invalid animation property: $prop');
      }
      if (match != null) {
        final propName = match.group(1)!;
        final operator = match.group(2)!;
        final value = double.parse(match.group(3)!);
        properties[propName] = operator == '+' ? value : -value;
      }
    }

    return AnimationKeyframe(
      type: type,
      duration: duration,
      properties: properties,
    );
  }
}
