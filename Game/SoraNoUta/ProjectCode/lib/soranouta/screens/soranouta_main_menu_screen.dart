import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/screens/save_load_screen.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/music_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';
import 'package:sakiengine/src/widgets/debug_panel_dialog.dart';
import 'package:sakiengine/src/widgets/common/exit_confirmation_dialog.dart';
import 'package:sakiengine/src/widgets/settings_screen.dart';
import 'package:sakiengine/src/widgets/common/game_title_widget.dart';
import 'package:sakiengine/src/widgets/common/game_background_widget.dart';
import '../widgets/soranouta_menu_buttons.dart';
import '../widgets/firefly_animation.dart';
import 'package:sakiengine/src/game/save_load_manager.dart';
import 'package:sakiengine/src/screens/story_flowchart_screen.dart';
import 'package:sakiengine/src/game/story_flowchart_analyzer.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:sakiengine/src/localization/localization_manager.dart';

/// SoraNoUta 项目的自定义主菜单屏幕
/// 使用模块化标题组件 + 专用按钮
class SoraNoutaMainMenuScreen extends StatefulWidget {
  final VoidCallback onNewGame;
  final VoidCallback onLoadGame;
  final Function(SaveSlot)? onLoadGameWithSave;
  final VoidCallback? onContinueGame; // 新增：继续游戏回调（快速读档）
  final bool skipMusicDelay;

  const SoraNoutaMainMenuScreen({
    Key? key,
    required this.onNewGame,
    required this.onLoadGame,
    this.onLoadGameWithSave,
    this.onContinueGame, // 新增：继续游戏回调
    this.skipMusicDelay = false,
  }) : super(key: key);

  @override
  State<SoraNoutaMainMenuScreen> createState() =>
      _SoraNoutaMainMenuScreenState();
}

class _SoraNoutaMainMenuScreenState extends State<SoraNoutaMainMenuScreen> {
  bool _showLoadOverlay = false;
  bool _showDebugPanel = false;
  bool _showSettings = false;
  bool _showFlowchart = false; // 新增：流程图覆盖层状态
  bool _isDarkModeButtonHovered = false;
  bool _isFlowchartButtonHovered = false; // 新增：流程图按钮悬停状态
  bool _startMenuAnimation = false; // 控制菜单动画开始
  bool _hasQuickSave = false; // 新增：标记是否有快速存档
  late String _copyrightText;
  late final LocalizationManager _localizationManager;
  final _uiSoundManager = UISoundManager(); // 新增：UI音效管理器

