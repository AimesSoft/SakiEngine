import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum RunBuildMode { debug, showcase, profile, release }

enum BuildMode { release, showcase }

class LauncherUiSettings {
  final ThemeMode themeMode;
  final Color seedColor;
  final RunBuildMode defaultRunBuildMode;

  const LauncherUiSettings({
    required this.themeMode,
    required this.seedColor,
    required this.defaultRunBuildMode,
  });

  factory LauncherUiSettings.defaults() => const LauncherUiSettings(
    themeMode: ThemeMode.system,
    seedColor: Color(0xFF17685A),
    defaultRunBuildMode: RunBuildMode.debug,
  );

  LauncherUiSettings copyWith({
    ThemeMode? themeMode,
    Color? seedColor,
    RunBuildMode? defaultRunBuildMode,
  }) {
    return LauncherUiSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      defaultRunBuildMode: defaultRunBuildMode ?? this.defaultRunBuildMode,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'theme_mode': _themeModeToString(themeMode),
      'seed_color': seedColor.toARGB32(),
      'run_build_mode': defaultRunBuildMode.name,
    };
  }

  static LauncherUiSettings fromJson(Map<String, dynamic> json) {
    final defaults = LauncherUiSettings.defaults();
    final mode = _themeModeFromString(json['theme_mode']?.toString());
    final colorValue = json['seed_color'];
    final runModeName = json['run_build_mode']?.toString();
    RunBuildMode? runMode;
    for (final modeItem in RunBuildMode.values) {
      if (modeItem.name == runModeName) {
        runMode = modeItem;
        break;
      }
    }

    return LauncherUiSettings(
      themeMode: mode ?? defaults.themeMode,
      seedColor: colorValue is int ? Color(colorValue) : defaults.seedColor,
      defaultRunBuildMode: runMode ?? defaults.defaultRunBuildMode,
    );
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  static ThemeMode? _themeModeFromString(String? value) {
    switch (value) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }
}

final ValueNotifier<LauncherUiSettings> _settingsNotifier =
    ValueNotifier<LauncherUiSettings>(LauncherUiSettings.defaults());

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _settingsNotifier.value = await _loadLauncherUiSettings();
  runApp(SakiLauncherApp(settingsNotifier: _settingsNotifier));
}

class SakiLauncherApp extends StatelessWidget {
  const SakiLauncherApp({required this.settingsNotifier, super.key});

  final ValueNotifier<LauncherUiSettings> settingsNotifier;

  ThemeData _buildTheme({
    required Brightness brightness,
    required Color seedColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      fontFamily: 'Noto Sans',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LauncherUiSettings>(
      valueListenable: settingsNotifier,
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'SakiEngine 开发启动器',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: _buildTheme(
            brightness: Brightness.light,
            seedColor: settings.seedColor,
          ),
          darkTheme: _buildTheme(
            brightness: Brightness.dark,
            seedColor: settings.seedColor,
          ),
          home: LauncherPage(settingsNotifier: settingsNotifier),
        );
      },
    );
  }
}

class LauncherPage extends StatefulWidget {
  const LauncherPage({required this.settingsNotifier, super.key});

  final ValueNotifier<LauncherUiSettings> settingsNotifier;

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

enum RunLaunchMode { embedded, systemTerminal }

class _LauncherPageState extends State<LauncherPage> {
  static const List<String> _allBuildTargets = <String>[
    'macos',
    'linux',
    'windows',
    'android',
    'ios',
    'web',
  ];

  static const String _defaultGeneratedLoader = '''
import 'package:sakiengine/src/sks_compiler/compiled_sks_bundle.dart';

CompiledSksBundle? loadGeneratedCompiledSksBundle() {
  return null;
}
''';

  static const List<_SeedChoice> _seedChoices = <_SeedChoice>[
    _SeedChoice('引擎青绿', Color(0xFF17685A)),
    _SeedChoice('深海蓝', Color(0xFF0E5A8A)),
    _SeedChoice('琥珀橙', Color(0xFF9A5A00)),
    _SeedChoice('石墨灰', Color(0xFF455A64)),
    _SeedChoice('绯红', Color(0xFF9F2A3F)),
  ];

  late final Directory _repoRoot;

  final List<String> _gameProjects = <String>[];
  final List<String> _logs = <String>[];
  final ScrollController _logScrollController = ScrollController();

  String? _selectedGame;
  String? _defaultGame;
  String _runTarget = 'web';
  RunLaunchMode _runMode = RunLaunchMode.embedded;
  RunBuildMode _runBuildMode = RunBuildMode.debug;
  String _buildTarget = 'web';
  BuildMode _buildMode = BuildMode.release;
  bool _busy = false;
  bool _isRunTask = false;
  bool _pendingSafeRestart = false;
  Process? _activeProcess;

  @override
  void initState() {
    super.initState();
    _repoRoot = _discoverRepoRoot();
    _runTarget = _recommendedRunTarget();
    _buildTarget = _recommendedBuildTarget();
    _runBuildMode = widget.settingsNotifier.value.defaultRunBuildMode;
    if (!_buildTargets.contains(_buildTarget)) {
      _buildTarget = _buildTargets.first;
    }
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _activeProcess?.kill();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    _appendLog('仓库根目录: ${_repoRoot.path}');
    await _checkToolchain();
    await _refreshProjects();
  }

  Directory _discoverRepoRoot() {
    const override = String.fromEnvironment('SAKI_REPO_ROOT');
    if (override.trim().isNotEmpty) {
      final overrideDir = Directory(override).absolute;
      if (_isRepoRoot(overrideDir)) {
        return overrideDir;
      }
    }

    final starts = <Directory>[
      Directory.current.absolute,
      File(Platform.resolvedExecutable).parent.absolute,
    ];
    final seen = <String>{};
    for (final start in starts) {
      final key = _normalizePath(start.path);
      if (!seen.add(key)) {
        continue;
      }
      final found = _findRepoRootFrom(start);
      if (found != null) {
        return found;
      }
    }

    return Directory.current.absolute;
  }

  Directory? _findRepoRootFrom(Directory start) {
    var current = start.absolute;
    while (true) {
      if (_isRepoRoot(current)) {
        return current;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
  }

  bool _isRepoRoot(Directory dir) {
    final hasEngine = Directory(_joinPath(dir.path, 'Engine')).existsSync();
    final hasGame = Directory(_joinPath(dir.path, 'Game')).existsSync();
    return hasEngine && hasGame;
  }

  String _recommendedRunTarget() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'web';
  }

  String _recommendedBuildTarget() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return _buildTargets.first;
  }

  List<String> get _runTargets {
    if (Platform.isMacOS) return <String>['macos', 'web'];
    if (Platform.isLinux) return <String>['linux', 'web'];
    if (Platform.isWindows) return <String>['windows', 'web'];
    return <String>['web'];
  }

  List<String> get _buildTargets {
    if (Platform.isMacOS) return <String>['macos', 'ios', 'android', 'web'];
    if (Platform.isLinux) return <String>['linux', 'android', 'web'];
    if (Platform.isWindows) return <String>['windows', 'android', 'web'];
    return _allBuildTargets;
  }

  String _runModeLabel(RunLaunchMode mode) {
    switch (mode) {
      case RunLaunchMode.embedded:
        return '内置控制台';
      case RunLaunchMode.systemTerminal:
        return '系统终端';
    }
  }

