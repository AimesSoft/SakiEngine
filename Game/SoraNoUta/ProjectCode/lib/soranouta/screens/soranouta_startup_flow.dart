import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/smart_asset_image.dart';
import 'soranouta_main_menu_screen.dart';
import 'package:sakiengine/src/game/story_flowchart_analyzer.dart';
import 'package:flutter/foundation.dart';

/// soraの歌启动流程：先展示独立的Logo页面，然后切换到主菜单
class SoraNoutaStartupFlow extends StatefulWidget {
  const SoraNoutaStartupFlow({
    super.key,
    required this.onNewGame,
    required this.onLoadGame,
    required this.onLoadGameWithSave,
    this.onContinueGame,
    required this.skipMusicDelay,
    this.splashDuration = const Duration(seconds: 3),
    this.fadeOutDuration = const Duration(milliseconds: 600),
    this.logoAsset = 'gui/logo',
    this.skipIntro = false,
  });

  final VoidCallback onNewGame;
  final VoidCallback onLoadGame;
  final Function(SaveSlot)? onLoadGameWithSave;
  final VoidCallback? onContinueGame;
  final bool skipMusicDelay;
  final Duration splashDuration;
  final Duration fadeOutDuration;
  final String logoAsset;
  final bool skipIntro;

  @override
  State<SoraNoutaStartupFlow> createState() => _SoraNoutaStartupFlowState();
}

class _SoraNoutaStartupFlowState extends State<SoraNoutaStartupFlow>
    with SingleTickerProviderStateMixin {
  bool _showMainMenu = false;
  late AnimationController _transitionController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();

    _transitionController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _transitionController,
      curve: Curves.easeIn,
    ));

    // 后台初始化流程图分析器
    Future.microtask(() async {
      try {
        final analyzer = StoryFlowchartAnalyzer();
        await analyzer.analyzeScript();
        if (kDebugMode) {
          print('[SoraNoUta] 剧情流程图初始化完成');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[SoraNoUta] 流程图初始化失败: $e');
        }
      }
    });

    // 如果跳过intro，直接显示主菜单
    if (widget.skipIntro) {
      _showMainMenu = true;
      _transitionController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    super.dispose();
  }

  Future<void> _onLogoComplete() async {
    setState(() {
      _showMainMenu = true;
    });
    // 等待一帧确保IndexedStack切换完成
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) {
      _transitionController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 根据状态显示不同页面，确保主菜单只在需要时才初始化
        if (!_showMainMenu)
          _LogoScreen(
            logoAsset: widget.logoAsset,
            splashDuration: widget.splashDuration,
            fadeOutDuration: widget.fadeOutDuration,
            onComplete: _onLogoComplete,
          )
        else
          SoraNoutaMainMenuScreen(
            onNewGame: widget.onNewGame,
            onLoadGame: widget.onLoadGame,
            onLoadGameWithSave: widget.onLoadGameWithSave,
            onContinueGame: widget.onContinueGame,
            skipMusicDelay: widget.skipMusicDelay,
          ),
        // 黑场过渡层
        if (_showMainMenu)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _fadeInAnimation,
              builder: (context, child) {
                final opacity = 1.0 - _fadeInAnimation.value;
                if (opacity <= 0) return const SizedBox.shrink();
                return ColoredBox(
                  color: Colors.black.withOpacity(opacity),
                  child: const SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 独立的Logo展示页面
class _LogoScreen extends StatefulWidget {
  const _LogoScreen({
    required this.logoAsset,
    required this.splashDuration,
    required this.fadeOutDuration,
    required this.onComplete,
  });

  final String logoAsset;
  final Duration splashDuration;
  final Duration fadeOutDuration;
  final VoidCallback onComplete;

  @override
  State<_LogoScreen> createState() => _LogoScreenState();
}

enum _LogoPhase { display, fadeOut }

class _LogoScreenState extends State<_LogoScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _fadeController;
  _LogoPhase _phase = _LogoPhase.display;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: widget.fadeOutDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onComplete();
        }
      });

    // 等待指定时长后开始淡出
    _timer = Timer(widget.splashDuration, _startFadeOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _startFadeOut() {
    if (_phase == _LogoPhase.display && mounted) {
      setState(() => _phase = _LogoPhase.fadeOut);
      _fadeController.forward(from: 0.0);
    }
  }

  void _handleDoubleTap() {
    // 双击跳过：取消定时器，快速完成淡出动画
    _timer?.cancel();
    if (!_hasCompleted && mounted) {
      setState(() => _phase = _LogoPhase.fadeOut);
      _fadeController.duration = const Duration(milliseconds: 200);
      _fadeController.forward(from: _fadeController.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = SettingsManager().currentDarkMode;
    final baseColor = isDarkMode ? Colors.black : Colors.white;

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: Scaffold(
        backgroundColor: baseColor,
        body: AnimatedBuilder(
          animation: _fadeController,
          builder: (context, child) {
            final t = _fadeController.value.clamp(0.0, 1.0);
            double logoOpacity = 1.0;
            double backgroundOpacity = 1.0;

            if (_phase == _LogoPhase.fadeOut) {
              if (t < 0.5) {
                // 先让Logo淡出
                final progress = t / 0.5;
                logoOpacity = 1.0 - progress;
                backgroundOpacity = 1.0;
              } else {
                // Logo已消失，背景也开始淡出
                logoOpacity = 0.0;
                final progress = (t - 0.5) / 0.5;
                backgroundOpacity = 1.0 - progress;
              }
            }

            return ColoredBox(
              color: baseColor.withOpacity(backgroundOpacity),
              child: Center(
                child: logoOpacity > 0
                    ? Opacity(
                        opacity: logoOpacity,
                        child: FractionallySizedBox(
                          widthFactor: 0.8,
                          heightFactor: 0.8,
                          child: isDarkMode
                              ? SmartAssetImage(
                                  assetName: widget.logoAsset,
                                  fit: BoxFit.contain,
                                )
                              : ColorFiltered(
                                  colorFilter: const ColorFilter.matrix(<double>[
                                    -1, 0, 0, 0, 255,
                                    0, -1, 0, 0, 255,
                                    0, 0, -1, 0, 255,
                                    0, 0, 0, 1, 0,
                                  ]),
                                  child: SmartAssetImage(
                                    assetName: widget.logoAsset,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                        ),
                      )
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
