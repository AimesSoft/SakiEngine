import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/config/config_models.dart';
import 'package:sakiengine/src/core/module_registry.dart';
import 'package:sakiengine/src/core/project_module_loader.dart';
import 'package:sakiengine/src/utils/debug_logger.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/global_variable_manager.dart';
import 'package:sakiengine/src/widgets/common/black_screen_transition.dart';
import 'package:sakiengine/src/widgets/common/exit_confirmation_dialog.dart';
import 'package:sakiengine/src/utils/transition_prewarming.dart';

enum AppState { mainMenu, inGame }

class GameContainer extends StatefulWidget {
  const GameContainer({super.key});

  @override
  State<GameContainer> createState() => _GameContainerState();
}

class _GameContainerState extends State<GameContainer> with WindowListener {
  AppState _currentState = AppState.mainMenu;
  SaveSlot? _saveSlotToLoad;
  bool _isReturningFromGame = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    bool shouldClose = await _showExitConfirmation();
    if (shouldClose) {
      // 修复Windows关闭游戏的bug：直接销毁窗口，避免重复触发onWindowClose
      try {
        await windowManager.destroy();
      } catch (e) {
        // 如果销毁失败，使用系统退出
        SystemNavigator.pop();
      }
    }
  }

  Future<bool> _showExitConfirmation() async {
    return await ExitConfirmationDialog.showExitConfirmation(context,
        hasProgress: true);
  }

  void _enterGame({SaveSlot? saveSlot}) {
    TransitionOverlayManager.instance.transition(
      context: context,
      onMidTransition: () {
        setState(() {
          _currentState = AppState.inGame;
          _saveSlotToLoad = saveSlot;
          _isReturningFromGame = false;
        });
      },
    );
  }

  void _returnToMainMenu() {
    TransitionOverlayManager.instance.transition(
      context: context,
      onMidTransition: () {
        setState(() {
          _currentState = AppState.mainMenu;
          _saveSlotToLoad = null;
          _isReturningFromGame = true;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = SettingsManager().currentDarkMode;
    
    print('[GameContainer] 全局反色模式: $isDarkMode');
    
    Widget gameContent = FutureBuilder(
      future: moduleLoader.getCurrentModule(),
      builder: (builderContext, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            body: Center(
                child: Container(color: const Color.fromARGB(0, 0, 0, 0))),
          );
        }

        final gameModule = snapshot.data!;

        Widget currentScreen;
        switch (_currentState) {
          case AppState.mainMenu:
            currentScreen = gameModule.createMainMenuScreen(
              onNewGame: () => _enterGame(),
              onLoadGame: () {
                // 这个回调现在只是个占位符，实际的load逻辑在MainMenuScreen内部处理
              },
              onLoadGameWithSave: (saveSlot) => _enterGame(saveSlot: saveSlot),
              skipMusicDelay: _isReturningFromGame,
            );
            // 重置标记，确保下次进入主菜单时正常延迟
            if (_isReturningFromGame) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _isReturningFromGame = false;
                });
              });
            }
            break;
          case AppState.inGame:
            currentScreen = gameModule.createGamePlayScreen(
              key: ValueKey(_saveSlotToLoad?.id ?? 'new_game'),
              saveSlotToLoad: _saveSlotToLoad,
              onReturnToMenu: _returnToMainMenu,
              onLoadGame: (saveSlot) => _enterGame(saveSlot: saveSlot),
            );
            break;
        }

        return currentScreen;
      },
    );

    // 在夜间模式下应用全局反色滤镜
    if (isDarkMode) {
      gameContent = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1.0, 0, 0, 0, 255,
          0, -1.0, 0, 0, 255,
          0, 0, -1.0, 0, 255,
          0, 0, 0, 1.0, 0,
        ]),
        child: gameContent,
      );
    }

    return gameContent;
  }
}

