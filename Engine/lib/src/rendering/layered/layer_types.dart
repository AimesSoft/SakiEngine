/// 图层类型和数据结构定义
/// 
/// 定义了层叠图像系统中的基础数据类型
library layer_types;

import 'package:sakiengine/src/utils/foundation_compat.dart';

/// 图层类型枚举
enum LayerType {
  /// 背景层 - 通常是最底层的图像
  background,
  /// 角色基础层 - 角色的基本形象
  characterBase,
  /// 表情层 - 角色的面部表情
  expression,
  /// 服装层 - 角色的衣服
  clothing,
  /// 配饰层 - 帽子、眼镜等配饰
  accessory,
  /// 特效层 - 特殊效果
  effect,
  /// 前景层 - 最顶层的装饰
  foreground,
}

/// 图层信息类
class LayerInfo {
  /// 图层唯一标识符
  final String layerId;
  
  /// 图层类型
  final LayerType type;
  
  /// 资源路径或名称
  final String assetPath;
  
  /// 图层在Z轴上的顺序（数值越大越靠前）
  final int zOrder;
  
  /// 是否可见
  final bool visible;
  
  /// 透明度 (0.0-1.0)
  final double opacity;
  
  /// X偏移量
  final double offsetX;
  
  /// Y偏移量
  final double offsetY;
  
  /// 缩放比例
  final double scale;
  
  /// 混合模式
  final String? blendMode;
  
  /// 创建时间戳（用于缓存管理）
  final DateTime createdAt;
  
  /// 最后访问时间（用于缓存淘汰）
  DateTime lastAccessTime;

  LayerInfo({
    required this.layerId,
    required this.type,
    required this.assetPath,
    required this.zOrder,
    this.visible = true,
    this.opacity = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.blendMode,
    DateTime? createdAt,
    DateTime? lastAccessTime,
  }) : createdAt = createdAt ?? DateTime.now(),
       lastAccessTime = lastAccessTime ?? DateTime.now();

  /// 更新访问时间
  void updateAccessTime() {
    lastAccessTime = DateTime.now();
  }

  /// 创建副本
  LayerInfo copyWith({
    String? layerId,
    LayerType? type,
    String? assetPath,
    int? zOrder,
    bool? visible,
    double? opacity,
    double? offsetX,
    double? offsetY,
    double? scale,
    String? blendMode,
  }) {
    return LayerInfo(
      layerId: layerId ?? this.layerId,
      type: type ?? this.type,
      assetPath: assetPath ?? this.assetPath,
      zOrder: zOrder ?? this.zOrder,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      scale: scale ?? this.scale,
      blendMode: blendMode ?? this.blendMode,
      createdAt: createdAt,
      lastAccessTime: lastAccessTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerInfo &&
          runtimeType == other.runtimeType &&
          layerId == other.layerId &&
          type == other.type &&
          assetPath == other.assetPath &&
          zOrder == other.zOrder &&
          visible == other.visible &&
          opacity == other.opacity &&
          offsetX == other.offsetX &&
          offsetY == other.offsetY &&
          scale == other.scale &&
          blendMode == other.blendMode;

  @override
  int get hashCode =>
      layerId.hashCode ^
      type.hashCode ^
      assetPath.hashCode ^
      zOrder.hashCode ^
      visible.hashCode ^
      opacity.hashCode ^
      offsetX.hashCode ^
      offsetY.hashCode ^
      scale.hashCode ^
      (blendMode?.hashCode ?? 0);

  @override
  String toString() {
    return 'LayerInfo(id: $layerId, type: $type, asset: $assetPath, z: $zOrder, visible: $visible)';
  }
}

/// 层叠图像的完整状态
class LayeredImageState {
  /// 所有图层的列表，按zOrder排序
  final List<LayerInfo> layers;
  
  /// 图像的唯一标识符
  final String imageId;
  
  /// 当前激活的属性集合
  final Set<String> activeAttributes;
  
  /// 状态创建时间
  final DateTime createdAt;
  
  /// 图像的整体透明度
  final double globalOpacity;
  
  /// 图像的整体缩放
  final double globalScale;

  LayeredImageState({
    required this.imageId,
    required this.layers,
    required this.activeAttributes,
    DateTime? createdAt,
    this.globalOpacity = 1.0,
    this.globalScale = 1.0,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 按Z顺序获取可见图层
  List<LayerInfo> get visibleLayers {
    return layers
        .where((layer) => layer.visible)
        .toList()
      ..sort((a, b) => a.zOrder.compareTo(b.zOrder));
  }

  /// 检查状态是否发生变化
  bool hasChangedFrom(LayeredImageState? other) {
    if (other == null) return true;
    if (imageId != other.imageId) return true;
    if (!setEquals(activeAttributes, other.activeAttributes)) return true;
    if (layers.length != other.layers.length) return true;
    
    for (int i = 0; i < layers.length; i++) {
      if (layers[i] != other.layers[i]) return true;
    }
    
    return false;
  }

  /// 创建副本
  LayeredImageState copyWith({
    List<LayerInfo>? layers,
    String? imageId,
    Set<String>? activeAttributes,
    double? globalOpacity,
    double? globalScale,
  }) {
    return LayeredImageState(
      imageId: imageId ?? this.imageId,
      layers: layers ?? List.from(this.layers),
      activeAttributes: activeAttributes ?? Set.from(this.activeAttributes),
      createdAt: createdAt,
      globalOpacity: globalOpacity ?? this.globalOpacity,
      globalScale: globalScale ?? this.globalScale,
    );
  }

  @override
  String toString() {
    return 'LayeredImageState(id: $imageId, layers: ${layers.length}, attributes: $activeAttributes)';
  }
}

/// 图层变化事件
class LayerChangeEvent {
  /// 变化类型
  final LayerChangeType type;
  
  /// 受影响的图层ID
  final String layerId;
  
  /// 旧的图层信息
  final LayerInfo? oldLayer;
  
  /// 新的图层信息
  final LayerInfo? newLayer;
  
  /// 事件时间戳
  final DateTime timestamp;

  LayerChangeEvent({
    required this.type,
    required this.layerId,
    this.oldLayer,
    this.newLayer,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'LayerChangeEvent(type: $type, layerId: $layerId, time: $timestamp)';
  }
}

/// 图层变化类型
enum LayerChangeType {
  /// 添加新图层
  added,
  /// 移除图层
  removed,
  /// 更新图层属性
  updated,
  /// 图层可见性变化
  visibilityChanged,
  /// 图层顺序变化
  orderChanged,
}

/// 性能统计信息
class LayeredRenderingStats {
  /// 当前活跃图层数量
  final int activeLayers;
  
  /// 缓存命中率
  final double cacheHitRate;
  
  /// 平均渲染时间（毫秒）
  final double averageRenderTime;
  
  /// GPU内存使用量（字节）
  final int gpuMemoryUsage;
  
  /// 系统内存使用量（字节）
  final int systemMemoryUsage;
  
  /// 每秒渲染帧数
  final double framesPerSecond;
  
  /// 统计时间窗口
  final Duration timeWindow;
  
  /// 统计时间戳
  final DateTime timestamp;

  LayeredRenderingStats({
    required this.activeLayers,
    required this.cacheHitRate,
    required this.averageRenderTime,
    required this.gpuMemoryUsage,
    required this.systemMemoryUsage,
    required this.framesPerSecond,
    required this.timeWindow,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'LayeredRenderingStats(layers: $activeLayers, cache: ${(cacheHitRate * 100).toStringAsFixed(1)}%, fps: ${framesPerSecond.toStringAsFixed(1)})';
  }
}