  String _runBuildModeLabel(RunBuildMode mode) {
    switch (mode) {
      case RunBuildMode.debug:
        return 'Debug';
      case RunBuildMode.showcase:
        return '演出模式';
      case RunBuildMode.profile:
        return 'Profile';
      case RunBuildMode.release:
        return 'Release';
    }
  }

  List<String> _runBuildModeArgs(RunBuildMode mode) {
    switch (mode) {
      case RunBuildMode.debug:
        return const <String>[];
      case RunBuildMode.showcase:
        return const <String>['--release'];
      case RunBuildMode.profile:
        return const <String>['--profile'];
      case RunBuildMode.release:
        return const <String>['--release'];
    }
  }

  String _runBuildModeFlag(RunBuildMode mode) {
    switch (mode) {
      case RunBuildMode.debug:
        return '';
      case RunBuildMode.showcase:
        return '--release';
      case RunBuildMode.profile:
        return '--profile';
      case RunBuildMode.release:
        return '--release';
    }
  }

  bool _isShowcaseMode(RunBuildMode mode) {
    return mode == RunBuildMode.showcase;
  }

  bool _shouldUseReleaseAssetPipeline(RunBuildMode mode) {
    return mode == RunBuildMode.profile || mode == RunBuildMode.release;
  }

  String _buildModeLabel(BuildMode mode) {
    switch (mode) {
      case BuildMode.release:
        return '发布模式';
      case BuildMode.showcase:
        return '演出模式';
    }
  }

  List<String> _buildRunDefines({
    required String game,
    required String gameDir,
    required RunBuildMode mode,
  }) {
    final defines = <String>['--dart-define=SAKI_GAME_PATH=$gameDir'];
    if (_isShowcaseMode(mode)) {
      defines.add('--dart-define=SAKI_SHOW_MODE=true');
      defines.add('--dart-define=SAKI_SHOWCASE_GAME_DIR=Game/$game');
    }
    return defines;
  }

