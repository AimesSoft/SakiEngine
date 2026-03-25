import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

class GameBackgroundWidget extends StatelessWidget {
  final SakiEngineConfig config;
  final String? customBackgroundName; // 新增：自定义背景名称

  const GameBackgroundWidget({
    super.key,
    required this.config,
  }) : customBackgroundName = null;

  // 新增：支持自定义背景名称的构造函数
  const GameBackgroundWidget.withCustomBackground({
    super.key,
    required this.config,
    required String backgroundName,
  }) : customBackgroundName = backgroundName;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = SettingsManager().currentDarkMode;
    
    // 使用自定义背景名称或配置文件中的背景
    String originalBackground = customBackgroundName ?? config.mainMenuBackground;
    // 根据主题模式选择背景图片
    String backgroundPath = originalBackground;
    if (isDarkMode && backgroundPath.isNotEmpty) {
      // 深色模式下使用 _yoru 版本
      if (backgroundPath == 'main') {
        backgroundPath = 'main_yoru';
      } else {
        // 处理有扩展名的情况
        final pathParts = backgroundPath.split('.');
        if (pathParts.length > 1) {
          final extension = pathParts.last;
          final nameWithoutExtension = pathParts.sublist(0, pathParts.length - 1).join('.');
          if (!nameWithoutExtension.contains('_yoru')) {
            backgroundPath = '${nameWithoutExtension}_yoru.$extension';
          }
        } else {
          // 没有扩展名的情况
          if (!backgroundPath.contains('_yoru')) {
            backgroundPath = '${backgroundPath}_yoru';
          }
        }
      }
    }    
    return SmartAssetImage(
      assetName: 'backgrounds/$backgroundPath',
      fit: BoxFit.cover,
      errorWidget: Container(color: Colors.black),
    );
  }
}