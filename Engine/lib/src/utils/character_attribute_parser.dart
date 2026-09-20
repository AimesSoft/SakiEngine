import 'package:sakiengine/src/utils/character_expression_layers.dart';

/// 角色属性 token 的解析结果。
///
/// `pose` 与 `expression` 的取值语义与引擎既有行为保持一致：
/// 遍历所有 token，包含 `pose` 的最后一个 token 作为姿态，其余 token 按出现
/// 顺序归并成多层差分表达式（第一层、第二层……），后出现的同层 token 覆盖
/// 先出现的。
class CharacterAttributeTokens {
  /// 姿态 token，例如 `pose2`；没有则为 null。
  final String? pose;

  /// 归并后的差分表达式，例如 `happy+--mask`；没有则为 null。
  final String? expression;

  const CharacterAttributeTokens({this.pose, this.expression});

  static const CharacterAttributeTokens empty = CharacterAttributeTokens();

  @override
  String toString() =>
      'CharacterAttributeTokens(pose: $pose, expression: $expression)';
}

/// 负责把剧本里的角色属性 token 归并成姿态 + 多层差分表达式。
///
/// SKS 解析器与 Shift+E 选择器的脚本改写共用这里，避免两处规则漂移。
class CharacterAttributeParser {
  const CharacterAttributeParser._();

  /// 判断 token 是否是内联 API 调用（`api...`）。
  static bool isInlineApiToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return trimmed.toLowerCase().startsWith('api');
  }

  /// 判断 token 是否是姿态（pose）。
  ///
  /// 与历史行为一致：包含 `pose` 子串即视为姿态，因此 `pose2`、`xiayo1pose`
  /// 都命中，而 `happy`、`mask` 这类差分不会。
  static bool isPoseToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return trimmed.startsWith('pose') || trimmed.contains('pose');
  }

  /// 归并角色属性。
  ///
  /// 第二层差分直接接在第一层之后：`x happy mask` 归一成 `happy --mask`，
  /// 渲染时 mask 盖在 happy 之上。也兼容显式写法 `x happy --mask` 以及原有
  /// 的 `A+B` 组合格式。内联 API token 不参与归并。
  ///
  /// yuyu 兼容包的状态串（`yu_...`）本身就是一个不透明 token，直接整段作为
  /// 表达式保留，映射层会按 `<pose>:<expression>` 组合表核对。
  static CharacterAttributeTokens resolve(Iterable<String> attributes) {
    String? pose;
    final expressionTokens = <String>[];

    for (final attribute in attributes) {
      final token = attribute.trim();
      if (token.isEmpty || isInlineApiToken(token)) {
        continue;
      }
      if (isPoseToken(token)) {
        pose = token;
        continue;
      }
      expressionTokens.add(token);
    }

    if (expressionTokens.isEmpty) {
      return CharacterAttributeTokens(pose: pose);
    }

    final merged = CharacterExpressionLayers.fromTokens(expressionTokens);
    // AST 里保存与剧本一致的空格形态。
    final encoded = merged.encodeScriptForm();
    return CharacterAttributeTokens(
      pose: pose,
      expression: encoded.isEmpty ? null : encoded,
    );
  }

  /// 按绘制顺序拆出各层差分 token，用于写回脚本。
  ///
  /// `happy+--mask` -> `['happy', '--mask']`，写回后仍是可读的空格分层语法。
  /// 第一层不带层级前缀（历史写法 `-happy` 归一成 `happy`），第二层及以上
  /// 保留 `--` 前缀。
  static List<String> expressionTokens(String? expression) {
    final layers = CharacterExpressionLayers.parse(expression).layers;
    return [
      for (final layer in layers)
        if (layer.level <= 1) layer.name else layer.assetToken,
    ];
  }
}
