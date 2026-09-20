import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/utils/character_expression_layers.dart';
import 'package:sakiengine/src/utils/character_expression_resolver.dart';

class CharacterLayerInfo {
  final String assetName;
  final int layerLevel;
  final String layerType;
  final String blend;

  const CharacterLayerInfo({
    required this.assetName,
    required this.layerLevel,
    required this.layerType,
    this.blend = 'normal',
  });
}

class CharacterLayerParser {
  // 添加缓存以避免重复解析
  static final Map<String, List<CharacterLayerInfo>> _layerCache = {};

  static Future<List<CharacterLayerInfo>> parseCharacterLayers({
    required String resourceId,
    required String pose,
    required String expression,
  }) async {
    // 生成缓存键
    final cacheKey = '$resourceId:$pose:$expression';

    // 检查缓存
    if (_layerCache.containsKey(cacheKey)) {
      return _layerCache[cacheKey]!;
    }

    final layers = <CharacterLayerInfo>[];

    final mapped = await AssetManager().mappedCharacterLayers(cacheKey);
    if (mapped != null) {
      for (final layer in mapped) {
        if (await AssetManager().findAsset(layer['assetName'] as String) ==
            null) {
          throw FormatException(
            'Missing mapped character layer: ${layer['assetName']}',
          );
        }
        layers.add(
          CharacterLayerInfo(
            assetName: layer['assetName'] as String,
            layerLevel: layer['layerLevel'] as int,
            layerType: layer['layerType'] as String,
            blend: layer['blend'] as String? ?? 'normal',
          ),
        );
      }
      _layerCache[cacheKey] = layers;
      return layers;
    }

    // 首先检查是否为物件（在items文件夹中查找）
    final itemAssetName = 'items/$resourceId';
    final itemExists = await AssetManager().findAsset(itemAssetName) != null;

    if (itemExists) {
      // 这是一个物件，使用简化的图层结构
      sakiDiagnosticLog('[CharacterLayerParser] 检测到物件: $resourceId，使用items文件夹');
      layers.add(
        CharacterLayerInfo(
          assetName: itemAssetName,
          layerLevel: 0,
          layerType: 'item',
        ),
      );

      // 缓存结果
      _layerCache[cacheKey] = layers;
      return layers;
    }

    // 不是物件，按原有逻辑处理角色
    // 1. 底层：pose（姿势）- 如果找不到指定pose，使用字母顺序第一个可用的pose
    String actualPose = pose;
    final poseAssetName = 'characters/$resourceId-$actualPose';
    final poseExists = await AssetManager().findAsset(poseAssetName) != null;

    if (!poseExists) {
      // 寻找可用的pose图层（level 0相当于pose层）
      final availablePoses = await AssetManager.getAvailableCharacterLayers(
        resourceId,
      );
      final poseLayersOnly = availablePoses
          .where((layer) => !layer.contains('-'))
          .toList();
      if (poseLayersOnly.isNotEmpty) {
        actualPose = poseLayersOnly.first;
      }
    }

    layers.add(
      CharacterLayerInfo(
        assetName: 'characters/$resourceId-$actualPose',
        layerLevel: 0,
        layerType: 'pose',
      ),
    );

    // 2. 解析expression，支持多级图层并处理默认值
    final expressionLayers = await _parseExpressionLayers(
      resourceId,
      expression,
    );
    layers.addAll(expressionLayers);

    // 3. 可选的姿势前景层。用于手臂、道具等必须覆盖在表情之上的部件，
    // 命名约定：characters/<resourceId>-<pose>-foreground。
    //
    // Ren'Py layeredimage 常见顺序是 body -> face -> arm。把 arm 直接烘进
    // pose 底图会导致后绘制的 face 遮住手部，因此这里提供一个通用的第三层，
    // 让项目无需为每个表情重复生成整张立绘。
    final foregroundAssetName = 'characters/$resourceId-$actualPose-foreground';
    final foregroundExists =
        await AssetManager().findAsset(foregroundAssetName) != null;
    if (foregroundExists) {
      layers.add(
        CharacterLayerInfo(
          assetName: foregroundAssetName,
          layerLevel: 98,
          layerType: 'pose_foreground',
        ),
      );
    }

    // 4. 检查是否需要添加帽子图层（仅针对特定角色和姿势）
    if (resourceId == 'xiayo1' &&
        (actualPose == 'pose6' ||
            actualPose == 'pose7' ||
            actualPose == 'pose8')) {
      final hatLayer = await _parseHatLayer(resourceId, actualPose);
      if (hatLayer != null) {
        layers.add(hatLayer);
      }
    }

    // 按层级排序确保正确的渲染顺序
    layers.sort((a, b) => a.layerLevel.compareTo(b.layerLevel));

    // 缓存结果
    _layerCache[cacheKey] = layers;

    return layers;
  }

