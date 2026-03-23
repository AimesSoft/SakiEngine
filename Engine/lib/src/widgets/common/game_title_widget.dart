import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
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
  Widget? _cachedLightImage;
  Widget? _cachedDarkImage;
  String? _cachedImagePath;
  double? _cachedScale; // 添加缓存的缩放值

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

  void _preloadImages() {
    // 当路径或缩放值变化时，重新生成缓存
    if (widget.config.mainMenuTitle.isNotEmpty && 
        (_cachedImagePath != widget.config.mainMenuTitle || _cachedScale != widget.textScale)) {
      _cachedImagePath = widget.config.mainMenuTitle;
      _cachedScale = widget.textScale;
      
      // 预载入浅色模式图片（原图）
      _cachedLightImage = SmartAssetImage(
        assetName: widget.config.mainMenuTitle,
        height: widget.config.mainMenuTitleSize * widget.textScale,
        errorWidget: Container(), // 使用空容器避免闪烁
      );
      
      // 预载入深色模式图片
      String darkImagePath = widget.config.mainMenuTitle;
      final pathParts = darkImagePath.split('.');
      if (pathParts.length > 1) {
        final extension = pathParts.last;
        final nameWithoutExtension = pathParts.sublist(0, pathParts.length - 1).join('.');
        darkImagePath = '${nameWithoutExtension.replaceAll(RegExp(r'main[^/]*$'), 'main_yoru')}.$extension';
      }
      
      _cachedDarkImage = SmartAssetImage(
        assetName: darkImagePath,
        height: widget.config.mainMenuTitleSize * widget.textScale,
        errorWidget: Container(), // 使用空容器避免闪烁
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDarkMode = SettingsManager().currentDarkMode;
    
    // 预载入图片
    _preloadImages();
  
    Widget titleImage;
    
    if (widget.config.mainMenuTitle.isNotEmpty) {
      if (isDarkMode && _cachedDarkImage != null) {
        // 深色模式使用深色图片
        titleImage = _cachedDarkImage!;
      } else if (!isDarkMode && _cachedLightImage != null) {
        // 浅色模式使用浅色图片，并应用反色滤镜
        titleImage = ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            -1.0, 0, 0, 0, 255,
            0, -1.0, 0, 0, 255,
            0, 0, -1.0, 0, 255,
            0, 0, 0, 1.0, 0,
          ]),
          child: _cachedLightImage!,
        );
      } else {
        // fallback：如果缓存还没准备好，显示文字
        titleImage = Text(
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
        );
      }
    } else {
      // 没有配置图片时显示文字
      titleImage = Text(
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
      );
    }
    
    return Positioned(
      top: widget.config.hasBottom ? null : screenSize.height * widget.config.mainMenuTitleTop,
      bottom: widget.config.hasBottom ? screenSize.height * widget.config.mainMenuTitleBottom : null,
      left: widget.config.hasLeft ? screenSize.width * widget.config.mainMenuTitleLeft : null,
      right: widget.config.hasLeft ? null : screenSize.width * widget.config.mainMenuTitleRight,
      child: titleImage,
    );
  }
}