import 'package:flutter/widgets.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

/// 缩放策略枚举
enum ScalingStrategy {
  /// 传统策略：取较小的缩放比例，适合横屏
  fitToSmaller,
  /// 竖屏友好策略：优先考虑高度，给宽度更低权重
  portraitFriendly,
  /// 自定义权重策略：可自定义宽度和高度的权重
  customWeight,
  /// 仅基于高度缩放
  heightBased,
  /// 仅基于宽度缩放
  widthBased,
}

/// 缩放管理器
class ScalingManager {
  static final ScalingManager _instance = ScalingManager._internal();
  factory ScalingManager() => _instance;
  ScalingManager._internal();

  // 默认缩放策略
  ScalingStrategy _strategy = ScalingStrategy.portraitFriendly;
  
  // 自定义权重（当策略为customWeight时使用）
  double _widthWeight = 0.3;  // 宽度权重，默认30%
  double _heightWeight = 0.7; // 高度权重，默认70%
  
  // 最小和最大缩放限制
  double _minScale = 0.5;
  double _maxScale = 2.0;

  /// 设置缩放策略
  void setStrategy(ScalingStrategy strategy) {
    _strategy = strategy;
  }

  /// 设置自定义权重（总和应为1.0）
  void setCustomWeights(double widthWeight, double heightWeight) {
    assert(widthWeight + heightWeight == 1.0, '权重总和必须为1.0');
    _widthWeight = widthWeight;
    _heightWeight = heightWeight;
  }

  /// 设置缩放限制
  void setScaleLimits(double minScale, double maxScale) {
    assert(minScale > 0 && maxScale > minScale, '缩放限制参数无效');
    _minScale = minScale;
    _maxScale = maxScale;
  }

  /// 计算缩放比例
  double calculateScale(Size screenSize, [SakiEngineConfig? config]) {
    config ??= SakiEngineConfig();
    
    final scaleX = screenSize.width / config.logicalWidth;
    final scaleY = screenSize.height / config.logicalHeight;
    
    double scale;
    
    switch (_strategy) {
      case ScalingStrategy.fitToSmaller:
        scale = scaleX < scaleY ? scaleX : scaleY;
        break;
        
      case ScalingStrategy.portraitFriendly:
        // 竖屏友好：给高度更高权重，避免在竖屏时过度缩小
        scale = scaleY * 0.8 + scaleX * 0.2;
        break;
        
      case ScalingStrategy.customWeight:
        scale = scaleX * _widthWeight + scaleY * _heightWeight;
        break;
        
      case ScalingStrategy.heightBased:
        scale = scaleY;
        break;
        
      case ScalingStrategy.widthBased:
        scale = scaleX;
        break;
    }
    
    // 应用缩放限制
    return scale.clamp(_minScale, _maxScale);
  }

  /// 为特定组件计算缩放（可以有不同的策略）
  double calculateScaleForComponent(
    Size screenSize, 
    ComponentType componentType, 
    [SakiEngineConfig? config]
  ) {
    config ??= SakiEngineConfig();
    
    final scaleX = screenSize.width / config.logicalWidth;
    final scaleY = screenSize.height / config.logicalHeight;
    
    double scale;
    
    switch (componentType) {
      case ComponentType.text:
        // 文字优先考虑高度，避免在竖屏时过小
        scale = scaleY * 0.9 + scaleX * 0.1;
        break;
        
      case ComponentType.ui:
        // UI元素适中权重
        scale = scaleY * 0.7 + scaleX * 0.3;
        break;
        
      case ComponentType.character:
        // 角色图片保持比例，但优先高度
        scale = scaleY * 0.8 + scaleX * 0.2;
        break;
        
      case ComponentType.background:
        // 背景图片可以填满屏幕
        scale = scaleX > scaleY ? scaleX : scaleY;
        break;
        
      case ComponentType.menu:
        // 菜单元素优先高度
        scale = scaleY * 0.85 + scaleX * 0.15;
        break;
    }
    
    return scale.clamp(_minScale, _maxScale);
  }

  /// 获取屏幕方向
  ScreenOrientation getScreenOrientation(Size screenSize) {
    final aspectRatio = screenSize.width / screenSize.height;
    
    if (aspectRatio > 1.3) {
      return ScreenOrientation.landscape;
    } else if (aspectRatio < 0.8) {
      return ScreenOrientation.portrait;
    } else {
      return ScreenOrientation.square;
    }
  }

  /// 根据屏幕方向自动调整策略
  void adaptToScreenOrientation(Size screenSize) {
    final orientation = getScreenOrientation(screenSize);
    
    switch (orientation) {
      case ScreenOrientation.portrait:
        // 竖屏时使用竖屏友好策略
        setStrategy(ScalingStrategy.portraitFriendly);
        break;
      case ScreenOrientation.landscape:
        // 横屏时可以使用传统策略
        setStrategy(ScalingStrategy.fitToSmaller);
        break;
      case ScreenOrientation.square:
        // 方形屏幕使用平衡策略
        setCustomWeights(0.5, 0.5);
        setStrategy(ScalingStrategy.customWeight);
        break;
    }
  }

  /// 便捷方法：获取当前策略信息
  Map<String, dynamic> getStrategyInfo() {
    return {
      'strategy': _strategy.toString(),
      'widthWeight': _widthWeight,
      'heightWeight': _heightWeight,
      'minScale': _minScale,
      'maxScale': _maxScale,
    };
  }
}

/// 组件类型枚举
enum ComponentType {
  text,       // 文字
  ui,         // UI元素
  character,  // 角色
  background, // 背景
  menu,       // 菜单
}

/// 屏幕方向枚举
enum ScreenOrientation {
  portrait,   // 竖屏
  landscape,  // 横屏
  square,     // 方形
}

/// 扩展方法，方便在Widget中使用
extension ScalingManagerExtension on BuildContext {
  /// 获取当前屏幕的缩放比例
  double get scale {
    final screenSize = MediaQuery.of(this).size;
    return ScalingManager().calculateScale(screenSize);
  }
  
  /// 获取特定组件的缩放比例
  double scaleFor(ComponentType type) {
    final screenSize = MediaQuery.of(this).size;
    return ScalingManager().calculateScaleForComponent(screenSize, type);
  }
}