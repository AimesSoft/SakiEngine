import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/utils/character_composite_cache.dart';

/// 差分偏移配置类
class ExpressionOffsetConfig {
  final String characterId;
  final String pose;
  final double yOffset; // 纵向偏移量（归一化值，相对于角色高度，-1.0到1.0）
  final double xOffset; // 横向偏移量（归一化值，相对于角色宽度，-1.0到1.0）
  final double alpha; // 透明度（0.0到1.0，1.0为完全不透明）
  final double scale; // 缩放比例（1.0为原始大小，锚点为左上角）
  
  const ExpressionOffsetConfig({
    required this.characterId,
    required this.pose,
    required this.yOffset,
    this.xOffset = 0.0,
    this.alpha = 1.0, // 默认完全不透明
    this.scale = 1.0, // 新增：默认原始大小
  });
  
  String get key => '${characterId}_$pose';
  
  @override
  String toString() => 'ExpressionOffsetConfig($characterId, $pose, x:$xOffset, y:$yOffset, a:$alpha, s:$scale)';
}

/// 差分偏移管理器
/// 用于管理特定角色、特定姿势下差分（表情）图层的位置偏移
/// 所有偏移值都是归一化的，适应窗口缩放
class ExpressionOffsetManager {
  static final ExpressionOffsetManager _instance = ExpressionOffsetManager._internal();
  factory ExpressionOffsetManager() => _instance;
  ExpressionOffsetManager._internal();
  
  // 偏移配置映射表
  final Map<String, ExpressionOffsetConfig> _offsetConfigs = {};
  
  /// 初始化默认配置
  void initializeDefaultConfigs() {
    // xiayo1 角色的特定姿势偏移配置
    // 负值向上/左偏移，正值向下/右偏移
    addOffsetConfig(ExpressionOffsetConfig(
      characterId: 'xiayo1',
      pose: 'pose6',
      xOffset: 0.0, // 横向偏移（可调整）
      yOffset: 0.028, // 纵向偏移（可调整）
      alpha: 1.0, // 透明度便于对准
      scale: 1.0, // 新增：缩放比例（可调整）
    ));
    
    // xiayo1 pose6 帽子配置
    addOffsetConfig(ExpressionOffsetConfig(
      characterId: 'xiayo1',
      pose: 'pose6_hat',
      xOffset: 0.0, // 横向偏移（可调整）
      yOffset: 0.0, // 纵向偏移（可调整）
      alpha: 1.0, // 透明度
      scale: 1.0, // 缩放比例（可调整）
    ));
    
    addOffsetConfig(ExpressionOffsetConfig(
      characterId: 'xiayo1',
      pose: 'pose7',
      xOffset: 0.0, // 横向偏移（可调整）
      yOffset: 0.028, // 纵向偏移（可调整）
      alpha: 1.0, // 透明度便于对准
      scale: 1.0, // 新增：缩放比例（可调整）
    ));
    
    // xiayo1 pose7 帽子配置
    addOffsetConfig(ExpressionOffsetConfig(
      characterId: 'xiayo1',
      pose: 'pose7_hat',
      xOffset: 0.0, // 横向偏移（可调整）
      yOffset: 0.0, // 纵向偏移（可调整）
      alpha: 1.0, // 透明度
      scale: 1.0, // 缩放比例（可调整）
    ));
    
    addOffsetConfig(ExpressionOffsetConfig(
      characterId: 'xiayo1',
      pose: 'pose8',
      xOffset: 0.0, // 横向偏移（可调整）
      yOffset: 0.028, // 纵向偏移（可调整）
      alpha: 1.0, // 透明度便于对准
      scale: 1.0, // 新增：缩放比例（可调整）
    ));
    
    // xiayo1 pose8 帽子配置
    addOffsetConfig(ExpressionOffsetConfig(
      characterId: 'xiayo1',
      pose: 'pose8_hat',
      xOffset: 0.0, // 横向偏移（可调整）
      yOffset: 0.0, // 纵向偏移（可调整）
      alpha: 1.0, // 透明度
      scale: 1.0, // 缩放比例（可调整）
    ));
    
    // 默认配置初始化日志已移除
  }
  
  /// 添加偏移配置
  void addOffsetConfig(ExpressionOffsetConfig config) {
    _offsetConfigs[config.key] = config;
    CharacterCompositeCache.instance.invalidate(
      config.characterId,
      config.pose,
    );
  }
  
