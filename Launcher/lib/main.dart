import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SakiLauncherApp());
}

class SakiLauncherApp extends StatelessWidget {
  const SakiLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SakiEngine 开发启动器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF17685A),
          brightness: Brightness.light,
        ),
        fontFamily: 'Noto Sans',
      ),
      home: const LauncherPage(),
    );
  }
}

class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key});

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

enum RunLaunchMode {
  embedded,
  systemTerminal,
}

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

  late final Directory _repoRoot;

  final List<String> _gameProjects = <String>[];
  final List<String> _logs = <String>[];
  final ScrollController _logScrollController = ScrollController();

  String? _selectedGame;
  String? _defaultGame;
  String _runTarget = 'web';
  RunLaunchMode _runMode = RunLaunchMode.embedded;
  String _buildTarget = 'web';
  bool _busy = false;
  bool _isRunTask = false;
  Process? _activeProcess;

  @override
  void initState() {
    super.initState();
    _repoRoot = _discoverRepoRoot();
    _runTarget = _recommendedRunTarget();
    _buildTarget = _recommendedBuildTarget();
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
      arguments: <String>[
        'scripts/launcher-bridge.js',
        ...bridgeArgs,
      ],
      workingDirectory: _repoRoot.path,
    );
  }

  Future<void> _prepareProjectForExecution(
    String game, {
    required bool generateIcons,
  }) async {
    final args = <String>[
      'prepare-project',
      '--game',
      game,
    ];
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
                          style: const TextStyle(
                            color: Color(0xFF9A4E00),
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

                          final nameOk = RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name);
                          final bundleOk = RegExp(
                            r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){2,}$',
                          ).hasMatch(bundle);
                          final colorOk = RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(color);

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

    setState(() {
      _busy = true;
      _isRunTask = true;
    });
    _appendLog(
      '开始运行游戏: $game (target=$runDevice, mode=${_runModeLabel(_runMode)})',
    );

    try {
      if (_runMode == RunLaunchMode.systemTerminal) {
        final launched = await _launchRunInSystemTerminal(
          game: game,
          gameDir: gameDir,
          runDevice: runDevice,
        );
        if (launched) {
          _appendLog('已在系统终端启动运行任务，可在终端中使用 r/R/q');
        } else {
          _appendLog('启动失败: 未找到可用系统终端');
        }
        return;
      }

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

      final runCode = await _runCommand(
        executable: 'flutter',
        arguments: <String>[
          'run',
          '-d',
          runDevice,
          '--dart-define=SAKI_GAME_PATH=$gameDir',
        ],
        workingDirectory: gameDir,
      );
      if (runCode != 0) {
        _appendLog('运行中止: flutter run 失败');
      }
    } on _TaskFailure catch (e) {
      _appendLog('运行失败: ${e.message}');
    } catch (e) {
      _appendLog('运行异常: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _isRunTask = false;
          _activeProcess = null;
        });
      }
      _appendLog('运行任务结束');
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

    _appendLog('开始构建: $game -> $platform');

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

      final buildArgs = _buildArgsFor(platform);
      final buildCode = await _runCommand(
        executable: 'flutter',
        arguments: buildArgs,
        workingDirectory: gameDir.path,
      );

      if (buildCode != 0) {
        throw _TaskFailure('flutter build 失败');
      }

      _appendLog('构建完成: $game -> $platform');
    } on _TaskFailure catch (e) {
      _appendLog('构建失败: ${e.message}');
    } finally {
      await gamePubspec.writeAsString(originalPubspec);
      await engineLoader.writeAsString(originalEngineLoader);
      _appendLog('已恢复临时修改文件（pubspec + 编译入口）');
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

  List<String> _buildArgsFor(String platform) {
    switch (platform) {
      case 'macos':
        return const <String>['build', 'macos', '--release'];
      case 'linux':
        return const <String>['build', 'linux', '--release'];
      case 'windows':
        return const <String>['build', 'windows', '--release'];
      case 'android':
        return const <String>[
          'build',
          'apk',
          '--release',
          '--target-platform',
          'android-arm64',
        ];
      case 'ios':
        return const <String>['build', 'ios', '--release', '--no-codesign'];
      case 'web':
        return const <String>['build', 'web', '--release'];
      default:
        throw _TaskFailure('不支持的平台: $platform');
    }
  }

  Future<bool> _launchRunInSystemTerminal({
    required String game,
    required String gameDir,
    required String runDevice,
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
        ),
      );
      final code = await _runDetachedCommand(
        executable: 'cmd',
        arguments: <String>[
          '/c',
          'start',
          '',
          scriptFile.path,
        ],
        workingDirectory: _repoRoot.path,
      );
      return code == 0;
    }

    final scriptFile = File(_joinPath(scriptDir.path, 'run_$ts.command'));
    await scriptFile.writeAsString(
      _buildPosixRunScript(game: game, gameDir: gameDir, runDevice: runDevice),
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
        _TerminalCandidate('x-terminal-emulator', <String>['-e', scriptFile.path]),
        _TerminalCandidate('gnome-terminal', <String>['--', 'bash', scriptFile.path]),
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
  }) {
    final repoEsc = _shellEscape(_repoRoot.path);
    final gameEsc = _shellEscape(game);
    final gameDirEsc = _shellEscape(gameDir);
    final bridgeEsc = _shellEscape(
      _joinPath(_repoRoot.path, 'scripts/launcher-bridge.js'),
    );
    final deviceEsc = _shellEscape(runDevice);
    final defineEsc = _shellEscape('--dart-define=SAKI_GAME_PATH=$gameDir');

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
flutter run -d $deviceEsc $defineEsc
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
  }) {
    final repoPath = _toWindowsPath(_repoRoot.path);
    final gamePath = _toWindowsPath(gameDir);
    final bridgeScript = _toWindowsPath(
      _joinPath(_repoRoot.path, 'scripts/launcher-bridge.js'),
    );

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
flutter run -d $runDevice "--dart-define=SAKI_GAME_PATH=$gamePath"

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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFE7F4F1),
              Color(0xFFF7F4EA),
              Color(0xFFEAF0FA),
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
                          Expanded(
                            flex: leftFlex,
                            child: _buildControlPanel(),
                          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF17685A).withValues(alpha: 0.18),
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
                      color: const Color(0xFF17685A),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                Text(
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
                  style: TextStyle(color: Color(0xFF4E5E5A)),
                ),
              ],
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF17685A).withValues(alpha: 0.15),
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
            style: const TextStyle(color: Color(0xFF53635F), fontSize: 12),
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
                  onPressed: () {
                    unawaited(_sendRunControl('r', '热重载'));
                  },
                  child: const Text('热重载 r'),
                ),
                OutlinedButton(
                  onPressed: () {
                    unawaited(_sendRunControl('R', '热重启'));
                  },
                  child: const Text('热重启 R'),
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
            label: const Text('发布构建'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? _stopActiveTask : null,
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(_isRunTask ? '停止运行任务' : '停止当前任务'),
          ),
          const SizedBox(height: 10),
          const Text(
            '说明: 启动器已覆盖 run.sh/build.sh 主要流程，可直接在此完成创建、运行、构建。',
            style: TextStyle(fontSize: 12, color: Color(0xFF5A6A66)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111418),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A313A)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A313A))),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '终端输出',
                    style: TextStyle(
                      color: Color(0xFFC9D1D9),
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
                    style: const TextStyle(
                      color: Color(0xFFD3DEE8),
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
    final timeMatch = RegExp(r'^\[\d{2}:\d{2}:\d{2}\]\s?').firstMatch(line);
    final children = <InlineSpan>[];
    var body = line;
    if (timeMatch != null) {
      final prefix = line.substring(0, timeMatch.end);
      body = line.substring(timeMatch.end);
      children.add(
        TextSpan(
          text: prefix,
          style: const TextStyle(
            color: Color(0xFF7B8A98),
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
    const base = TextStyle(
      color: Color(0xFFD3DEE8),
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.35,
    );
    final normalized = body.toLowerCase();

    if (body.startsWith('\$ ') || normalized.contains('flutter run')) {
      return base.copyWith(color: const Color(0xFF7DD3FC));
    }
    if (body.startsWith('[stderr]') ||
        normalized.contains('error') ||
        normalized.contains('exception') ||
        body.contains('失败') ||
        body.contains('错误') ||
        RegExp(r'退出码:\s*[1-9]\d*').hasMatch(body)) {
      return base.copyWith(color: const Color(0xFFF87171));
    }
    if (normalized.contains('warning') || body.contains('警告')) {
      return base.copyWith(color: const Color(0xFFFBBF24));
    }
    if (body.contains('成功') ||
        body.contains('完成') ||
        body.contains('可用') ||
        body.contains('已复制') ||
        body.contains('退出码: 0')) {
      return base.copyWith(color: const Color(0xFF86EFAC));
    }

    return base;
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
