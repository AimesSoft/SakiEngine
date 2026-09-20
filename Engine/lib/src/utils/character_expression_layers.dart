/// 角色差分表达式（expression）的多层解析工具。
///
/// 引擎把一个角色的差分拆成若干层：第一层是基础表情，第二层及以后盖在
/// 前一层之上。磁盘上的命名约定为：
///
/// * 第一层：`characters/<resourceId>-<name>`
/// * 第二层：`characters/<resourceId>--<name>`
/// * 第三层：`characters/<resourceId>---<name>`（延续同一规则）
///
/// 剧本里第二层直接接在第一层后面，例如 `x happy mask`。解析器把它以 script
/// 形态（`happy --mask`）写进 AST，游戏状态与选择器内部则使用更明确的
/// `happy+--mask`。两种形态 [parse] 都接受，索引见 [encode] 与
/// [encodeScriptForm]。
library;

/// 一层差分的描述。
class CharacterExpressionLayer {
  /// 实际差分名（不含层级前缀），例如 `mask`。
  final String name;

  /// 层级，从 1 开始。
  final int level;

  /// 原始 token 是否显式写了 `-` 前缀（`--mask` 为 true）。
  final bool explicit;

  const CharacterExpressionLayer({
    required this.name,
    required this.level,
    required this.explicit,
  });

  /// 磁盘资源名使用的 token：第一层为 `name`，第二层及以上为 `--name`。
  String get assetToken => level <= 1 ? name : '${'-' * level}$name';

  @override
  String toString() => 'CharacterExpressionLayer($assetToken, level: $level)';
}

/// 表达式的多层解析结果。
class CharacterExpressionLayers {
  /// 按 level 升序排列的图层，同层最多保留一个。
  final List<CharacterExpressionLayer> layers;

  /// 被显式清除标记（`--none`、`--`、`clear`）清掉的层级集合。
  final Set<int> clearedLevels;

  /// 需要原样保留在表达式里的不透明 token（yuyu 的 `__none` 哨兵）。
  ///
  /// 它们不属于任何差分层，但 yuyu 的 `layersFor(<pose>:<expression>)` 组合表
  /// 要求表达式字面量保持原样，所以编码时按原顺序附在末尾。
  final List<String> passthroughTokens;

  const CharacterExpressionLayers({
    required this.layers,
    this.clearedLevels = const <int>{},
    this.passthroughTokens = const <String>[],
  });

  static const CharacterExpressionLayers empty = CharacterExpressionLayers(
    layers: [],
  );

  static final RegExp _separator = RegExp(r'[\s+]+');