  /// 解析 expression 里的差分图层。
  ///
  /// 支持的写法：
  /// * `happy`        -> 第一层
  /// * `--happy`      -> 第二层（磁盘资源 `characters/<id>--happy`）
  /// * `happy mask`   -> 第一层 happy + 第二层 mask（剧本语法）
  /// * `happy+--mask` -> 同上的内部规范格式
  ///
  /// 同层最多一个图层，返回值已按 layerLevel 升序排列，渲染时后画的层自然
  /// 盖在前一层之上。
  static Future<List<CharacterLayerInfo>> _parseExpressionLayers(
    String resourceId,
    String expression,
  ) async {
    final parsed = CharacterExpressionLayers.parse(expression);
    if (parsed.layers.isEmpty) {
      return const [];
    }

    final layers = <CharacterLayerInfo>[];
    for (final layer in parsed.layers) {
      final parsedLayer = await _parseExpressionLayer(
        resourceId,
        layer.assetToken,
        layer.level,
      );
      if (parsedLayer != null) {
        layers.add(parsedLayer);
      }
    }
    return layers;
  }

  /// 解析单层差分。
  ///
  /// [expressionName] 允许是裸名（`mask`）或带层级前缀的 token（`--mask`）；
  /// [layerLevel] 只在裸名需要补前缀时使用。资源名优先使用规范命名
  /// `characters/<id>--<name>`，找不到时回退到旧的单横线命名。
  static Future<CharacterLayerInfo?> _parseExpressionLayer(
    String resourceId,
    String expressionName,
    int layerLevel,
  ) async {
    final name = expressionName.trim();
    if (name.isEmpty) {
      return null;
    }

    // token 自带层级前缀（`--mask`），层级由它自己决定。
    final token = CharacterExpressionLayers.normalizedLayerToken(
      name,
      level: layerLevel,
    );
    var resolved = await CharacterExpressionResolver.resolveToken(
      resourceId: resourceId,
      token: token,
    );
    if (resolved == null) {
      return null;
    }

    // 显式指定的差分缺失时，回退到该层默认差分。
    //
    // 第一层保留历史行为（按字母序补位）；第二层及以上不做这种补位：叠加层
    // 是显式选择的结果，悄悄换成另一个差分比缺图更让人困惑。
    if (await AssetManager().findAsset(resolved.assetName) == null &&
        layerLevel <= 1) {
      final defaultLayerName =
          CharacterExpressionResolver.defaultLayerNameForLevel(
            await AssetManager.getAvailableCharacterLayers(resourceId),
            layerLevel,
          );
      if (defaultLayerName != null && defaultLayerName.isNotEmpty) {
        // 扫描结果可能自带 `--` 前缀，先剥掉再按层级重建，避免重复叠加。
        final fallbackName = CharacterExpressionLayers.stripPrefixes(
          defaultLayerName,
        );
        final fallback = await CharacterExpressionResolver.resolveToken(
          resourceId: resourceId,
          token: fallbackName,
        );
        if (fallback != null) {
          resolved = fallback;
        }
      }
    }

    return CharacterLayerInfo(
      assetName: resolved.assetName,
      layerLevel: layerLevel,
      layerType: 'expression_layer_$layerLevel',
    );
  }

  /// 辅助方法：检查表达式字符串的层级。
  static int getExpressionLayerLevel(String expression) {
    final layers = CharacterExpressionLayers.parse(expression).layers;
    if (layers.isEmpty) {
      return 1;
    }
    // 单个 token 时返回其所在层，多 token 组合时返回最高层。
    return layers.last.level;
  }

  /// 解析帽子图层
  static Future<CharacterLayerInfo?> _parseHatLayer(
    String resourceId,
    String pose,
  ) async {
    // 帽子图层的资源命名：characters/xiayo1-hat
    // 帽子图层应该在所有差分图层之上，使用层级99
    final hatAssetName = 'characters/$resourceId-hat';
    final hatExists = await AssetManager().findAsset(hatAssetName) != null;

    if (hatExists) {
      print('[CharacterLayerParser] 为 $resourceId $pose 添加帽子图层: $hatAssetName');
      return CharacterLayerInfo(
        assetName: hatAssetName,
        layerLevel: 99, // 最高层级，确保在所有表情图层之上
        layerType: 'hat_layer',
      );
    }

    return null;
  }

  /// 辅助方法：从单个差分 token 中提取实际的表情名称。
  ///
  /// 多层组合表达式请使用 [CharacterExpressionLayers.parse]，这里只处理
  /// 第一个 token，保持旧调用点的行为不变。
  static String extractExpressionName(String expression) {
    final parsed = CharacterExpressionLayers.parse(expression);
    final first = parsed.layers.isEmpty ? null : parsed.layers.first;
    if (first != null) {
      return first.name;
    }
    return CharacterExpressionLayers.stripPrefixes(expression.trim());
  }

  /// 清理缓存（在必要时调用）
  static void clearCache() {
    _layerCache.clear();
  }
}