  /// 移除偏移配置
  void removeOffsetConfig(String characterId, String pose) {
    final key = '${characterId}_$pose';
    final removed = _offsetConfigs.remove(key);
    if (removed != null) {
      CharacterCompositeCache.instance.invalidate(characterId, pose);
    }
  }
  
  /// 获取差分偏移、透明度和缩放（归一化值）
  /// [characterId] 角色ID (如 'xiayo1')
  /// [pose] 姿势 (如 'pose6', 'pose7', 'pose8')
  /// [layerType] 图层类型，包含 'expression' 或 'hat' 的图层类型才应用偏移
  /// 返回 (xOffset, yOffset, alpha, scale) 归一化偏移量、透明度和缩放比例
  (double, double, double, double) getExpressionOffset({
    required String characterId,
    required String pose,
    required String layerType,
  }) {
    // 检查是否为需要偏移的图层类型（表情或帽子）
    final isExpressionLayer = layerType.contains('expression');
    final isHatLayer = layerType.contains('hat');
    
    if (!isExpressionLayer && !isHatLayer) {
      return (0.0, 0.0, 1.0, 1.0); // 非表情/帽子图层使用默认值
    }
    
    String configKey;
    if (isHatLayer) {
      // 帽子图层使用特殊配置键
      configKey = '${characterId}_${pose}_hat';
    } else {
      // 表情图层使用原有配置键
      configKey = '${characterId}_$pose';
    }
    
    final config = _offsetConfigs[configKey];
    
    if (config != null) {
      return (config.xOffset, config.yOffset, config.alpha, config.scale);
    }
    
    return (0.0, 0.0, 1.0, 1.0); // 默认无偏移，完全不透明，原始大小
  }
  
  /// 获取所有配置（用于调试）
  Map<String, ExpressionOffsetConfig> getAllConfigs() => Map.unmodifiable(_offsetConfigs);
  
  /// 清空所有配置
  void clearAllConfigs() {
    _offsetConfigs.clear();
    // 静默清理
  }
  
  /// 动态调整偏移量（用于实时调试）
  /// [characterId] 角色ID
  /// [pose] 姿势
  /// [yOffset] 纵向偏移量（归一化值，相对于角色高度）
  /// [xOffset] 横向偏移量（归一化值，相对于角色宽度）
  void adjustOffset({
    required String characterId,
    required String pose,
    required double yOffset,
    double xOffset = 0.0,
  }) {
    final config = ExpressionOffsetConfig(
      characterId: characterId,
      pose: pose,
      yOffset: yOffset,
      xOffset: xOffset,
    );
    addOffsetConfig(config);
  }
  
  /// 批量设置 xiayo1 姿势 6、7、8 的偏移量（便于调试）
  /// 所有偏移量都是归一化值
  void setXiayo1SpecialPosesOffset({
    required double pose6YOffset,
    required double pose7YOffset,
    required double pose8YOffset,
    double xOffset = 0.0,
  }) {
    adjustOffset(characterId: 'xiayo1', pose: '6', yOffset: pose6YOffset, xOffset: xOffset);
    adjustOffset(characterId: 'xiayo1', pose: '7', yOffset: pose7YOffset, xOffset: xOffset);
    adjustOffset(characterId: 'xiayo1', pose: '8', yOffset: pose8YOffset, xOffset: xOffset);
    
    // 静默调整
  }
  
  /// 纳米级控制方法 - 微调单个姿势的偏移量
  /// [delta] 偏移增量（归一化值），正值向下/右，负值向上/左
  void tweakOffset({
    required String characterId,
    required String pose,
    required double deltaY,
    double deltaX = 0.0,
  }) {
    final key = '${characterId}_$pose';
    final currentConfig = _offsetConfigs[key];
    
    if (currentConfig != null) {
      final newConfig = ExpressionOffsetConfig(
        characterId: characterId,
        pose: pose,
        yOffset: currentConfig.yOffset + deltaY,
        xOffset: currentConfig.xOffset + deltaX,
      );
      addOffsetConfig(newConfig);
      // 静默微调
    } else {
      // 如果没有配置，创建新的
      adjustOffset(characterId: characterId, pose: pose, yOffset: deltaY, xOffset: deltaX);
    }
  }
}
