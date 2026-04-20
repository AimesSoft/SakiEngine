class CharacterConfig {
  final String id;
  final String name;
  final String resourceId;
  final String? defaultPoseId;
  final String? slotId;

  CharacterConfig({
    required this.id,
    required this.name,
    required this.resourceId,
    this.defaultPoseId,
    this.slotId,
  });
}

class PoseConfig {
  final String id;
  final double scale;
  final double xcenter;
  final double ycenter;
  final String anchor;

  PoseConfig({
    required this.id,
    this.scale = 0,
    this.xcenter = 0.5,
    this.ycenter = 1.0,
    this.anchor = 'bottomCenter',
  });
  
  /// 检查是否为自动分布锚点
  bool get isAutoAnchor => anchor == 'auto';
  
  /// 创建一个用于自动分布的新配置
  PoseConfig copyWithAutoDistribution(double newXCenter) {
    return PoseConfig(
      id: id,
      scale: scale,
      xcenter: newXCenter,
      ycenter: ycenter, // 保持原始的ycenter
      anchor: anchor == 'auto' ? 'center' : anchor, // 只有当anchor=auto时才改为center，否则保持原值
    );
  }
} 
