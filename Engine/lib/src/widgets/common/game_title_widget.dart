import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';

class GameTitleWidget extends StatefulWidget {
  final SakiEngineConfig config;
  final double textScale;

  const GameTitleWidget({
    super.key,
    required this.config,
    required this.textScale,
  });

  @override
  State<GameTitleWidget> createState() => _GameTitleWidgetState();
}

class _GameTitleWidgetState extends State<GameTitleWidget> {
  String _appTitle = 'SakiEngine';

  @override
  void initState() {
    super.initState();
    _loadAppTitle();
  }

  Future<void> _loadAppTitle() async {
    try {
      final appName = await ProjectInfoManager().getAppName();
      if (mounted) {
        setState(() {
          _appTitle = appName;
        });
      }
    } catch (e) {
      // 保持默认标题
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDarkMode = SettingsManager().currentDarkMode;
    
    print('[GameTitleWidget] isDarkMode: $isDarkMode');
    print('[GameTitleWidget] 原始标题: ${widget.config.mainMenuTitle}');
    
    // 根据主题模式选择图片文件
    String titleImagePath = widget.config.mainMenuTitle;
    if (isDarkMode && titleImagePath.isNotEmpty) {
      // 深色模式下使用 main_yoru.png
      final pathParts = titleImagePath.split('.');
      if (pathParts.length > 1) {
        final extension = pathParts.last;
        final nameWithoutExtension = pathParts.sublist(0, pathParts.length - 1).join('.');
        titleImagePath = '${nameWithoutExtension.replaceAll(RegExp(r'main[^/]*$'), 'main_yoru')}.$extension';
      }
    }
    
    print('[GameTitleWidget] 最终标题路径: $titleImagePath');
    print('[GameTitleWidget] 全局反色模式，不再单独应用滤镜');
    
    Widget titleImage = SmartAssetImage(
      assetName: titleImagePath,
      height: widget.config.mainMenuTitleSize * widget.textScale,
      errorWidget: Text(
        _appTitle,
        style: TextStyle(
          fontFamily: 'SourceHanSansCN',
          fontSize: widget.config.mainMenuTitleSize * widget.textScale,
          color: widget.config.themeColors.background,
          letterSpacing: 4,
          shadows: [
            Shadow(
              blurRadius: 10.0,
              color: widget.config.themeColors.primaryDark,
              offset: const Offset(2, 2),
            ),
          ],
        ),
      ),
    );
    
    // 移除单独的反色滤镜，因为现在使用全局反色
    
    return Positioned(
      top: widget.config.hasBottom ? null : screenSize.height * widget.config.mainMenuTitleTop,
      bottom: widget.config.hasBottom ? screenSize.height * widget.config.mainMenuTitleBottom : null,
      left: widget.config.hasLeft ? screenSize.width * widget.config.mainMenuTitleLeft : null,
      right: widget.config.hasLeft ? null : screenSize.width * widget.config.mainMenuTitleRight,
      child: widget.config.mainMenuTitle.isNotEmpty
          ? titleImage
          : Text(
              _appTitle,
              style: TextStyle(
                fontFamily: 'SourceHanSansCN',
                fontSize: widget.config.mainMenuTitleSize * widget.textScale,
                color: widget.config.themeColors.background,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                    blurRadius: 10.0,
                    color: widget.config.themeColors.primaryDark,
                    offset: const Offset(2, 2),
                  ),
                ],
              ),
            ),
    );
  }
}