  /// 解析任意来源的表达式字符串。
  ///
  /// 兼容三种写法：
  /// * `happy` 单个基础表情
  /// * `happy mask` 剧本语法，第二层直接接在第一层之后
  /// * `happy+--mask` 引擎内部的规范组合格式
  ///
  /// 层级规则：
  /// * 显式 `--` 前缀（或更多 `-`）永远以它自己写的层级为准
  /// * 不带前缀的 token 按位置递推，第一个是第一层，第二个是第二层
  ///
  /// 同一层出现多个 token 时保留最后一个，与该属性"后者覆盖前者"的历史语义
  /// 保持一致。超过 [maxLevel] 的 token 会被忽略。
  static CharacterExpressionLayers parse(String? raw, {int maxLevel = 2}) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return empty;
    }
    return _resolveTokens(trimmed.split(_separator), maxLevel: maxLevel);
  }

  /// token 前缀的 `-` 数量；无前缀或单个 `-` 都视为第一层。
  static int levelOfToken(String token) {
    var dashCount = 0;
    for (var i = 0; i < token.length; i++) {
      if (token[i] == '-') {
        dashCount++;
      } else {
        break;
      }
    }
    if (dashCount <= 1) {
      return 1;
    }
    return dashCount;
  }

  /// 去掉 token 开头的全部 `-`。
  static String stripPrefixes(String token) {
    var index = 0;
    while (index < token.length && token[index] == '-') {
      index++;
    }
    return index == 0 ? token : token.substring(index);
  }

  /// 把 `characters/<characterId>-<layer>` 的完整词干归一成规范图层 token。
  ///
  /// `getAvailableCharacterLayers` 系列 API 用 `$characterId-` 作为分隔符，
  /// 因此截断后剩下的横线数量本身就是层级信息：`xiayo1--mask` -> `--mask`
  /// （第二层），`xiayo1-happy` -> `happy`（第一层）。返回的 token 可以直接交给
  /// [levelOfToken] / [parse]，不会重复叠加前缀。
  static String canonicalLayerToken(String fileStem, String characterId) {
    final stem = fileStem.trim();
    final prefix = '${characterId.trim()}-';
    if (stem.isEmpty || !stem.startsWith(prefix)) {
      return normalizedLayerToken(stem);
    }

    final layerPart = stem.substring(prefix.length);
    final name = stripPrefixes(layerPart);
    if (name.isEmpty) {
      return '';
    }

    // 截断时被分隔符吃掉的那一个横线不计入层级：横线数量就是层级 - 1。
    final level = _leadingDashCount(layerPart) + 1;
    return normalizedLayerToken(name, level: level > 1 ? level : 1);
  }

  static int _leadingDashCount(String value) {
    var count = 0;
    for (var i = 0; i < value.length; i++) {
      if (value[i] != '-') break;
      count++;
    }
    return count;
  }

  /// 由裸差分名和层级拼出规范图层 token。
  ///
  /// [name] 允许已经带层级前缀（扫描结果常见 `--mask` 这种形式）；此时以调用
  /// 方给出的 [level] 为准，避免把前缀重复叠加成 `----mask`。
  static String normalizedLayerToken(String name, {int level = 1}) {
    final baseName = stripPrefixes(name.trim());
    if (baseName.isEmpty) {
      return '';
    }
    return level <= 1 ? baseName : '${'-' * level}$baseName';
  }

  static const Set<String> _removalTokens = {
    'none',
    'clear',
    'remove',
    'off',
  };

  /// 判断 token 是否是显式清除标记。
  ///
  /// 支持 `--none`、`--clear`、`none`、`clear` 等形式；单独的 `--` 也视为
  /// 清除。差分名本身叫 `none` 的角色需要用 `--none` 之外的写法，引擎不为此
  /// 保留歧义。
  static bool isRemovalToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed == '--' || trimmed == '-') {
      return true;
    }
    final name = stripPrefixes(trimmed).toLowerCase();
    return _removalTokens.contains(name);
  }

  /// 生成某一层的显式清除 token：第一层 `none`，第二层 `--none`。
  static String removalTokensForLevel(int level) =>
      normalizedLayerToken('none', level: level);

  /// 是否显式写出了层级前缀（`--mask`、`---mask`）。
  ///
  /// 单个 `-` 是历史写法，仍按第一层处理，因此不算显式层级。
  static bool hasExplicitLevelPrefix(String token) =>
      levelOfToken(token.trim()) >= 2;

  /// yuyu 兼容包用 `yu_...` 前缀的 base64Url 状态串标识一组图层属性；
  /// `__none` 是同一套映射里的"无差分"哨兵。
  ///
  /// 这两类 token 都要原样保留：前者的编码里可能出现 `--`，后者的名字以 `__`
  /// 开头，都不能被当成差分层级前缀拆开。
  static const String opaqueStatePrefix = 'yu_';
  static const String yuyuNoneSentinel = '__none';

  static bool isOpaqueStateToken(String token) {
    final trimmed = token.trim();
    return trimmed.startsWith(opaqueStatePrefix) ||
        trimmed == yuyuNoneSentinel;
  }

  /// 把剧本里依次出现的差分 token 归并成"每层一个"的图层集合。
  ///
  /// 支持两种写法：
  /// * 空格语法 `happy mask` —— 第一个 token 作为第一层，第二个自动升为第二层
  /// * 显式前缀 `happy --mask`、`--mask` —— 层级以自己写出的为准
  static CharacterExpressionLayers fromTokens(
    Iterable<String> tokens, {
    int maxLevel = 2,
  }) {
    final normalized = <String>[];
    for (final token in tokens) {
      final trimmed = token.trim();
      if (trimmed.isNotEmpty) {
        normalized.add(trimmed);
      }
    }
    if (normalized.isEmpty) {
      return empty;
    }
    return _resolveTokens(normalized, maxLevel: maxLevel);
  }

  /// 两种入口共用的层级推导：显式前缀优先，其余按位置递推。
  static CharacterExpressionLayers _resolveTokens(
    Iterable<String> tokens, {
    required int maxLevel,
  }) {
    final byLevel = <int, CharacterExpressionLayer>{};
    final cleared = <int>{};
    final passthrough = <String>[];

    /// 不带前缀的 token 落在从第一层开始的第一个空闲层。
    int firstFreeLevel() {
      for (var level = 1; level <= maxLevel; level++) {
        if (!byLevel.containsKey(level) && !cleared.contains(level)) {
          return level;
        }
      }
      return maxLevel + 1;
    }

    for (final token in tokens) {
      if (token.isEmpty || token == '+') {
        continue;
      }

      // yuyu 兼容状态是单层的不透明字符串，其中可能包含 `--`。
      if (isOpaqueStateToken(token)) {
        if (token.trim() == yuyuNoneSentinel) {
          // `__none` 是 yuyu 的"无差分"哨兵，只影响该模型自己的属性选择，
          // 不能变成第二层，也不能当成清除标记去动普通差分；但它必须原样
          // 留在表达式里，yuyu 组合表才能命中。
          passthrough.add(token.trim());
          continue;
        }
        final level = firstFreeLevel();
        if (level < 1 || level > maxLevel) {
          continue;
        }
        byLevel[level] = CharacterExpressionLayer(
          name: token,
          level: level,
          explicit: false,
        );
        continue;
      }

      final level = hasExplicitLevelPrefix(token)
          ? levelOfToken(token)
          : firstFreeLevel();
      if (level < 1 || level > maxLevel) {
        continue;
      }

      if (isRemovalToken(token)) {
        cleared.add(level);
        byLevel.remove(level);
      } else {
        final name = stripPrefixes(token);
        if (name.isEmpty) {
          continue;
        }
        byLevel[level] = CharacterExpressionLayer(
          name: name,
          level: level,
          explicit: token.startsWith('-'),
        );
      }
    }

    if (byLevel.isEmpty && passthrough.isEmpty) {
      return CharacterExpressionLayers(
        layers: const [],
        clearedLevels: cleared,
      );
    }

    // 渲染顺序必须按层级升序，与输入书写顺序无关。
    final levels = byLevel.keys.toList()..sort();
    return CharacterExpressionLayers(
      layers: [for (final level in levels) byLevel[level]!],
      clearedLevels: cleared,
      passthroughTokens: passthrough,
    );
  }

  bool get isEmpty => layers.isEmpty;

  /// 是否出现了按层生效的清除标记。
  bool get clearsExplicitly => clearedLevels.isNotEmpty;

  CharacterExpressionLayer? layerAt(int level) {
    for (final layer in layers) {
      if (layer.level == level) {
        return layer;
      }
    }
    return null;
  }

  String? assetTokenAt(int level) => layerAt(level)?.assetToken;

  String? nameAt(int level) => layerAt(level)?.name;

  /// 编码成规范表达式：`happy+--mask`。
  ///
  /// 第一层不带层级前缀（历史写法 `-happy` 归一成 `happy`），第二层及以上带
  /// `--` 前缀，因此同一个 token 既能在磁盘上定位资源，也能明确表达层级。
  /// 空结果返回空字符串，调用方据此判断"无差分"。
  String encode() => encodeWithSeparator('+');

  /// 编码成空格分隔的表达式：`happy --mask`。
  ///
  /// 解析器把它直接写进 AST，因此形态与剧本一致；yuyu 的 `__none` 哨兵也在
  /// 这个形态里保持原位，组合表才能命中。[parse] 两种分隔符都接受。
  String encodeScriptForm() => encodeWithSeparator(' ');

  String encodeWithSeparator(String separator) {
    final tokens = [
      ...layers.map((layer) => layer.assetToken),
      ...passthroughTokens,
    ];
    return tokens.join(separator);
  }

  /// 在保留 [other] 图层的基础上，用 [requested] 显式给出的层覆盖。
  ///
  /// 这是"第二层状态保留"语义的核心：剧本只写第一层时，第二层沿用角色当前
  /// 状态；一旦显式写了第二层（或清除标记）就以剧本为准。
  static CharacterExpressionLayers merge({
    required CharacterExpressionLayers requested,
    required CharacterExpressionLayers other,
    int maxLevel = 2,
  }) {
    final byLevel = <int, CharacterExpressionLayer>{};

    for (final layer in other.layers) {
      if (requested.clearedLevels.contains(layer.level)) {
        continue;
      }
      if (layer.level > maxLevel) {
        continue;
      }
      byLevel[layer.level] = layer;
    }
    for (final layer in requested.layers) {
      if (layer.level > maxLevel) {
        continue;
      }
      byLevel[layer.level] = layer;
    }

    final levels = byLevel.keys.toList()..sort();
    return CharacterExpressionLayers(
      layers: [for (final level in levels) byLevel[level]!],
      clearedLevels: requested.clearedLevels,
    );
  }

  @override
  String toString() => encode();
}