  Future<void> _checkToolchain() async {
    final flutterReady = await _isCommandAvailable('flutter');
    if (flutterReady) {
      _appendLog('环境检测: flutter 可用');
    } else {
      _appendLog('环境检测警告: 未检测到 flutter，运行/构建会失败');
    }

    final nodeReady = await _isCommandAvailable('node');
    if (nodeReady) {
      _appendLog('环境检测: node 可用');
    } else {
      _appendLog('环境检测警告: 未检测到 node，项目准备与创建会失败');
    }
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  Future<void> _saveSettings(LauncherUiSettings settings) async {
    widget.settingsNotifier.value = settings;
    await _saveLauncherUiSettings(settings);
  }

  Future<void> _showSettingsDialog() async {
    final current = widget.settingsNotifier.value;
    var selectedThemeMode = current.themeMode;
    var selectedSeedColor = current.seedColor;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('启动器设置'),
              content: SizedBox(
                width: 430,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    DropdownButtonFormField<ThemeMode>(
                      initialValue: selectedThemeMode,
                      decoration: const InputDecoration(
                        labelText: '主题模式',
                        border: OutlineInputBorder(),
                      ),
                      items: ThemeMode.values
                          .map(
                            (mode) => DropdownMenuItem<ThemeMode>(
                              value: mode,
                              child: Text(_themeModeLabel(mode)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedThemeMode = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '主题色调',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _seedChoices.map((choice) {
                        final selected =
                            choice.color.toARGB32() ==
                            selectedSeedColor.toARGB32();
                        return ChoiceChip(
                          label: Text(choice.label),
                          selected: selected,
                          selectedColor: choice.color.withValues(alpha: 0.22),
                          side: BorderSide(
                            color: selected
                                ? choice.color
                                : Theme.of(context).dividerColor,
                          ),
                          avatar: CircleAvatar(
                            radius: 8,
                            backgroundColor: choice.color,
                          ),
                          onSelected: (_) {
                            setDialogState(() {
                              selectedSeedColor = choice.color;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final next = current.copyWith(
                      themeMode: selectedThemeMode,
                      seedColor: selectedSeedColor,
                    );
                    await _saveSettings(next);
                    if (!mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    final hex = (selectedSeedColor.toARGB32() & 0xFFFFFF)
                        .toRadixString(16)
                        .padLeft(6, '0')
                        .toUpperCase();
                    _appendLog(
                      '设置已更新: 主题=${_themeModeLabel(selectedThemeMode)}, 色调=#$hex',
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _refreshProjects() async {
    final gameDir = Directory(_joinPath(_repoRoot.path, 'Game'));
    final defaultGameFile = File(_joinPath(_repoRoot.path, 'default_game.txt'));
    final projects = <String>[];

    if (!gameDir.existsSync()) {
      _appendLog('未找到 Game 目录: ${gameDir.path}');
    }

    if (gameDir.existsSync()) {
      final candidates =
          gameDir
              .listSync(followLinks: false)
              .whereType<Directory>()
              .map((d) => d.path)
              .toList()
            ..sort();

      for (final path in candidates) {
        final pubspec = File(_joinPath(path, 'pubspec.yaml'));
        if (pubspec.existsSync()) {
          projects.add(_basename(path));
        }
      }
    }

    String? defaultGame;
    if (defaultGameFile.existsSync()) {
      defaultGame = defaultGameFile.readAsStringSync().trim();
      if (defaultGame.isEmpty) {
        defaultGame = null;
      }
    }

    if (mounted) {
      setState(() {
        _gameProjects
          ..clear()
          ..addAll(projects);
        _defaultGame = defaultGame;

        if (_selectedGame == null || !_gameProjects.contains(_selectedGame)) {
          if (_defaultGame != null && _gameProjects.contains(_defaultGame)) {
            _selectedGame = _defaultGame;
          } else {
            _selectedGame = _gameProjects.isEmpty ? null : _gameProjects.first;
          }
        }
      });
    }

    _appendLog('已加载 ${projects.length} 个游戏项目');
    if (projects.isEmpty) {
      _appendLog('提示: 仅识别包含 pubspec.yaml 的 Game/<项目> 目录');
    }
  }

  Future<void> _setDefaultGame() async {
    final game = _selectedGame;
    if (game == null) {
      return;
    }

    final file = File(_joinPath(_repoRoot.path, 'default_game.txt'));
    await file.writeAsString('$game\n');
    if (mounted) {
      setState(() {
        _defaultGame = game;
      });
    }
    _appendLog('默认项目已更新为: $game');
  }

  Future<int> _runNodeBridge(List<String> bridgeArgs) {
    return _runCommand(
      executable: 'node',
      arguments: <String>['scripts/launcher-bridge.js', ...bridgeArgs],
      workingDirectory: _repoRoot.path,
    );
  }

  Future<void> _prepareProjectForExecution(
    String game, {
    required bool generateIcons,
  }) async {
    final args = <String>['prepare-project', '--game', game];
    if (generateIcons) {
      args.add('--generate-icons');
    }

    final code = await _runNodeBridge(args);
    if (code != 0) {
      throw _TaskFailure('准备项目失败（应用身份/图标同步）');
    }
  }

  Future<void> _showCreateProjectDialog() async {
    if (_busy) {
      return;
    }

    final nameController = TextEditingController();
    final bundleController = TextEditingController(
      text: 'com.aimessoft.mygame',
    );
    final colorController = TextEditingController(text: '137B8B');
    var setDefault = true;
    var submitting = false;
    String? message;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('创建新项目'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: nameController,
                      enabled: !submitting,
                      decoration: const InputDecoration(
                        labelText: '项目名称',
                        hintText: 'MyGame',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bundleController,
                      enabled: !submitting,
                      decoration: const InputDecoration(
                        labelText: 'Bundle ID',
                        hintText: 'com.company.game',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: colorController,
                      enabled: !submitting,
                      decoration: const InputDecoration(
                        labelText: '主色调 (Hex)',
                        hintText: '137B8B',
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: setDefault,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      enabled: !submitting,
                      title: const Text('创建后设为默认项目'),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          setDefault = value;
                        });
                      },
                    ),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final bundle = bundleController.text.trim();
                          var color = colorController.text.trim();
                          if (color.startsWith('#')) {
                            color = color.substring(1);
                          }

                          final nameOk = RegExp(
                            r'^[a-zA-Z0-9_-]+$',
                          ).hasMatch(name);
                          final bundleOk = RegExp(
                            r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){2,}$',
                          ).hasMatch(bundle);
                          final colorOk = RegExp(
                            r'^[0-9A-Fa-f]{6}$',
                          ).hasMatch(color);

                          if (!nameOk || !bundleOk || !colorOk) {
                            setDialogState(() {
                              message = '请输入合法值：项目名、Bundle ID、6位十六进制颜色';
                            });
                            return;
                          }

                          setDialogState(() {
                            submitting = true;
                            message = null;
                          });

                          final success = await _createProjectNonInteractive(
                            name: name,
                            bundleId: bundle,
                            color: color,
                            setDefault: setDefault,
                          );
                          if (!mounted) {
                            return;
                          }

                          if (success) {
                            Navigator.of(dialogContext).pop();
                          } else {
                            setDialogState(() {
                              submitting = false;
                              message = '创建失败，请查看任务日志';
                            });
                          }
                        },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _createProjectNonInteractive({
    required String name,
    required String bundleId,
    required String color,
    required bool setDefault,
  }) async {
    if (_busy) {
      return false;
    }

    setState(() {
      _busy = true;
      _isRunTask = false;
    });
    _appendLog('开始创建新项目: $name');

    try {
      final args = <String>[
        'create-project',
        '--name',
        name,
        '--bundle',
        bundleId,
        '--color',
        color,
      ];
      if (setDefault) {
        args.add('--set-default');
      }

      final code = await _runNodeBridge(args);
      if (code != 0) {
        _appendLog('创建项目失败: $name');
        return false;
      }

      await _refreshProjects();
      if (mounted) {
        setState(() {
          _selectedGame = name;
        });
      }
      _appendLog('创建项目成功: $name');
      return true;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activeProcess = null;
        });
      }
    }
  }

  Future<void> _runSelectedGame() async {
    final game = _selectedGame;
    if (game == null || _busy) {
      return;
    }

    final gameDir = _joinPath(_joinPath(_repoRoot.path, 'Game'), game);
    final runDevice = _runTarget == 'web' ? 'chrome' : _runTarget;
    final runModeArgs = _runBuildModeArgs(_runBuildMode);
    final runDefineArgs = _buildRunDefines(
      game: game,
      gameDir: gameDir,
      mode: _runBuildMode,
    );

    setState(() {
      _busy = true;
      _isRunTask = true;
    });
    _appendLog(
      '开始运行游戏: $game (target=$runDevice, launch=${_runModeLabel(_runMode)}, build=${_runBuildModeLabel(_runBuildMode)})',
    );

    try {
      if (_runMode == RunLaunchMode.systemTerminal) {
        if (_shouldUseReleaseAssetPipeline(_runBuildMode)) {
          _appendLog('系统终端模式暂不支持 Profile/Release 发布运行管线，请切换到内置控制台运行');
          return;
        }
        final launched = await _launchRunInSystemTerminal(
          game: game,
          gameDir: gameDir,
          runDevice: runDevice,
          runBuildMode: _runBuildMode,
        );
        if (launched) {
          _appendLog('已在系统终端启动运行任务，可在终端中使用 r/R/q');
        } else {
          _appendLog('启动失败: 未找到可用系统终端');
        }
        return;
      }

      int runCode;
      if (!_shouldUseReleaseAssetPipeline(_runBuildMode)) {
        await _prepareProjectForExecution(game, generateIcons: false);

        final pubGetCode = await _runCommand(
          executable: 'flutter',
          arguments: const <String>['pub', 'get'],
          workingDirectory: gameDir,
        );
        if (pubGetCode != 0) {
          _appendLog('运行中止: flutter pub get 失败');
          return;
        }

        await _prepareProjectForExecution(game, generateIcons: true);

        runCode = await _runCommand(
          executable: 'flutter',
          arguments: <String>[
            'run',
            ...runModeArgs,
            '-d',
            runDevice,
            ...runDefineArgs,
          ],
          workingDirectory: gameDir,
        );
      } else {
        runCode = await _runWithReleaseAssetPipeline(
          game: game,
          gameDir: gameDir,
          runDevice: runDevice,
          runModeArgs: runModeArgs,
          runDefineArgs: runDefineArgs,
        );
      }
      if (runCode != 0) {
        _appendLog('运行中止: flutter run 失败');
      }
    } on _TaskFailure catch (e) {
      _appendLog('运行失败: ${e.message}');
    } catch (e) {
      _appendLog('运行异常: $e');
    } finally {
      final shouldSafeRestart = _pendingSafeRestart;
      _pendingSafeRestart = false;
      if (mounted) {
        setState(() {
          _busy = false;
          _isRunTask = false;
          _activeProcess = null;
        });
      }
      _appendLog('运行任务结束');
      if (shouldSafeRestart && mounted) {
        _appendLog('开始安全重启运行任务...');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        unawaited(_runSelectedGame());
      }
    }
  }

  Future<int> _runWithReleaseAssetPipeline({
    required String game,
    required String gameDir,
    required String runDevice,
    required List<String> runModeArgs,
    required List<String> runDefineArgs,
  }) async {
    final gameDirectory = Directory(gameDir);
    final gamePubspec = File(_joinPath(gameDir, 'pubspec.yaml'));
    final cacheDir = Directory(_joinPath(gameDir, '.saki_cache'));
    final cacheBundle = File(
      _joinPath(cacheDir.path, 'compiled_sks_bundle.g.dart'),
    );
    final engineLoader = File(
      _joinPath(
        _repoRoot.path,
        'Engine/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart',
      ),
    );

    if (!gameDirectory.existsSync() || !gamePubspec.existsSync()) {
      throw _TaskFailure('运行失败: 无效项目目录 $game');
    }

    cacheDir.createSync(recursive: true);

    final originalPubspec = await gamePubspec.readAsString();
    final originalEngineLoader = engineLoader.existsSync()
        ? await engineLoader.readAsString()
        : _defaultGeneratedLoader;

    _appendLog('非 Debug 运行启用发布资源管线（与发布构建一致）');

    try {
      await _prepareProjectForExecution(game, generateIcons: false);

      final firstPubGet = await _runCommand(
        executable: 'flutter',
        arguments: const <String>['pub', 'get'],
        workingDirectory: gameDir,
      );
      if (firstPubGet != 0) {
        throw _TaskFailure('flutter pub get 失败');
      }

      final compileCode = await _runCommand(
        executable: 'flutter',
        arguments: <String>[
          'pub',
          'run',
          '../../Engine/tool/sks_compiler.dart',
          '--game-dir',
          gameDir,
          '--output',
          cacheBundle.path,
          '--game-name',
          game,
        ],
        workingDirectory: gameDir,
      );
      if (compileCode != 0 || !cacheBundle.existsSync()) {
        throw _TaskFailure('.sks 预编译失败');
      }

      await cacheBundle.copy(engineLoader.path);
      final summary = await _prepareReleasePubspec(
        gameDir: gameDirectory,
        pubspecFile: gamePubspec,
      );
      _appendLog(
        '发布运行资源清单已生成: ${summary.totalAssets} 项，图片/视频 ${summary.mediaAssets} 项',
      );

      final secondPubGet = await _runCommand(
        executable: 'flutter',
        arguments: const <String>['pub', 'get'],
        workingDirectory: gameDir,
      );
      if (secondPubGet != 0) {
        throw _TaskFailure('更新发布资源后 pub get 失败');
      }

      await _prepareProjectForExecution(game, generateIcons: true);

      return await _runCommand(
        executable: 'flutter',
        arguments: <String>[
          'run',
          ...runModeArgs,
          '-d',
          runDevice,
          ...runDefineArgs,
        ],
        workingDirectory: gameDir,
      );
    } finally {
      await gamePubspec.writeAsString(originalPubspec);
      await engineLoader.writeAsString(originalEngineLoader);
      _appendLog('已恢复运行前临时修改（pubspec + 编译入口）');
    }
  }

  Future<void> _buildSelectedGame() async {
    final game = _selectedGame;
    if (game == null || _busy) {
      return;
    }
    if (!_buildTargets.contains(_buildTarget)) {
      _appendLog('构建失败: 当前主机不支持目标平台 $_buildTarget');
      return;
    }

    setState(() {
      _busy = true;
      _isRunTask = false;
    });

    try {
      await _runBuildPipeline(game, _buildTarget);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activeProcess = null;
        });
      }
    }
  }

  Future<void> _runBuildPipeline(String game, String platform) async {
    final gameDir = Directory(
      _joinPath(_joinPath(_repoRoot.path, 'Game'), game),
    );
    final gamePubspec = File(_joinPath(gameDir.path, 'pubspec.yaml'));
    final cacheDir = Directory(_joinPath(gameDir.path, '.saki_cache'));
    final cacheBundle = File(
      _joinPath(cacheDir.path, 'compiled_sks_bundle.g.dart'),
    );
    final engineLoader = File(
      _joinPath(
        _repoRoot.path,
        'Engine/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart',
      ),
    );

    if (!gameDir.existsSync() || !gamePubspec.existsSync()) {
      _appendLog('构建失败: 无效项目目录 $game');
      return;
    }

    cacheDir.createSync(recursive: true);

    final originalPubspec = await gamePubspec.readAsString();
    final originalEngineLoader = engineLoader.existsSync()
        ? await engineLoader.readAsString()
        : _defaultGeneratedLoader;

    _appendLog(
      '开始构建: $game -> $platform (mode=${_buildModeLabel(_buildMode)})',
    );

    try {
      await _prepareProjectForExecution(game, generateIcons: false);

      final firstPubGet = await _runCommand(
        executable: 'flutter',
        arguments: const <String>['pub', 'get'],
        workingDirectory: gameDir.path,
      );
      if (firstPubGet != 0) {
        throw _TaskFailure('flutter pub get 失败');
      }

      final useReleaseAssetPipeline = _buildMode == BuildMode.release;
      if (useReleaseAssetPipeline) {
        final compileCode = await _runCommand(
          executable: 'flutter',
          arguments: <String>[
            'pub',
            'run',
            '../../Engine/tool/sks_compiler.dart',
            '--game-dir',
            gameDir.path,
            '--output',
            cacheBundle.path,
            '--game-name',
            game,
          ],
          workingDirectory: gameDir.path,
        );
        if (compileCode != 0 || !cacheBundle.existsSync()) {
          throw _TaskFailure('.sks 预编译失败');
        }

        await cacheBundle.copy(engineLoader.path);
        final summary = await _prepareReleasePubspec(
          gameDir: gameDir,
          pubspecFile: gamePubspec,
        );
        _appendLog(
          '发布资源清单已生成: ${summary.totalAssets} 项，图片/视频 ${summary.mediaAssets} 项',
        );

        final secondPubGet = await _runCommand(
          executable: 'flutter',
          arguments: const <String>['pub', 'get'],
          workingDirectory: gameDir.path,
        );
        if (secondPubGet != 0) {
          throw _TaskFailure('更新发布资源后 pub get 失败');
        }
      } else {
        _appendLog('演出模式构建: 跳过 .sks 预编译与发布资源裁剪，保留脚本直读能力');
      }

      await _prepareProjectForExecution(game, generateIcons: true);

      if (platform == 'ios') {
        final iosDir = Directory(_joinPath(gameDir.path, 'ios'));
        if (!iosDir.existsSync()) {
          throw _TaskFailure('iOS 平台目录不存在: ${iosDir.path}');
        }
        final podCode = await _runCommand(
          executable: 'pod',
          arguments: const <String>['install'],
          workingDirectory: iosDir.path,
        );
        if (podCode != 0) {
          throw _TaskFailure('pod install 失败');
        }
      }

      final buildArgs = _buildArgsFor(platform, _buildMode, game);
      final buildCode = await _runCommand(
        executable: 'flutter',
        arguments: buildArgs,
        workingDirectory: gameDir.path,
      );

      if (buildCode != 0) {
        throw _TaskFailure('flutter build 失败');
      }

      final outputDir = _resolveBuildOutputDirectory(gameDir, platform);
      if (_buildMode == BuildMode.showcase &&
          (platform == 'macos' ||
              platform == 'windows' ||
              platform == 'linux')) {
        await _stageShowcaseGameDirectory(
          gameDir: gameDir,
          outputDir: outputDir,
          game: game,
        );
      }

      _appendLog('构建完成: $game -> $platform');
      await _openBuildOutputInFileManager(gameDir, platform);
    } on _TaskFailure catch (e) {
      _appendLog('构建失败: ${e.message}');
    } finally {
      if (_buildMode == BuildMode.release) {
        await gamePubspec.writeAsString(originalPubspec);
        await engineLoader.writeAsString(originalEngineLoader);
        _appendLog('已恢复临时修改文件（pubspec + 编译入口）');
      }
    }
  }

  Future<_AssetRewriteResult> _prepareReleasePubspec({
    required Directory gameDir,
    required File pubspecFile,
  }) async {
    final lines = await pubspecFile.readAsLines();
    var assetsStart = -1;
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'^\s{2}assets:\s*$').hasMatch(lines[i])) {
        assetsStart = i;
        break;
      }
    }

    if (assetsStart < 0) {
      throw _TaskFailure('pubspec.yaml 未找到 flutter/assets 段');
    }

    var assetsEnd = assetsStart;
    while (assetsEnd + 1 < lines.length) {
      final nextLine = lines[assetsEnd + 1];
      final isAssetLine = RegExp(r'^\s{4}-\s+').hasMatch(nextLine);
      if (isAssetLine || nextLine.trim().isEmpty) {
        assetsEnd += 1;
        continue;
      }
      break;
    }

    final rawEntries = <String>[];
    for (var i = assetsStart + 1; i <= assetsEnd; i++) {
      final match = RegExp(r'^\s{4}-\s+(.+)$').firstMatch(lines[i]);
      if (match == null) {
        continue;
      }
      var entry = match.group(1)!.replaceAll(RegExp(r'\s+#.*$'), '').trim();
      if ((entry.startsWith('"') && entry.endsWith('"')) ||
          (entry.startsWith("'") && entry.endsWith("'"))) {
        entry = entry.substring(1, entry.length - 1);
      }
      if (entry.isNotEmpty) {
        rawEntries.add(entry);
      }
    }

    final expanded = <String>[];
    for (final entry in rawEntries) {
      if (_isGameScriptPath(entry)) {
        continue;
      }
      final normalized = _normalizePath(entry).replaceAll(RegExp(r'/$'), '');
      final fullPath = _joinPath(gameDir.path, normalized);
      final type = FileSystemEntity.typeSync(fullPath);

      if (type == FileSystemEntityType.notFound) {
        _appendLog('警告: 资源路径不存在，已跳过: $entry');
        continue;
      }

      if (type == FileSystemEntityType.file) {
        expanded.add(normalized);
        continue;
      }

      final files = <File>[];
      await for (final entity in Directory(
        fullPath,
      ).list(recursive: true, followLinks: false)) {
        if (entity is File) {
          if (_basename(entity.path) == '.DS_Store') {
            continue;
          }
          files.add(entity);
        }
      }
      files.sort((a, b) => a.path.compareTo(b.path));

      for (final file in files) {
        final relative = _relativePath(file.path, gameDir.path);
        if (_isGameScriptPath(relative)) {
          continue;
        }
        expanded.add(_normalizePath(relative));
      }
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final entry in expanded) {
      if (entry.isEmpty) {
        continue;
      }
      if (seen.add(entry)) {
        deduped.add(entry);
      }
    }

    if (deduped.isEmpty) {
      throw _TaskFailure('发布资源清单为空，已中止构建');
    }

    final hasAssetsRoot = rawEntries.any((entry) {
      final n = _normalizePath(entry).replaceAll(RegExp(r'/$'), '');
      return n == 'Assets';
    });
    final mediaCount = deduped
        .where(
          (entry) => RegExp(
            r'^Assets/images/.*\.(png|jpg|jpeg|gif|bmp|webp|avif|mp4|mov|avi|mkv|webm)$',
            caseSensitive: false,
          ).hasMatch(entry),
        )
        .length;
    if (hasAssetsRoot && mediaCount == 0) {
      throw _TaskFailure('检测到配置了 Assets/，但展开后没有 Assets/images 资源，已中止构建');
    }

    final output = <String>[];
    output.addAll(lines.sublist(0, assetsStart + 1));
    for (final entry in deduped) {
      output.add('    - $entry');
    }
    if (assetsEnd + 1 < lines.length) {
      output.addAll(lines.sublist(assetsEnd + 1));
    }

    await pubspecFile.writeAsString('${output.join('\n')}\n');
    return _AssetRewriteResult(
      totalAssets: deduped.length,
      mediaAssets: mediaCount,
    );
  }

  List<String> _buildArgsFor(String platform, BuildMode mode, String game) {
    final showModeDefine = mode == BuildMode.showcase
        ? <String>[
            '--dart-define=SAKI_SHOW_MODE=true',
            '--dart-define=SAKI_SHOWCASE_GAME_DIR=Game/$game',
          ]
        : const <String>[];
    switch (platform) {
      case 'macos':
        return <String>['build', 'macos', '--release', ...showModeDefine];
      case 'linux':
        return <String>['build', 'linux', '--release', ...showModeDefine];
      case 'windows':
        return <String>['build', 'windows', '--release', ...showModeDefine];
      case 'android':
        return <String>[
          'build',
          'apk',
          '--release',
          '--target-platform',
          'android-arm64',
          ...showModeDefine,
        ];
      case 'ios':
        return <String>[
          'build',
          'ios',
          '--release',
          '--no-codesign',
          ...showModeDefine,
        ];
      case 'web':
        return <String>['build', 'web', '--release', ...showModeDefine];
      default:
        throw _TaskFailure('不支持的平台: $platform');
    }
  }

  Future<void> _stageShowcaseGameDirectory({
    required Directory gameDir,
    required Directory outputDir,
    required String game,
  }) async {
    if (!outputDir.existsSync()) {
      throw _TaskFailure('构建产物目录不存在: ${outputDir.path}');
    }

    final sourceAssetsDir = Directory(_joinPath(gameDir.path, 'Assets'));
    if (!sourceAssetsDir.existsSync()) {
      throw _TaskFailure('演出模式资源目录不存在: ${sourceAssetsDir.path}');
    }

    final scriptDirs = gameDir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((dir) {
          final name = _basename(dir.path);
          return name == 'GameScript' || name.startsWith('GameScript_');
        })
        .toList();
    if (scriptDirs.isEmpty) {
      throw _TaskFailure('未找到 GameScript 目录，无法生成演出模式可热更新包');
    }

    final targetGameRoot = Directory(
      _joinPath(_joinPath(outputDir.path, 'Game'), game),
    );
    if (targetGameRoot.existsSync()) {
      await targetGameRoot.delete(recursive: true);
    }
    await targetGameRoot.create(recursive: true);

    await _copyDirectoryRecursive(
      source: sourceAssetsDir,
      target: Directory(_joinPath(targetGameRoot.path, 'Assets')),
    );
    for (final dir in scriptDirs) {
      final name = _basename(dir.path);
      await _copyDirectoryRecursive(
        source: dir,
        target: Directory(_joinPath(targetGameRoot.path, name)),
      );
    }

    for (final fileName in const <String>[
      'game_config.txt',
      'default_game.txt',
      'icon.png',
    ]) {
      final sourceFile = File(_joinPath(gameDir.path, fileName));
      if (!sourceFile.existsSync()) {
        continue;
      }
      final targetFile = File(_joinPath(targetGameRoot.path, fileName));
      await targetFile.parent.create(recursive: true);
      await sourceFile.copy(targetFile.path);
    }

    _appendLog('演出模式资源已打包: ${targetGameRoot.path}');
  }

  Future<void> _copyDirectoryRecursive({
    required Directory source,
    required Directory target,
  }) async {
    if (!await source.exists()) {
      return;
    }

    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = _basename(entity.path);
      final destinationPath = _joinPath(target.path, name);
      if (entity is Directory) {
        await _copyDirectoryRecursive(
          source: entity,
          target: Directory(destinationPath),
        );
      } else if (entity is File) {
        await entity.copy(destinationPath);
      }
    }
  }

  Directory _resolveBuildOutputDirectory(Directory gameDir, String platform) {
    final candidates = <String>[];
    switch (platform) {
      case 'macos':
        candidates.add(
          _joinPath(gameDir.path, 'build/macos/Build/Products/Release'),
        );
        break;
      case 'linux':
        candidates.add(
          _joinPath(gameDir.path, 'build/linux/x64/release/bundle'),
        );
        break;
      case 'windows':
        candidates.add(
          _joinPath(gameDir.path, 'build/windows/x64/runner/Release'),
        );
        break;
      case 'android':
        candidates.add(
          _joinPath(gameDir.path, 'build/app/outputs/flutter-apk'),
        );
        candidates.add(
          _joinPath(gameDir.path, 'build/app/outputs/apk/release'),
        );
        break;
      case 'ios':
        candidates.add(_joinPath(gameDir.path, 'build/ios/iphoneos'));
        candidates.add(_joinPath(gameDir.path, 'build/ios/archive'));
        break;
      case 'web':
        candidates.add(_joinPath(gameDir.path, 'build/web'));
        break;
      default:
        break;
    }

    for (final candidate in candidates) {
      final dir = Directory(candidate);
      if (dir.existsSync()) {
        return dir;
      }
    }
    return Directory(_joinPath(gameDir.path, 'build'));
  }

  Future<void> _openBuildOutputInFileManager(
    Directory gameDir,
    String platform,
  ) async {
    final targetDir = _resolveBuildOutputDirectory(gameDir, platform);
    if (!targetDir.existsSync()) {
      _appendLog('提示: 构建输出目录不存在，跳过自动打开: ${targetDir.path}');
      return;
    }

    int code = -1;
    if (Platform.isMacOS) {
      code = await _runDetachedCommand(
        executable: 'open',
        arguments: <String>[targetDir.path],
        workingDirectory: _repoRoot.path,
      );
    } else if (Platform.isWindows) {
      code = await _runDetachedCommand(
        executable: 'explorer',
        arguments: <String>[_toWindowsPath(targetDir.path)],
        workingDirectory: _repoRoot.path,
      );
    } else if (Platform.isLinux) {
      if (await _isCommandAvailable('xdg-open')) {
        code = await _runDetachedCommand(
          executable: 'xdg-open',
          arguments: <String>[targetDir.path],
          workingDirectory: _repoRoot.path,
        );
      } else if (await _isCommandAvailable('gio')) {
        code = await _runDetachedCommand(
          executable: 'gio',
          arguments: <String>['open', targetDir.path],
          workingDirectory: _repoRoot.path,
        );
      }
    }

    if (code == 0) {
      _appendLog('已自动打开构建产物目录: ${targetDir.path}');
    } else {
      _appendLog('提示: 自动打开目录失败，请手动查看: ${targetDir.path}');
    }
  }

  Future<bool> _launchRunInSystemTerminal({
    required String game,
    required String gameDir,
    required String runDevice,
    required RunBuildMode runBuildMode,
  }) async {
    final scriptDir = Directory(_joinPath(_repoRoot.path, '.saki_launcher'));
    scriptDir.createSync(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;

    if (Platform.isWindows) {
      final scriptFile = File(_joinPath(scriptDir.path, 'run_$ts.cmd'));
      await scriptFile.writeAsString(
        _buildWindowsRunScript(
          game: game,
          gameDir: gameDir,
          runDevice: runDevice,
          runBuildMode: runBuildMode,
        ),
      );
      final code = await _runDetachedCommand(
        executable: 'cmd',
        arguments: <String>['/c', 'start', '', scriptFile.path],
        workingDirectory: _repoRoot.path,
      );
      return code == 0;
    }

    final scriptFile = File(_joinPath(scriptDir.path, 'run_$ts.command'));
    await scriptFile.writeAsString(
      _buildPosixRunScript(
        game: game,
        gameDir: gameDir,
        runDevice: runDevice,
        runBuildMode: runBuildMode,
      ),
    );

    final chmod = await _runCommand(
      executable: 'chmod',
      arguments: <String>['+x', scriptFile.path],
      workingDirectory: _repoRoot.path,
    );
    if (chmod != 0) {
      _appendLog('赋予脚本执行权限失败');
      return false;
    }

    if (Platform.isMacOS) {
      final code = await _runDetachedCommand(
        executable: 'open',
        arguments: <String>[scriptFile.path],
        workingDirectory: _repoRoot.path,
      );
      return code == 0;
    }

    if (Platform.isLinux) {
      final candidates = <_TerminalCandidate>[
        _TerminalCandidate('x-terminal-emulator', <String>[
          '-e',
          scriptFile.path,
        ]),
        _TerminalCandidate('gnome-terminal', <String>[
          '--',
          'bash',
          scriptFile.path,
        ]),
        _TerminalCandidate('konsole', <String>['-e', 'bash', scriptFile.path]),
        _TerminalCandidate('xterm', <String>['-e', 'bash', scriptFile.path]),
      ];
      for (final candidate in candidates) {
        if (!await _isCommandAvailable(candidate.executable)) {
          continue;
        }
        final code = await _runDetachedCommand(
          executable: candidate.executable,
          arguments: candidate.arguments,
          workingDirectory: _repoRoot.path,
        );
        if (code == 0) {
          return true;
        }
      }
      return false;
    }

    return false;
  }

  String _buildPosixRunScript({
    required String game,
    required String gameDir,
    required String runDevice,
    required RunBuildMode runBuildMode,
  }) {
    final repoEsc = _shellEscape(_repoRoot.path);
    final gameEsc = _shellEscape(game);
    final gameDirEsc = _shellEscape(gameDir);
    final bridgeEsc = _shellEscape(
      _joinPath(_repoRoot.path, 'scripts/launcher-bridge.js'),
    );
    final deviceEsc = _shellEscape(runDevice);
    final defineArgs = <String>[
      '--dart-define=SAKI_GAME_PATH=$gameDir',
      if (_isShowcaseMode(runBuildMode)) '--dart-define=SAKI_SHOW_MODE=true',
      if (_isShowcaseMode(runBuildMode))
        '--dart-define=SAKI_SHOWCASE_GAME_DIR=Game/$game',
    ];
    final defineEsc = defineArgs.map(_shellEscape).join(' ');
    final modeFlag = _runBuildModeFlag(runBuildMode);
    final modePart = modeFlag.isEmpty ? '' : '${_shellEscape(modeFlag)} ';

    return '''#!/usr/bin/env bash
set -euo pipefail

cd $repoEsc
node $bridgeEsc prepare-project --game $gameEsc
cd $gameDirEsc
flutter pub get
node $bridgeEsc prepare-project --game $gameEsc --generate-icons

echo ""
echo "启动 Flutter 运行（支持 r/R/q 热更新命令）..."
set +e
flutter run ${modePart}-d $deviceEsc $defineEsc
status=\$?
set -e

echo ""
echo "运行已结束（退出码: \$status）"
read -r -p "按回车关闭终端..." _
exit \$status
''';
  }

  String _buildWindowsRunScript({
    required String game,
    required String gameDir,
    required String runDevice,
    required RunBuildMode runBuildMode,
  }) {
    final repoPath = _toWindowsPath(_repoRoot.path);
    final gamePath = _toWindowsPath(gameDir);
    final bridgeScript = _toWindowsPath(
      _joinPath(_repoRoot.path, 'scripts/launcher-bridge.js'),
    );
    final modeFlag = _runBuildModeFlag(runBuildMode);
    final modePart = modeFlag.isEmpty ? '' : '$modeFlag ';
    final extraShowModeDefine = _isShowcaseMode(runBuildMode)
        ? ' "--dart-define=SAKI_SHOW_MODE=true" "--dart-define=SAKI_SHOWCASE_GAME_DIR=Game/$game"'
        : '';

    return '''@echo off
setlocal

cd /d "$repoPath"
if errorlevel 1 goto end

node "$bridgeScript" prepare-project --game "$game"
if errorlevel 1 goto end

cd /d "$gamePath"
if errorlevel 1 goto end

flutter pub get
if errorlevel 1 goto end

node "$bridgeScript" prepare-project --game "$game" --generate-icons
if errorlevel 1 goto end

echo.
echo 启动 Flutter 运行（支持 r/R/q 热更新命令）...
flutter run ${modePart}-d $runDevice "--dart-define=SAKI_GAME_PATH=$gamePath"$extraShowModeDefine

:end
echo.
echo 运行已结束，按任意键关闭窗口...
pause >nul
endlocal
''';
  }

  Future<bool> _isCommandAvailable(String command) async {
    final lookupExecutable = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(
        lookupExecutable,
        <String>[command],
        runInShell: true,
        workingDirectory: _repoRoot.path,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<int> _runDetachedCommand({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final command = '$executable ${arguments.join(' ')}';
    _appendLog('\$ $command');
    try {
      await Process.start(
        executable,
        arguments,
        runInShell: true,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
      );
      return 0;
    } on ProcessException catch (e) {
      _appendLog('命令启动失败: ${e.message}');
      return -1;
    }
  }

  Future<int> _runCommand({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
  }) async {
    final command = '$executable ${arguments.join(' ')}';
    _appendLog('\$ $command');
    Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        runInShell: true,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      _appendLog('命令启动失败: ${e.message}');
      return -1;
    }
    _activeProcess = process;

    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_appendLog);
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _appendLog('[stderr] $line'));

    final code = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();
    if (identical(_activeProcess, process)) {
      _activeProcess = null;
    }
    _appendLog('退出码: $code');
    return code;
  }

  Future<void> _sendRunControl(String control, String label) async {
    final process = _activeProcess;
    if (process == null || !_isRunTask) {
      _appendLog('没有可控制的运行进程');
      return;
    }

    try {
      process.stdin.write(control);
      await process.stdin.flush();
      _appendLog('已发送运行指令: $label');
    } catch (e) {
      _appendLog('发送运行指令失败: $e');
    }
  }

  Future<void> _requestSafeRestart() async {
    final process = _activeProcess;
    if (process == null || !_isRunTask) {
      _appendLog('没有可重启的运行进程');
      return;
    }
    if (_runMode != RunLaunchMode.embedded) {
      _appendLog('系统终端模式请在终端内手动重启');
      return;
    }

    _pendingSafeRestart = true;
    _appendLog('已请求安全重启：将停止当前运行并自动重新启动');
    await _sendRunControl('q', '退出运行');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (identical(process, _activeProcess)) {
      await _stopActiveTask();
    }
  }

  Future<void> _requestHotRestart() async {
    final process = _activeProcess;
    if (process == null || !_isRunTask) {
      _appendLog('没有可重启的运行进程');
      return;
    }
    if (_runMode != RunLaunchMode.embedded) {
      _appendLog('系统终端模式请在终端内手动热重启');
      return;
    }
    if (_runBuildMode != RunBuildMode.debug) {
      _appendLog('仅 Debug 运行配置支持热重启');
      return;
    }
    await _sendRunControl('R', '热重启');
  }

  Future<void> _stopActiveTask() async {
    final process = _activeProcess;
    if (process == null) {
      return;
    }
    _appendLog('请求停止任务...');
    try {
      process.kill(ProcessSignal.sigint);
    } catch (_) {
      process.kill();
    }

    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (identical(process, _activeProcess)) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {
        process.kill();
      }
    }
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }
    final sanitized = line.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add('[$time] $sanitized');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) {
        return;
      }
      _logScrollController.jumpTo(
        _logScrollController.position.maxScrollExtent,
      );
    });
  }

