import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

class SvgColorFilterUtils {
  /// 获取SVG色温调整滤镜
  /// 在深色模式下应用冷色调效果，浅色模式下使用默认滤镜
  static ColorFilter getSvgColorTemperatureFilter(SakiEngineConfig config) {
    final isDarkMode = SettingsManager().currentDarkMode;
    
    if (!isDarkMode) {
      return ColorFilter.mode(Colors.transparent, config.baseWindowBackgroundBlendMode);
    }
    
    // 夜间模式下应用色温调整（冷色调）
    return const ColorFilter.matrix([
      // R  G  B  A  Offset  
      0.6, 0.1, 0.3, 0, 30,   // 红色通道：减少红色，增加蓝色成分
      0.1, 0.8, 0.1, 0, 15,   // 绿色通道：保持绿色
      0.4, 0.2, 1.3, 0, 50,   // 蓝色通道：大幅增强蓝色
      0,   0,   0,   1, 0,    // Alpha通道：保持不变
    ]);
  }
}