void main() async {
  // 设置调试日志收集器
  setupDebugLogger();

  // 在Zone中运行应用，捕获所有print输出
  runZoned(() async {
    // 初始化Flutter绑定
    WidgetsFlutterBinding.ensureInitialized();

    // 注册fvp以支持所有平台的视频播放，特别是Windows
    fvp.registerWith(options: {
      'global': {
        'log': 'debug', // off, error, warning, info, debug, all(default)
      }
    });

    // 初始化窗口管理器
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    
    // 设置窗口默认最大化
    await windowManager.maximize();

    // 初始化系统热键，清理之前的注册（用于热重载）
    await hotKeyManager.unregisterAll();

    // 加载引擎配置
    await SakiEngineConfig().loadConfig();

    // 初始化设置管理器
    await SettingsManager().init();

    // 初始化全局变量管理器并打印变量状态
    await GlobalVariableManager().init();
    final allVars = GlobalVariableManager().getAllVariables();
    print('=== 应用启动 - 全局变量状态 ===');
    if (allVars.isEmpty) {
      print('暂无全局变量');
    } else {
      allVars.forEach((name, value) {
        print('全局变量: $name = $value');
      });
    }
    print('=== 全局变量状态结束 ===');

    // 应用深色模式设置
    SakiEngineConfig().updateThemeForDarkMode();

    // 初始化项目模块
    initializeProjectModules();

    // 启动应用
    runApp(const SakiEngineApp());
  }, zoneSpecification: ZoneSpecification(
    print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
      // 记录到我们的日志系统
      DebugLogger().addLog(line);
      // 保持正常的控制台输出
      parent.print(zone, line);
    },
  ));
}

class SakiEngineApp extends StatefulWidget {
  const SakiEngineApp({super.key});

  @override
  State<SakiEngineApp> createState() => _SakiEngineAppState();
}

class _SakiEngineAppState extends State<SakiEngineApp> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsManager(),
      builder: (context, child) {
        return FutureBuilder(
          future: moduleLoader.getCurrentModule(),
          builder: (builderContext, snapshot) {
            if (!snapshot.hasData) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  body: Center(
                    child: Container(color: Colors.black),
                  ),
                ),
              );
            }

            final gameModule = snapshot.data!;

            return FutureBuilder<String>(
              future: gameModule.getAppTitle(),
              builder: (context, titleSnapshot) {
                final appTitle = titleSnapshot.data ?? 'SakiEngine';
                final customTheme = gameModule.createTheme();

                // 设置窗口标题
                if (titleSnapshot.hasData) {
                  windowManager.setTitle(appTitle);
                }

                return MaterialApp(
                  title: appTitle,
                  debugShowCheckedModeBanner: false,
                  theme: customTheme ??
                      ThemeData(
                        primarySwatch: Colors.blue,
                        fontFamily: 'SourceHanSansCN',
                      ),
                  home: const StartupMaskWrapper(),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 启动遮罩包装器
/// 在应用启动时立即显示黑屏遮罩，遮盖界面闪烁
class StartupMaskWrapper extends StatefulWidget {
  const StartupMaskWrapper({super.key});

  @override
  State<StartupMaskWrapper> createState() => _StartupMaskWrapperState();
}

class _StartupMaskWrapperState extends State<StartupMaskWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _prewarmingComplete = false;

  @override
  void initState() {
    super.initState();

    // 创建淡出动画控制器
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    // 启动遮罩和预热
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMaskAndPrewarm();
    });
  }

  Future<void> _startMaskAndPrewarm() async {
    if (mounted) {
      try {
        // 等待1秒保持黑屏，然后预热
        await Future.delayed(const Duration(milliseconds: 1000));

        // 在后台预热
        await TransitionPrewarmingManager.instance.prewarm(context);

        if (mounted) {
          _prewarmingComplete = true;
          // 开始淡出动画
          _fadeController.forward();
        }
        print('[StartupMask] 启动遮罩和预热完成，开始淡出');
      } catch (e) {
        print('[StartupMask] 启动遮罩和预热失败: $e');
        // 即使失败也要开始淡出，避免永远黑屏
        if (mounted) {
          _prewarmingComplete = true;
          _fadeController.forward();
        }
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 实际的游戏内容
        const GameContainer(),

        // 启动遮罩 - 使用动画淡出
        AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            // 如果预热还未完成，或者动画值大于0，则显示遮罩
            if (!_prewarmingComplete || _fadeAnimation.value > 0) {
              return Material(
                color: Colors.black.withOpacity(
                    _prewarmingComplete ? _fadeAnimation.value : 1.0),
                child: const SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