  String _joinPath(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) {
      return '$a$b';
    }
    return '$a${Platform.pathSeparator}$b';
  }

  String _basename(String path) {
    final normalized = _normalizePath(path).replaceAll(RegExp(r'/$'), '');
    final index = normalized.lastIndexOf('/');
    if (index < 0) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  String _toWindowsPath(String path) {
    return path.replaceAll('/', '\\');
  }

  String _shellEscape(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _relativePath(String fullPath, String basePath) {
    final full = _normalizePath(fullPath);
    final base = _normalizePath(basePath).replaceAll(RegExp(r'/$'), '');
    if (full.startsWith('$base/')) {
      return full.substring(base.length + 1);
    }
    return full;
  }

  bool _isGameScriptPath(String path) {
    final n = _normalizePath(path).replaceAll(RegExp(r'/$'), '');
    return n == 'GameScript' ||
        n.startsWith('GameScript/') ||
        n.startsWith('GameScript_');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? <Color>[
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.08),
                      scheme.surface,
                    ),
                    scheme.surface,
                    Color.alphaBlend(
                      scheme.tertiary.withValues(alpha: 0.07),
                      scheme.surface,
                    ),
                  ]
                : <Color>[
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.10),
                      scheme.surface,
                    ),
                    Color.alphaBlend(
                      scheme.secondary.withValues(alpha: 0.08),
                      scheme.surface,
                    ),
                    Color.alphaBlend(
                      scheme.tertiary.withValues(alpha: 0.10),
                      scheme.surface,
                    ),
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final leftFlex = constraints.maxWidth >= 1200
                    ? 36
                    : constraints.maxWidth >= 900
                    ? 40
                    : 44;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildHeader(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(flex: leftFlex, child: _buildControlPanel()),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 100 - leftFlex,
                            child: _buildLogPanel(),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final engineIconFile = File(_joinPath(_repoRoot.path, 'Engine/icon.png'));
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: isDark ? 0.86 : 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.52 : 0.34),
        ),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: engineIconFile.existsSync()
                ? Image.file(
                    engineIconFile,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.rocket_launch_rounded,
                      color: scheme.onPrimary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'SakiEngine 开发启动器',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '统一执行创建、运行与发布构建任务',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showSettingsDialog,
            tooltip: '设置',
            icon: const Icon(Icons.tune_rounded),
          ),
          if (_busy)
            const Row(
              children: <Widget>[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('任务执行中'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    final defaultLabel = _defaultGame == null ? '未设置' : _defaultGame!;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: isDark ? 0.88 : 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.48 : 0.3),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            '项目控制',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _repoRoot.path,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _selectedGame,
            decoration: const InputDecoration(
              labelText: '游戏项目',
              border: OutlineInputBorder(),
            ),
            items: _gameProjects
                .map(
                  (name) =>
                      DropdownMenuItem<String>(value: name, child: Text(name)),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _selectedGame = value;
                    });
                  },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _refreshProjects,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新项目'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || _selectedGame == null
                      ? null
                      : _setDefaultGame,
                  icon: const Icon(Icons.push_pin_outlined),
                  label: const Text('设为默认'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showCreateProjectDialog,
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('创建新项目'),
          ),
          const SizedBox(height: 8),
          Text('默认项目: $defaultLabel'),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text('运行', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _runTarget,
            decoration: const InputDecoration(
              labelText: '运行目标',
              border: OutlineInputBorder(),
            ),
            items: _runTargets
                .map(
                  (target) => DropdownMenuItem<String>(
                    value: target,
                    child: Text(target),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _runTarget = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<RunLaunchMode>(
            initialValue: _runMode,
            decoration: const InputDecoration(
              labelText: '运行模式',
              border: OutlineInputBorder(),
            ),
            items: RunLaunchMode.values
                .map(
                  (mode) => DropdownMenuItem<RunLaunchMode>(
                    value: mode,
                    child: Text(_runModeLabel(mode)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _runMode = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<RunBuildMode>(
            initialValue: _runBuildMode,
            decoration: const InputDecoration(
              labelText: '运行配置',
              border: OutlineInputBorder(),
            ),
            items: RunBuildMode.values
                .map(
                  (mode) => DropdownMenuItem<RunBuildMode>(
                    value: mode,
                    child: Text(_runBuildModeLabel(mode)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) async {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _runBuildMode = value;
                    });
                    final next = widget.settingsNotifier.value.copyWith(
                      defaultRunBuildMode: value,
                    );
                    await _saveSettings(next);
                  },
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || _selectedGame == null ? null : _runSelectedGame,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('运行游戏'),
          ),
          if (_isRunTask &&
              _runMode == RunLaunchMode.embedded &&
              _activeProcess != null) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton(
                  onPressed: _runBuildMode == RunBuildMode.debug
                      ? () {
                          unawaited(_requestHotRestart());
                        }
                      : null,
                  child: const Text('热重启 R'),
                ),
                OutlinedButton(
                  onPressed: _runBuildMode == RunBuildMode.debug
                      ? () {
                          unawaited(_sendRunControl('r', '热重载'));
                        }
                      : null,
                  child: const Text('热重载 r'),
                ),
                OutlinedButton(
                  onPressed: () {
                    unawaited(_requestSafeRestart());
                  },
                  child: const Text('安全重启'),
                ),
                OutlinedButton(
                  onPressed: () {
                    unawaited(_sendRunControl('q', '退出运行'));
                  },
                  child: const Text('退出 q'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text('构建', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<BuildMode>(
            initialValue: _buildMode,
            decoration: const InputDecoration(
              labelText: '构建模式',
              border: OutlineInputBorder(),
            ),
            items: BuildMode.values
                .map(
                  (mode) => DropdownMenuItem<BuildMode>(
                    value: mode,
                    child: Text(_buildModeLabel(mode)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _buildMode = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _buildTarget,
            decoration: const InputDecoration(
              labelText: '构建目标',
              border: OutlineInputBorder(),
            ),
            items: _buildTargets
                .map(
                  (target) => DropdownMenuItem<String>(
                    value: target,
                    child: Text(target),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _buildTarget = value;
                    });
                  },
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy || _selectedGame == null
                ? null
                : _buildSelectedGame,
            icon: const Icon(Icons.build_circle_outlined),
            label: Text(_buildMode == BuildMode.showcase ? '演出构建' : '发布构建'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? _stopActiveTask : null,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(_isRunTask ? '停止运行任务' : '停止当前任务'),
          ),
          const SizedBox(height: 10),
          Text(
            '说明: 启动器已覆盖 run.sh/build.sh 主要流程，可直接在此完成创建、运行、构建。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBackground = Color.alphaBlend(
      (isDark ? Colors.black : scheme.primary).withValues(
        alpha: isDark ? 0.22 : 0.06,
      ),
      scheme.surfaceContainerLow,
    );
    final panelBorder = scheme.outlineVariant.withValues(
      alpha: isDark ? 0.6 : 0.36,
    );
    final headerTextColor = scheme.onSurface;
    final bodyTextColor = scheme.onSurface.withValues(
      alpha: isDark ? 0.92 : 0.95,
    );

    return Container(
      decoration: BoxDecoration(
        color: panelBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: panelBorder)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '终端输出',
                    style: TextStyle(
                      color: headerTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _clearLogs,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('清空'),
                ),
                TextButton.icon(
                  onPressed: _logs.isEmpty
                      ? null
                      : () {
                          unawaited(_copyAllLogs());
                        },
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('复制全部'),
                ),
              ],
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return SelectableText.rich(
                    _buildLogLineSpan(_logs[index]),
                    style: TextStyle(
                      color: bodyTextColor,
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAllLogs() async {
    final allLogs = _logs.join('\n');
    await Clipboard.setData(ClipboardData(text: allLogs));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('终端日志已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  TextSpan _buildLogLineSpan(String line) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeColor = scheme.outline.withValues(alpha: isDark ? 0.95 : 0.85);
    final timeMatch = RegExp(r'^\[\d{2}:\d{2}:\d{2}\]\s?').firstMatch(line);
    final children = <InlineSpan>[];
    var body = line;
    if (timeMatch != null) {
      final prefix = line.substring(0, timeMatch.end);
      body = line.substring(timeMatch.end);
      children.add(
        TextSpan(
          text: prefix,
          style: TextStyle(
            color: timeColor,
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
      );
    }

    final bodyStyle = _resolveLogBodyStyle(body);
    children.add(TextSpan(text: body, style: bodyStyle));
    return TextSpan(children: children);
  }

  TextStyle _resolveLogBodyStyle(String body) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = TextStyle(
      color: scheme.onSurface.withValues(alpha: isDark ? 0.92 : 0.95),
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.35,
    );
    final normalized = body.toLowerCase();

    if (body.startsWith('\$ ') || normalized.contains('flutter run')) {
      return base.copyWith(color: scheme.primary);
    }
    if (body.startsWith('[stderr]') ||
        normalized.contains('error') ||
        normalized.contains('exception') ||
        body.contains('失败') ||
        body.contains('错误') ||
        RegExp(r'退出码:\s*[1-9]\d*').hasMatch(body)) {
      return base.copyWith(color: scheme.error);
    }
    if (normalized.contains('warning') || body.contains('警告')) {
      return base.copyWith(color: scheme.tertiary);
    }
    if (body.contains('成功') ||
        body.contains('完成') ||
        body.contains('可用') ||
        body.contains('已复制') ||
        body.contains('退出码: 0')) {
      return base.copyWith(color: scheme.secondary);
    }

    return base;
  }
}

class _SeedChoice {
  final String label;
  final Color color;

  const _SeedChoice(this.label, this.color);
}

String _launcherSettingsFilePath() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  return '$home/.sakiengine_launcher_settings.json';
}

Future<LauncherUiSettings> _loadLauncherUiSettings() async {
  final file = File(_launcherSettingsFilePath());
  if (!file.existsSync()) {
    return LauncherUiSettings.defaults();
  }

  try {
    final raw = await file.readAsString();
    final jsonMap = jsonDecode(raw);
    if (jsonMap is Map<String, dynamic>) {
      return LauncherUiSettings.fromJson(jsonMap);
    }
    if (jsonMap is Map) {
      return LauncherUiSettings.fromJson(
        jsonMap.map((key, value) => MapEntry('$key', value)),
      );
    }
  } catch (_) {
    // ignore and fallback to defaults.
  }
  return LauncherUiSettings.defaults();
}

Future<void> _saveLauncherUiSettings(LauncherUiSettings settings) async {
  final file = File(_launcherSettingsFilePath());
  try {
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  } catch (_) {
    // ignore write failure; runtime settings still applied in memory.
  }
}

class _AssetRewriteResult {
  final int totalAssets;
  final int mediaAssets;

  const _AssetRewriteResult({
    required this.totalAssets,
    required this.mediaAssets,
  });
}

class _TerminalCandidate {
  final String executable;
  final List<String> arguments;

  const _TerminalCandidate(this.executable, this.arguments);
}

class _TaskFailure implements Exception {
  final String message;

  const _TaskFailure(this.message);
}
