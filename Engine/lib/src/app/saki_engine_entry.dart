import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakiengine/src/config/runtime_project_config.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/core/module_registry.dart';
import 'package:sakiengine/src/core/project_module_loader.dart';
import 'package:sakiengine/src/game/save_load_manager.dart';
import 'package:sakiengine/src/integrations/steam/steamworks_manager.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/binary_serializer.dart';
import 'package:sakiengine/src/utils/debug_logger.dart';
import 'package:sakiengine/src/utils/global_variable_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/utils/transition_prewarming.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';
import 'package:sakiengine/src/widgets/common/black_screen_transition.dart';
import 'package:sakiengine/src/widgets/common/exit_confirmation_dialog.dart';

import '../utils/platform_window_manager_io.dart'
    if (dart.library.html) '../utils/platform_window_manager_web.dart';

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
    PlatformWindowManager.addListener(this);
  }

  @override
  void dispose() {
    PlatformWindowManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    final shouldClose = await _showExitConfirmation();
    if (shouldClose) {
      try {
        await PlatformWindowManager.destroy();
      } catch (_) {
        SystemNavigator.pop();
      }
    }
  }

  Future<bool> _showExitConfirmation() async {
    return ExitConfirmationDialog.showExitConfirmation(context,
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

  Future<void> _continueGame() async {
    try {
      final quickSave = await SaveLoadManager().loadQuickSave();
      if (quickSave != null) {
        _enterGame(saveSlot: quickSave);
      }
    } catch (e) {
      debugPrint('快速读档失败: $e');
    }
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
    return FutureBuilder(
      future: moduleLoader.getCurrentModule(),
      builder: (builderContext, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: ColoredBox(color: Color.fromARGB(0, 0, 0, 0)),
            ),
          );
        }

        final gameModule = snapshot.data!;
        late final Widget currentScreen;

        switch (_currentState) {
          case AppState.mainMenu:
            currentScreen = gameModule.createMainMenuScreen(
              onNewGame: () => _enterGame(),
              onLoadGame: () {},
              onLoadGameWithSave: (saveSlot) => _enterGame(saveSlot: saveSlot),
              onContinueGame: _continueGame,
              skipMusicDelay: _isReturningFromGame,
            );
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
  }
}

Future<void> runSakiEngine({
  String? projectName,
  String? appName,
  String? gamePath,
  int steamAppId = 3536120,
  bool enableSteamworks = true,
  bool initializeGeneratedModules = true,
}) async {
  setupDebugLogger();

  await runZoned(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      configureRuntimeProject(
        projectName: projectName,
        appName: appName,
        gamePath: gamePath,
      );

      if (enableSteamworks) {
        final steamworksManager = SteamworksManager.instance;
        if (steamworksManager.isSupportedPlatform) {
          final steamOptions = SteamworksInitOptions(appId: steamAppId);
          final steamInitialized =
              await steamworksManager.initialize(options: steamOptions);
          debugPrint('Seamworks: 游戏Appid：${steamOptions.appId}');
          if (!steamInitialized && kDebugMode) {
            debugPrint('Steamworks 初始化未成功，可能需要用户先启动 Steam 客户端。');
          }
        }
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }

      MediaKit.ensureInitialized();
      JustAudioMediaKit.ensureInitialized(
        android: true,
        iOS: true,
        macOS: true,
        windows: true,
        linux: true,
      );

      if (!kIsWeb) {
        await PlatformWindowManager.ensureInitialized();
        await PlatformWindowManager.setPreventClose(true);
        await PlatformWindowManager.maximize();
      }

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        await hotKeyManager.unregisterAll();
      }

      await SakiEngineConfig().loadConfig();
      await SettingsManager().init();
      await LocalizationManager().init();
      await UISoundManager().initialize();

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

      SakiEngineConfig().updateThemeForDarkMode();

      if (initializeGeneratedModules) {
        initializeProjectModules();
      }

      runApp(const SakiEngineApp());
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        DebugLogger().addLog(line);
        parent.print(zone, line);
      },
    ),
  );
}

class SakiEngineApp extends StatefulWidget {
  const SakiEngineApp({super.key});

  @override
  State<SakiEngineApp> createState() => _SakiEngineAppState();
}

class _SakiEngineAppState extends State<SakiEngineApp> {
  String? _lastSetTitle;
  late final Listenable _settingsAppListenable;

  @override
  void initState() {
    super.initState();
    _settingsAppListenable = Listenable.merge([
      SettingsManager(),
      LocalizationManager(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final localization = LocalizationManager();

    return AnimatedBuilder(
      animation: _settingsAppListenable,
      builder: (context, child) {
        return FutureBuilder(
          future: moduleLoader.getCurrentModule(),
          builder: (builderContext, snapshot) {
            if (!snapshot.hasData) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: localization.currentLocale,
                supportedLocales: localization.supportedLocales,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Scaffold(
                  body: Center(
                    child: ColoredBox(color: Colors.black),
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

                if (titleSnapshot.hasData && _lastSetTitle != appTitle) {
                  _lastSetTitle = appTitle;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (kIsWeb) {
                      Timer(const Duration(milliseconds: 500), () {
                        PlatformWindowManager.setTitle(appTitle);
                      });
                    } else {
                      PlatformWindowManager.setTitle(appTitle);
                    }
                  });
                }

                return MaterialApp(
                  title: appTitle,
                  debugShowCheckedModeBanner: false,
                  locale: localization.currentLocale,
                  supportedLocales: localization.supportedLocales,
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
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

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOut,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startMaskAndPrewarm();
    });
  }

  Future<void> _startMaskAndPrewarm() async {
    if (!mounted) {
      return;
    }

    try {
      final delay = kIsWeb ? 1500 : 1000;
      await Future.delayed(Duration(milliseconds: delay));
      if (mounted) {
        await TransitionPrewarmingManager.instance.prewarm(context);
      }
      if (mounted) {
        _prewarmingComplete = true;
        _fadeController.forward();
      }
    } catch (_) {
      if (mounted) {
        _prewarmingComplete = true;
        _fadeController.forward();
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
        const GameContainer(),
        AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
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