  @override
  void initState() {
    super.initState();
    _localizationManager = LocalizationManager();
    _localizationManager.addListener(_handleLocalizationChanged);
    _generateCopyrightText();
    _checkQuickSave();

    // 延迟播放音乐和启动动画，确保页面已显示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundMusic();
      _initMenuAnimation();
    });
  }

  void _handleLocalizationChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // 新增：检查快速存档是否存在
  Future<void> _checkQuickSave() async {
    try {
      final hasQuickSave = await SaveLoadManager().hasQuickSave();
      if (mounted) {
        setState(() {
          _hasQuickSave = hasQuickSave;
        });
      }
    } catch (e) {
      // 忽略错误
    }
  }

  // 新增：处理继续游戏（快速读档）
  void _handleContinueGame() {
    if (widget.onContinueGame != null) {
      widget.onContinueGame!();
    }
  }

  void _generateCopyrightText() {
    final random = Random();
    final randomValue = random.nextDouble();

    if (randomValue < 0.1) {
      _copyrightText = 'Ⓒ Copyright 950-2050 Aimes Soft';
    } else {
      _copyrightText = 'Ⓒ Copyright 2023-2025 Aimes Soft';
    }
  }

  @override
  void dispose() {
    _localizationManager.removeListener(_handleLocalizationChanged);
    super.dispose();
  }

  void _initMenuAnimation() {
    if (mounted) {
      setState(() {
        _startMenuAnimation = true;
      });
    }
  }

  Future<void> _startBackgroundMusic() async {
    try {
      // 如果是从游戏返回主菜单，立即播放；否则等待一小段时间让页面渲染
      if (widget.skipMusicDelay) {
        await MusicManager().playBackgroundMusic('Assets/music/dream.mp3');
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await MusicManager().playBackgroundMusic('Assets/music/dream.mp3');
        }
      }
    } catch (e) {
      // Silently handle music loading errors
    }
  }

  Future<void> _showExitConfirmation(BuildContext context) async {
    await ExitConfirmationDialog.showExitConfirmationAndDestroy(context);
  }

  String _resolveLocalizedTitleAsset() {
    var assetName = 'title';
    switch (_localizationManager.currentLanguage) {
      case SupportedLanguage.zhHans:
        assetName = 'title_chs';
        break;
      case SupportedLanguage.zhHant:
        assetName = 'title_cht';
        break;
      case SupportedLanguage.en:
        assetName = 'title_en';
        break;
      case SupportedLanguage.ja:
        assetName = 'title_jp';
        break;
    }
    return assetName;
  }

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final screenSize = MediaQuery.of(context).size;
    final menuScale = context.scaleFor(ComponentType.menu);
    final textScale = context.scaleFor(ComponentType.text);
    final isDarkMode = SettingsManager().currentDarkMode;

    // 根据当前语言选择对应的标题资源
    config.mainMenuTitle = _resolveLocalizedTitleAsset();

    return AnimatedBuilder(
      animation: SettingsManager(), // 监听设置变化
      builder: (context, child) {
        // 当设置变化时，重新更新主题配置
        config.updateThemeForDarkMode();

        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 模块化背景组件 - soranouta 直接控制背景
              GameBackgroundWidget.withCustomBackground(
                config: config,
                backgroundName: 'main', // soranouta 直接传递 'main'
              ),

              // 萤火虫动画层 - 在背景之上，其他UI之下
              const Positioned.fill(
                child: FireflyAnimation(
                  fireflyCount: 8, // 减少数量：苍蝇变萤火虫
                  maxRadius: 3.5, // 增大最大尺寸
                  minRadius: 1.0, // 减小最小尺寸，增加变化范围
                  maxSpeed: 0.15, // 大幅降低速度
                  minSpeed: 0.08,
                ),
              ),

              // 模块化标题组件
              GameTitleWidget(
                config: config,
                textScale: menuScale, // 使用菜单缩放系数而不是文本缩放系数
              ),

              // 按钮区域的白色模糊阴影层 - 使用淡入动画
              SoranoutaMenuButtons.createShadowWidget(
                config: config,
                scale: menuScale,
                screenSize: screenSize,
                onContinueGame:
                    _hasQuickSave ? _handleContinueGame : null, // 新增：传递继续游戏回调
                startAnimation: _startMenuAnimation, // 与按钮动画同步
              ),

              // SoraNoUta 专用按钮，参与卷帘动画
              SoranoutaMenuButtons.createButtonsWidget(
                onNewGame: widget.onNewGame,
                onContinueGame:
                    _hasQuickSave ? _handleContinueGame : null, // 新增：传递继续游戏回调
                onLoadGame: () => setState(() => _showLoadOverlay = true),
                onSettings: () => setState(() => _showSettings = true),
                onExit: () => _showExitConfirmation(context),
                config: config,
                scale: menuScale,
                screenSize: screenSize,
                startAnimation: _startMenuAnimation,
              ),

              // 版权信息阴影层
              Positioned(
                right: 20,
                bottom: 20,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                  child: Text(
                    _copyrightText,
                    style: TextStyle(
                      fontFamily: 'ChillJinshuSongPro_Soft',
                      fontSize: 40 * textScale,
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.9)
                          : Colors.black.withOpacity(0.9),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              ),

              // 版权信息文本
              Positioned(
                right: 20,
                bottom: 20,
                child: Text(
                  _copyrightText,
                  style: TextStyle(
                    fontFamily: 'ChillJinshuSongPro_Soft',
                    fontSize: 40 * textScale,
                    color: isDarkMode ? Colors.black : Colors.white,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),

              // 深色模式切换按钮阴影层
              Positioned(
                left: 20,
                bottom: 20,
                child: AnimatedScale(
                  scale: _isDarkModeButtonHovered ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        return RotationTransition(
                          turns: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        key: ValueKey(isDarkMode ? 'dark' : 'light'),
                        size: 48 * textScale,
                        color: isDarkMode
                            ? Colors.white.withOpacity(0.9)
                            : Colors.black.withOpacity(0.9),
                      ),
                    ),
                  ),
                ),
              ),

              // 深色模式切换按钮
              Positioned(
                left: 20,
                bottom: 20,
                child: AnimatedScale(
                  scale: _isDarkModeButtonHovered ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) {
                      setState(() => _isDarkModeButtonHovered = true);
                      _uiSoundManager.playButtonHover();
                    },
                    onExit: (_) =>
                        setState(() => _isDarkModeButtonHovered = false),
                    child: GestureDetector(
                      onTapDown: (_) =>
                          setState(() => _isDarkModeButtonHovered = true),
                      onTapUp: (_) {
                        setState(() => _isDarkModeButtonHovered = false);
                        _uiSoundManager.playButtonClick();
                      },
                      onTapCancel: () =>
                          setState(() => _isDarkModeButtonHovered = false),
                      onTap: () async {
                        final newDarkMode = !isDarkMode;
                        await SettingsManager().setDarkMode(newDarkMode);
                        config.updateThemeForDarkMode();
                        // 触发重建以更新图标
                        if (mounted) {
                          setState(() {});
                        }
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                          return RotationTransition(
                            turns: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          isDarkMode ? Icons.dark_mode : Icons.light_mode,
                          key: ValueKey(isDarkMode ? 'dark' : 'light'),
                          size: 48 * textScale,
                          color: _isDarkModeButtonHovered
                            ? (isDarkMode ? Colors.white : Colors.black)
                            : (isDarkMode ? Colors.black : Colors.white),
                      ),
                      ),
                    ),
                  ),
                ),
              ),

              // 流程图按钮阴影层
              Positioned(
                left: 90,
                bottom: 20,
                child: AnimatedScale(
                  scale: _isFlowchartButtonHovered ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: Icon(
                      Icons.account_tree,
                      size: 48 * textScale,
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.9)
                          : Colors.black.withOpacity(0.9),
                    ),
                  ),
                ),
              ),

              // 流程图按钮
              Positioned(
                left: 90,
                bottom: 20,
                child: AnimatedScale(
                  scale: _isFlowchartButtonHovered ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) {
                      setState(() => _isFlowchartButtonHovered = true);
                      _uiSoundManager.playButtonHover();
                    },
                    onExit: (_) =>
                        setState(() => _isFlowchartButtonHovered = false),
                    child: GestureDetector(
                      onTapDown: (_) =>
                          setState(() => _isFlowchartButtonHovered = true),
                      onTapUp: (_) {
                        setState(() => _isFlowchartButtonHovered = false);
                        _uiSoundManager.playButtonClick();
                      },
                      onTapCancel: () =>
                          setState(() => _isFlowchartButtonHovered = false),
                      onTap: () async {
                        _uiSoundManager.playButtonClick();
                        // 先分析脚本（如果需要）
                        final analyzer = StoryFlowchartAnalyzer();
                        await analyzer.analyzeScript();
                        // 显示流程图覆盖层
                        setState(() => _showFlowchart = true);
                      },
                      child: Icon(
                        Icons.account_tree,
                        size: 48 * textScale,
                        color: _isFlowchartButtonHovered
                            ? (isDarkMode ? Colors.white : Colors.black)
                            : (isDarkMode ? Colors.black : Colors.white),
                      ),
                    ),
                  ),
                ),
              ),

              // 覆盖层
              if (_showLoadOverlay)
                SaveLoadScreen(
                  mode: SaveLoadMode.load,
                  onClose: () => setState(() => _showLoadOverlay = false),
                  onLoadSlot: widget.onLoadGameWithSave,
                ),

              if (_showSettings)
                SettingsScreen(
                  onClose: () => setState(() => _showSettings = false),
                ),

              if (_showFlowchart)
                StoryFlowchartScreen(
                  onClose: () => setState(() => _showFlowchart = false),
                  onLoadSave: (saveSlot) {
                    widget.onLoadGameWithSave?.call(saveSlot);
                    setState(() => _showFlowchart = false);
                  },
                ),

              if (_showDebugPanel)
                DebugPanelDialog(
                  onClose: () => setState(() => _showDebugPanel = false),
                ),
            ],
          ),
        );
      },
    );
  }
}
