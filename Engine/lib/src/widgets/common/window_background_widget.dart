import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

class WindowBackgroundWidget extends StatelessWidget {
  final Widget child;
  final SakiEngineConfig config;

  const WindowBackgroundWidget({
    super.key,
    required this.child,
    required this.config,
  });

  // 获取SVG色温调整滤镜
  ColorFilter? _getSvgColorTemperatureFilter() {
    final isDarkMode = SettingsManager().currentDarkMode;
    
    if (!isDarkMode) {
      return config.baseWindowBackgroundBlendMode == BlendMode.multiply 
          ? ColorFilter.mode(Colors.transparent, config.baseWindowBackgroundBlendMode)
          : null;
    }
    
    // 夜间模式下应用色温调整（冷色调）
    // 为SVG背景图案应用色温矩阵
    return const ColorFilter.matrix([
      // R  G  B  A  Offset  
      0.6, 0.1, 0.3, 0, 30,   // 红色通道：减少红色，增加蓝色成分
      0.1, 0.8, 0.1, 0, 15,   // 绿色通道：保持绿色
      0.4, 0.2, 1.3, 0, 50,   // 蓝色通道：大幅增强蓝色
      0,   0,   0,   1, 0,    // Alpha通道：保持不变
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (config.baseWindowBackground == null || config.baseWindowBackground!.isEmpty) {
      return child;
    }

    return ClipRect(
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: config.baseWindowBackgroundAlpha,
                child: ColorFiltered(
                  colorFilter: _getSvgColorTemperatureFilter() ?? ColorFilter.mode(
                    Colors.transparent,
                    config.baseWindowBackgroundBlendMode,
                  ),
                  child: Align(
                    alignment: Alignment(
                      (config.baseWindowXAlign - 0.5) * 2,
                      (config.baseWindowYAlign - 0.5) * 2,
                    ),
                    child: SmartAssetImage(
                      assetName: config.baseWindowBackground!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}