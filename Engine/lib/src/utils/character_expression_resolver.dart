import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/utils/character_expression_layers.dart';

/// 一个表达式 token 解析出的图层信息。
class ResolvedCharacterExpressionLayer {
  /// 实际差分名（不含层级前缀），例如 `mask`。
  final String name;

  /// 层级，从 1 开始。
  final int level;

  /// 实际使用的资源名，例如 `characters/xiayo1--mask`。
  final String assetName;

  /// 该层是调用方显式指定的，还是缺层时按字母序补的默认层。
  final bool isDefault;

  const ResolvedCharacterExpressionLayer({
    required this.name,
    required this.level,
    required this.assetName,
    required this.isDefault,
  });

  @override
  String toString() =>
      'ResolvedCharacterExpressionLayer($assetName, level: $level, '
      'isDefault: $isDefault)';
}

/// 把 expression 的图层 token 映射到磁盘资源。
///
/// 资源名优先级：
/// 1. 规范命名 `characters/<id>--<name>`（层级由 `-` 数量决定）
/// 2. 兼容命名 `characters/<id>-<name>`（旧项目里第二层沿用单横线）
/// 3. 缺层时按字母序取该层第一个可用资源（仅当调用方没有显式指定该层）
///
/// 显式写出的 token 如果找不到资源，会保留规范资源名继续走渲染路径：渲染层
/// 缺图时跳过，比"悄悄换成另一个差分"更安全，也和引擎既有的缺资源语义一致。
class CharacterExpressionResolver {
  const CharacterExpressionResolver._();

  /// 解析单个图层 token。
  ///
  /// 层级来自 token 自带的 `--` 前缀（`--mask` -> 第二层），因此调用方不需要
  /// 再传一次层级，避免两边不一致导致资源名多一个或少一个横线。
  ///
  /// [defaultLayerName] 是该层缺省时的回退候选（通常是字母序第一个），
  /// 只有 [token] 为空时才会被使用。
  static Future<ResolvedCharacterExpressionLayer?> resolveToken({
    required String resourceId,
    required String? token,
    String? defaultLayerName,
  }) async {
    final normalizedToken = token?.trim() ?? '';
    if (normalizedToken.isEmpty) {
      if (defaultLayerName == null || defaultLayerName.isEmpty) {
        return null;
      }
      final level = CharacterExpressionLayers.levelOfToken(defaultLayerName);
      final defaultName = CharacterExpressionLayers.stripPrefixes(
        defaultLayerName,
      );
      if (defaultName.isEmpty) {
        return null;
      }
      final assetName = await resolveAssetName(
        resourceId: resourceId,
        name: defaultName,
        level: level,
      );
      return ResolvedCharacterExpressionLayer(
        name: defaultName,
        level: level,
        assetName: assetName,
        isDefault: true,
      );
    }

    if (CharacterExpressionLayers.isRemovalToken(normalizedToken)) {
      return null;
    }

    // yuyu 的 `__none` 哨兵要原样保留，组合表才能命中。
    if (normalizedToken == CharacterExpressionLayers.yuyuNoneSentinel) {
      return ResolvedCharacterExpressionLayer(
        name: normalizedToken,
        level: 1,
        assetName: 'characters/$resourceId-$normalizedToken',
        isDefault: false,
      );
    }

    final level = CharacterExpressionLayers.levelOfToken(normalizedToken);
    final name = CharacterExpressionLayers.stripPrefixes(normalizedToken);
    if (name.isEmpty) {
      return null;
    }
    final assetName = await resolveAssetName(
      resourceId: resourceId,
      name: name,
      level: level,
    );
    return ResolvedCharacterExpressionLayer(
      name: name,
      level: level,
      assetName: assetName,
      isDefault: false,
    );
  }

  /// 规范资源名；规范命名不存在时回退到单横线旧命名。
  ///
  /// `xiayo1--mask`（规范第二层）找不到时，会再试 `xiayo1-mask`，避免旧项目
  /// 的第二层资源因为改名而失效。返回的资源名不保证存在，调用方仍然需要按
  /// 缺图处理。
  static Future<String> resolveAssetName({
    required String resourceId,
    required String name,
    required int level,
  }) async {
    if (level <= 1) {
      return 'characters/$resourceId-$name';
    }
    // 规范命名：level 1 -> `<id>-<name>`，level 2 -> `<id>--<name>`。
    final canonical =
        'characters/$resourceId-${'-' * (level - 1)}$name';
    if (await AssetManager().findAsset(canonical) != null) {
      return canonical;
    }
    final legacy = 'characters/$resourceId-$name';
    if (await AssetManager().findAsset(legacy) != null) {
      return legacy;
    }
    return canonical;
  }

  /// 在可用图层列表里找出某一层的默认差分名（字母序第一个）。
  ///
  /// 用于同时兼容"带 `-` 前缀"和"裸名字"两种磁盘命名：两层都会贡献候选，
  /// 显式前缀优先。
  static String? defaultLayerNameForLevel(
    Iterable<String> availableLayers,
    int level,
  ) {
    String? explicit;
    String? bare;
    for (final layer in availableLayers) {
      final name = layer.trim();
      if (name.isEmpty) {
        continue;
      }
      if (CharacterExpressionLayers.isRemovalToken(name)) {
        continue;
      }
      final tokenLevel = CharacterExpressionLayers.levelOfToken(name);
      if (tokenLevel != level) {
        continue;
      }
      if (isPoseLayerName(name)) {
        continue;
      }
      final stripped = CharacterExpressionLayers.stripPrefixes(name);
      if (stripped.isEmpty) {
        continue;
      }
      if (name.startsWith('-')) {
        explicit ??= stripped;
      } else {
        bare ??= name;
      }
    }
    return explicit ?? bare;
  }

  /// 判断某个磁盘图层名是否属于姿态层。
  ///
  /// 姿态层用 `pose` 命名（例如 `pose1`、`pose6`），也可能带 `-foreground`
  /// 后缀；它们不参与差分分层。
  static bool isPoseLayerName(String layerName) {
    final name = layerName.trim();
    if (name.isEmpty) {
      return false;
    }
    if (name.toLowerCase().startsWith('pose')) {
      return true;
    }
    // `-pose2` / `--pose2` 这类带层级前缀的写法同样按姿态处理。
    final stripped = CharacterExpressionLayers.stripPrefixes(name);
    return stripped.toLowerCase().startsWith('pose');
  }

}
