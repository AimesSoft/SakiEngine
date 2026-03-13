import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/game/game_manager.dart';
import 'package:sakiengine/src/game/game_script_localization.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/debug_panel_dialog.dart';
import 'package:sakiengine/src/utils/svg_color_filter_utils.dart';
import 'package:sakiengine/src/widgets/common/close_button.dart';
import 'package:sakiengine/src/utils/read_text_tracker.dart';

class DeveloperPanel extends StatefulWidget {
  final VoidCallback onClose;
  final GameManager gameManager;
  final Future<void> Function()? onReload;

  const DeveloperPanel({
    Key? key,
    required this.onClose,
    required this.gameManager,
    this.onReload,
  }) : super(key: key);

  @override
  State<DeveloperPanel> createState() => _DeveloperPanelState();
}

class _DeveloperPanelState extends State<DeveloperPanel>
    with TickerProviderStateMixin {
  bool _showScriptPreview = false;
  bool _showDebugPanel = false;
  String _currentScriptContent = '';
  String _currentScriptPath = '';
  final TextEditingController _scriptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadCurrentScript();

    // 初始化动画
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scriptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleClose() async {
    await _animationController.reverse();
    widget.onClose();
  }

  Future<void> _loadCurrentScript() async {
    try {
      // 获取当前脚本名称（从GameManager获取）
      final currentScriptName = _getCurrentScriptName();

      if (currentScriptName.isNotEmpty) {
        // 尝试直接加载当前脚本文件
        final gamePath = await _getGamePathFromAssetManager();
        if (gamePath != null) {
          final candidateDirs = GameScriptLocalization.candidateDirectories();
          final attemptedPaths = <String>[];
          File? matchedFile;

          for (final dirName in candidateDirs) {
            final candidatePath =
                p.join(gamePath, dirName, 'labels', '$currentScriptName.sks');
            attemptedPaths.add(candidatePath);
            final candidateFile = File(candidatePath);
            if (await candidateFile.exists()) {
              matchedFile = candidateFile;
              break;
            }
          }

          if (matchedFile != null) {
            try {
              final content = await matchedFile.readAsString();
              _currentScriptContent = content;
              _currentScriptPath = matchedFile.path;
              _scriptController.text = content;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToCurrentPosition();
              });

              if (kDebugMode) {
                print('开发者面板: 成功加载脚本 ${matchedFile.path}');
              }
            } catch (readError) {
              if (kDebugMode) {
                print('开发者面板: 读取脚本文件失败: $readError');
              }
              _currentScriptContent = '''// 当前正在播放的脚本: $currentScriptName.sks
// 路径: ${matchedFile.path}
// 
// 无法直接读取脚本文件: $readError
// 
// 请使用"浏览脚本文件"功能手动选择文件进行编辑
''';
              _currentScriptPath = '';
              _scriptController.text = _currentScriptContent;
            }
          } else {
            final attemptedMessage = attemptedPaths.isEmpty
                ? '// 未找到可用的脚本路径'
                : attemptedPaths.map((path) => '//   - $path').join('\n');
            _currentScriptContent = '''// 当前正在播放的脚本: $currentScriptName.sks
// 
// 未找到脚本文件。已尝试路径:
$attemptedMessage
// 请使用"浏览脚本文件"功能手动选择文件
''';
            _currentScriptPath = '';
            _scriptController.text = _currentScriptContent;
          }
        } else {
          _currentScriptContent = '''// 当前正在播放的脚本: $currentScriptName.sks
// 
// 无法获取游戏路径，请使用"浏览脚本文件"功能
''';
          _currentScriptPath = '';
          _scriptController.text = _currentScriptContent;
        }
      } else {
        _currentScriptContent = '// 无法获取当前脚本名称，请使用"浏览脚本文件"功能';
        _currentScriptPath = '';
        _scriptController.text = _currentScriptContent;
      }
    } catch (e) {
      _currentScriptContent = '// 加载脚本失败: $e';
      _currentScriptPath = '';
      _scriptController.text = _currentScriptContent;
    }
    setState(() {});
  }

  void _scrollToCurrentPosition() {
    try {
      if (_currentScriptContent.isEmpty) {
        if (kDebugMode) {
          print('开发者面板: 脚本内容为空，跳过滚动');
        }
        return;
      }

      // 获取当前对话文本
      final currentDialogue = widget.gameManager.currentDialogueText;
      if (currentDialogue.isEmpty) {
        if (kDebugMode) {
          print('开发者面板: 当前对话文本为空，跳过滚动');
        }
        return;
      }

      final lines = _currentScriptContent.split('\n');
      if (lines.isEmpty) return;

      if (kDebugMode) {
        print('开发者面板: 搜索对话文本: "$currentDialogue"');
      }

      // 在脚本中搜索当前对话文本
      int targetLine = _findLineByDialogueText(lines, currentDialogue);

      if (targetLine >= 0) {
        if (kDebugMode) {
          print('开发者面板: 找到对话文本位置，行号=$targetLine');
        }
      } else {
        // 如果找不到完全匹配，尝试模糊搜索
        targetLine = _findLineByPartialText(lines, currentDialogue);
        if (targetLine >= 0) {
          if (kDebugMode) {
            print('开发者面板: 通过模糊搜索找到位置，行号=$targetLine');
          }
        } else {
          if (kDebugMode) {
            print('开发者面板: 未找到对话文本，跳过滚动');
          }
          return;
        }
      }

      // 计算滚动位置，稍微向上偏移几行以提供上下文
      const lineHeight = 21.0;
      final contextOffset = 3; // 向上偏移3行显示上下文
      final adjustedLine =
          (targetLine - contextOffset).clamp(0, lines.length - 1);
      final targetOffset = adjustedLine * lineHeight;

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );

        if (kDebugMode) {
          print(
              '开发者面板: 滚动到位置 $targetOffset (行 $adjustedLine, 原始行 $targetLine)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('开发者面板: 滚动到当前位置失败: $e');
      }
    }
  }

  int _findLineByDialogueText(List<String> lines, String dialogueText) {
    // 精确搜索：寻找包含对话文本的行
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 检查多种对话格式
      String? lineDialogue;

      if (line.startsWith('"') && line.endsWith('"')) {
        // 格式1: "对话文本"
        lineDialogue = line.substring(1, line.length - 1);
      } else if (line.contains('"') && line.endsWith('"')) {
        // 格式2: l "对话文本" 或 character "对话文本"
        final quoteStart = line.indexOf('"');
        if (quoteStart >= 0) {
          lineDialogue = line.substring(quoteStart + 1, line.length - 1);
        }
      }

      // 检查是否匹配
      if (lineDialogue != null) {
        if (lineDialogue.contains(dialogueText) ||
            dialogueText.contains(lineDialogue)) {
          return i;
        }
      }
    }
    return -1;
  }

  int _findLineByPartialText(List<String> lines, String dialogueText) {
    // 模糊搜索：寻找包含部分对话文本的行
    final searchText = dialogueText.trim();
    if (searchText.length < 3) return -1; // 太短的文本不进行模糊搜索

    // 取对话文本的前几个字符进行搜索
    final searchPrefix =
        searchText.substring(0, (searchText.length / 2).round());

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 在整行中搜索包含搜索前缀的内容
      if (line.contains(searchPrefix)) {
        return i;
      }
    }
    return -1;
  }

  int _getCurrentScriptIndex() {
    try {
      // 从GameManager获取当前脚本执行索引
      return widget.gameManager.currentScriptIndex;
    } catch (e) {
      if (kDebugMode) {
        print('开发者面板: 无法获取当前脚本索引: $e');
      }
      return 0;
    }
  }

  String _getCurrentScriptName() {
    // 从GameManager获取当前正在加载的脚本文件名
    try {
      final currentScriptFile = widget.gameManager.currentScriptFile;
      if (kDebugMode) {
        print('开发者面板: 获取到当前脚本文件名: $currentScriptFile');
      }
      return currentScriptFile;
    } catch (e) {
      if (kDebugMode) {
        print('开发者面板: 获取当前脚本名称失败: $e');
      }
      return 'start'; // 默认脚本
    }
  }

  /// 清除已读状态
  Future<void> _clearReadStatus() async {
    final config = SakiEngineConfig();

    // 显示确认对话框
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: config.themeColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(config.baseWindowBorder),
            side: BorderSide(
              color: config.themeColors.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          title: Text(
            '清除已读状态',
            style: TextStyle(
              color: config.themeColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '确定要清除所有已读文本记录吗？\n\n清除后，快进按钮将无法跳过任何文本，直到重新阅读。',
            style: TextStyle(
              color: config.themeColors.onSurface,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                '取消',
                style: TextStyle(color: config.themeColors.primary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                '确定',
                style: TextStyle(color: config.themeColors.primary),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // 清除所有已读记录
        await ReadTextTracker.instance.clearAllReadRecords();

        // 显示成功消息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已读状态已清除！快进功能将重新开始跟踪已读文本。',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: config.themeColors.primary,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        // 显示错误消息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '清除失败：$e',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _browseAndLoadScript() async {
    try {
      // 生成可能的脚本目录路径
      final possibleDirs = _generatePossibleScriptDirs();

      Directory? scriptDir;
      for (final dirPath in possibleDirs) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          scriptDir = dir;
          break;
        }
      }

      if (scriptDir == null) {
        // 如果找不到脚本目录，显示错误信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('找不到脚本目录，请检查项目路径配置'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 列出所有.sks文件
      final sksFiles = await scriptDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.sks'))
          .cast<File>()
          .toList();

      if (sksFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('在 ${scriptDir.path} 中未找到.sks脚本文件'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // 显示文件选择对话框
      final selectedFile = await _showFileSelectionDialog(sksFiles);
      if (selectedFile != null) {
        await _loadScriptFromFile(selectedFile);

        // 展开脚本预览
        if (!_showScriptPreview) {
          setState(() {
            _showScriptPreview = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('浏览文件失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  List<String> _generatePossibleScriptDirs() {
    final currentDir = Directory.current.path;
    final homeDir = Platform.environment['HOME'] ?? '';
    final variants = GameScriptLocalization.candidateDirectories();
    final paths = <String>{};

    void addVariantPath(String Function(String directoryName) builder) {
      for (final directoryName in variants) {
        final built = builder(directoryName);
        if (built.isEmpty) {
          continue;
        }
        paths.add(p.normalize(built));
      }
    }

    void addGameRoot(String gameRoot) {
      final root = Directory(gameRoot);
      if (!root.existsSync()) {
        return;
      }
      for (final entity in root.listSync()) {
        if (entity is! Directory) {
          continue;
        }
        addVariantPath((dir) => p.join(entity.path, dir, 'labels'));
      }
    }

    const fromDefine = String.fromEnvironment('SAKI_GAME_PATH', defaultValue: '');
    if (fromDefine.isNotEmpty && !fromDefine.contains('Containers')) {
      addVariantPath((dir) => p.join(fromDefine, dir, 'labels'));
    }

    final envPath = Platform.environment['SAKI_GAME_PATH'];
    if (envPath != null &&
        envPath.isNotEmpty &&
        !envPath.contains('Containers')) {
      addVariantPath((dir) => p.join(envPath, dir, 'labels'));
    }

    if (homeDir.isNotEmpty) {
      addGameRoot(p.join(homeDir, 'Documents', 'SakiEngine', 'Game'));
      addGameRoot(p.join(homeDir, 'Downloads', 'SakiEngine', 'Game'));
      addGameRoot(p.join(homeDir, 'Desktop', 'SakiEngine', 'Game'));
      addGameRoot(p.join(homeDir, 'SakiEngine', 'Game'));

      addVariantPath((dir) => p.join(homeDir, 'Documents', dir, 'labels'));
      addVariantPath((dir) => p.join(homeDir, 'Downloads', dir, 'labels'));
      addVariantPath((dir) => p.join(homeDir, 'Desktop', dir, 'labels'));
      addVariantPath((dir) => p.join(homeDir, dir, 'labels'));
    }

    if (!currentDir.contains('Containers')) {
      addGameRoot(p.join(currentDir, '..', 'Game'));
      addGameRoot(p.join(currentDir, '..', '..', 'Game'));
      addVariantPath((dir) => p.join(currentDir, '..', 'Game', dir, 'labels'));
      addVariantPath((dir) => p.join(currentDir, 'Game', dir, 'labels'));
      addVariantPath((dir) => p.join(currentDir, 'assets', dir, 'labels'));
      addVariantPath(
          (dir) => p.join(currentDir, '..', 'assets', dir, 'labels'));
    }

    return paths.toList();
  }

  Future<File?> _showFileSelectionDialog(List<File> files) async {
    return await showDialog<File>(
      context: context,
      builder: (BuildContext context) {
        final config = SakiEngineConfig();
        final textScale = context.scaleFor(ComponentType.text);

        return AlertDialog(
          backgroundColor: config.themeColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(config.baseWindowBorder),
          ),
          title: Text(
            '选择脚本文件',
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.8,
              color: config.themeColors.primary,
            ),
          ),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final fileName = file.path.split('/').last;

                return ListTile(
                  title: Text(
                    fileName,
                    style: config.dialogueTextStyle.copyWith(
                      fontSize:
                          config.dialogueTextStyle.fontSize! * textScale * 0.6,
                      color: config.themeColors.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    file.path,
                    style: config.dialogueTextStyle.copyWith(
                      fontSize:
                          config.dialogueTextStyle.fontSize! * textScale * 0.5,
                      color: config.themeColors.onSurface.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).pop(file),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '取消',
                style: TextStyle(color: config.themeColors.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadScriptFromFile(File file) async {
    try {
      final content = await file.readAsString();
      setState(() {
        _currentScriptContent = content;
        _currentScriptPath = file.path;
        _scriptController.text = content;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已加载: ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载文件失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 复制AssetManager中的游戏路径获取逻辑
  Future<String?> _getGamePathFromAssetManager() async {
    // 首先检查环境变量
    const fromDefine =
        String.fromEnvironment('SAKI_GAME_PATH', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv = Platform.environment['SAKI_GAME_PATH'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    try {
      // 从assets读取default_game.txt
      final assetContent =
          await AssetManager().loadString('assets/default_game.txt');
      final defaultGame = assetContent.trim();

      if (defaultGame.isEmpty) {
        throw Exception('default_game.txt is empty');
      }

      final gamePath = p.join(Directory.current.path, 'Game', defaultGame);
      if (kDebugMode) {
        print("开发者面板: 从default_game.txt获取游戏路径: $gamePath");
      }

      return gamePath;
    } catch (e) {
      if (kDebugMode) {
        print('开发者面板: 无法获取游戏路径: $e');
      }
      return null;
    }
  }

  Future<void> _saveAndReloadScript() async {
    if (_currentScriptPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请先使用"浏览脚本文件"功能选择要编辑的脚本文件，或点击"脚本预览"加载当前脚本'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    try {
      bool saveSuccess = false;
      String errorMessage = '';

      // 方法1: 直接文件写入（如果沙箱被禁用）
      try {
        final file = File(_currentScriptPath);
        await file.writeAsString(_scriptController.text);
        saveSuccess = true;

        if (kDebugMode) {
          print('开发者面板: 直接文件写入成功 $_currentScriptPath');
        }
      } catch (directWriteError) {
        if (kDebugMode) {
          print('开发者面板: 直接文件写入失败: $directWriteError');
        }

        // 方法2: 使用命令行 echo 写入（绕过沙箱限制）
        try {
          final content = _scriptController.text;
          // 转义特殊字符
          final escapedContent = content
              .replaceAll('\\', '\\\\')
              .replaceAll('\$', '\\\$')
              .replaceAll('"', '\\"')
              .replaceAll('\n', '\\n');

          final result = await Process.run('sh',
              ['-c', 'echo -e "$escapedContent" > "${_currentScriptPath}"']);

          if (result.exitCode == 0) {
            saveSuccess = true;
            if (kDebugMode) {
              print('开发者面板: 命令行写入成功 $_currentScriptPath');
            }
          } else {
            errorMessage = '命令行写入失败: ${result.stderr}';
          }
        } catch (commandError) {
          // 方法3: 使用 cp 命令
          try {
            final content = _scriptController.text;
            final tempFile =
                File('${Directory.systemTemp.path}/saki_temp_script.sks');
            await tempFile.writeAsString(content);

            final result =
                await Process.run('cp', [tempFile.path, _currentScriptPath]);
            await tempFile.delete();

            if (result.exitCode == 0) {
              saveSuccess = true;
              if (kDebugMode) {
                print('开发者面板: cp命令写入成功 $_currentScriptPath');
              }
            } else {
              errorMessage = 'cp命令失败: ${result.stderr}';
            }
          } catch (copyError) {
            errorMessage =
                '所有保存方法均失败: 直接写入($directWriteError), 命令行($commandError), cp($copyError)';
          }
        }
      }

      if (saveSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('脚本已保存: ${_currentScriptPath.split('/').last}'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }

        // 保存成功后自动重载
        if (widget.onReload != null) {
          try {
            await widget.onReload!();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('重载完成'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: Colors.blue,
                ),
              );
            }
          } catch (reloadError) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('重载失败: $reloadError'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
      } else {
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      if (kDebugMode) {
        print('开发者面板: 保存脚本失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final config = SakiEngineConfig();
    final uiScale = context.scaleFor(ComponentType.ui);
    final textScale = context.scaleFor(ComponentType.text);
    final panelWidth = screenSize.width / 6;

    return Stack(
      children: [
        AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Positioned(
              right: -panelWidth * _slideAnimation.value,
              top: 0,
              bottom: 0,
              width: panelWidth,
              child: Shortcuts(
                shortcuts: <LogicalKeySet, Intent>{
                  LogicalKeySet(LogicalKeyboardKey.escape):
                      const _CloseIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _CloseIntent: _CloseAction(_handleClose),
                  },
                  child: Focus(
                    autofocus: true,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20 * uiScale,
                              offset: Offset(-8 * uiScale, 0),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(config.baseWindowBorder),
                            bottomLeft:
                                Radius.circular(config.baseWindowBorder),
                          ),
                          child: Stack(
                            children: [
                              // 底层：纯色背景
                              Container(
                                width: double.infinity,
                                height: double.infinity,
                                color: config.themeColors.background,
                              ),
                              // 中层：背景图片
                              if (config.baseWindowBackground != null &&
                                  config.baseWindowBackground!.isNotEmpty)
                                Positioned.fill(
                                  child: Opacity(
                                    opacity:
                                        config.baseWindowBackgroundAlpha * 0.5,
                                    child: ColorFiltered(
                                      colorFilter: SvgColorFilterUtils
                                          .getSvgColorTemperatureFilter(config),
                                      child: Container(
                                          color: Colors
                                              .blue), // 临时替换 SmartAssetImage
                                    ),
                                  ),
                                ),
                              // 上层：半透明面板
                              Container(
                                color: config.themeColors.background
                                    .withOpacity(0.85),
                                child: Column(
                                  children: [
                                    _buildHeader(uiScale, textScale, config),
                                    Expanded(
                                      child: _buildContent(
                                          uiScale, textScale, config),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // 调试面板覆盖层
        if (_showDebugPanel)
          DebugPanelDialog(
            onClose: () => setState(() => _showDebugPanel = false),
          ),
      ],
    );
  }

  Widget _buildHeader(
      double uiScale, double textScale, SakiEngineConfig config) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 12 * uiScale,
        vertical: 12 * uiScale,
      ),
      decoration: BoxDecoration(
        color: config.themeColors.primary.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(
            color: config.themeColors.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '开发者面板',
              style: config.reviewTitleTextStyle.copyWith(
                fontSize:
                    (config.reviewTitleTextStyle.fontSize! - 2) * textScale,
                color: config.themeColors.primary,
                letterSpacing: 1.0,
              ),
            ),
          ),
          CommonCloseButton(
            scale: uiScale * 0.8,
            onClose: _handleClose,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      double uiScale, double textScale, SakiEngineConfig config) {
    return Padding(
      padding: EdgeInsets.all(12 * uiScale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 功能按钮
          _buildStyledButton(
            text: _showScriptPreview ? '隐藏脚本预览' : '脚本预览',
            onPressed: () {
              setState(() {
                _showScriptPreview = !_showScriptPreview;
              });
              if (_showScriptPreview) {
                _loadCurrentScript();
              }
            },
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),

          SizedBox(height: 8 * uiScale),

          // 调试面板按钮
          _buildStyledButton(
            text: '调试面板',
            onPressed: () {
              setState(() {
                _showDebugPanel = true;
              });
            },
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),

          SizedBox(height: 8 * uiScale),

          // 清除已读状态按钮
          _buildStyledButton(
            text: '清除已读状态',
            onPressed: _clearReadStatus,
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),

          SizedBox(height: 8 * uiScale),

          // 浏览文件按钮
          _buildStyledButton(
            text: '浏览脚本文件',
            onPressed: _browseAndLoadScript,
            config: config,
            uiScale: uiScale,
            textScale: textScale,
          ),

          // 脚本预览区域
          if (_showScriptPreview) ...[
            SizedBox(height: 12 * uiScale),
            Expanded(
              child: _buildScriptPreview(uiScale, textScale, config),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStyledButton({
    required String text,
    required VoidCallback onPressed,
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(config.baseWindowBorder),
        gradient: LinearGradient(
          colors: [
            config.themeColors.primary.withOpacity(0.8),
            config.themeColors.primary.withOpacity(0.6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: config.themeColors.primary.withOpacity(0.3),
            blurRadius: 4 * uiScale,
            offset: Offset(0, 2 * uiScale),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(config.baseWindowBorder),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: 8 * uiScale,
              horizontal: 16 * uiScale,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: config.reviewTitleTextStyle.copyWith(
                fontSize:
                    (config.reviewTitleTextStyle.fontSize! - 4) * textScale,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLineNumbers(double uiScale, double textScale) {
    final lines = _scriptController.text.split('\n');
    final lineCount = lines.length;

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 12 * uiScale,
        horizontal: 8 * uiScale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 1; i <= lineCount; i++)
            Container(
              height: 21 * textScale, // 与文字行高匹配
              alignment: Alignment.centerRight,
              child: Text(
                '$i',
                style: TextStyle(
                  color: const Color(0xFF858585), // 行号颜色
                  fontSize: 12 * textScale,
                  fontFamily: 'Courier New',
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextSpan _buildHighlightedText(String text, double textScale) {
    final lines = text.split('\n');
    final spans = <TextSpan>[];

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final lineSpans = <TextSpan>[];

      if (line.trim().startsWith('//')) {
        // 注释行 - 绿色
        lineSpans.add(TextSpan(
          text: line,
          style: TextStyle(
            color: const Color(0xFF6A9955),
            fontSize: 14 * textScale,
            fontFamily: 'Courier New',
          ),
        ));
      } else if (line.trim().startsWith('[') && line.trim().endsWith(']')) {
        // 标签行 - 蓝色
        lineSpans.add(TextSpan(
          text: line,
          style: TextStyle(
            color: const Color(0xFF569CD6),
            fontSize: 14 * textScale,
            fontFamily: 'Courier New',
          ),
        ));
      } else if (line.trim().startsWith('"') && line.trim().endsWith('"')) {
        // 对话文本 - 浅绿色
        lineSpans.add(TextSpan(
          text: line,
          style: TextStyle(
            color: const Color(0xFFCE9178),
            fontSize: 14 * textScale,
            fontFamily: 'Courier New',
          ),
        ));
      } else if (RegExp(r'^(scene|show|hide|nvlm|endnvlm|music|sound|fx)\s')
          .hasMatch(line.trim())) {
        // 命令关键词 - 紫色
        lineSpans.add(TextSpan(
          text: line,
          style: TextStyle(
            color: const Color(0xFFC586C0),
            fontSize: 14 * textScale,
            fontFamily: 'Courier New',
          ),
        ));
      } else {
        // 普通文本 - 默认颜色
        lineSpans.add(TextSpan(
          text: line,
          style: TextStyle(
            color: const Color(0xFFD4D4D4),
            fontSize: 14 * textScale,
            fontFamily: 'Courier New',
          ),
        ));
      }

      spans.addAll(lineSpans);
      if (lineIndex < lines.length - 1) {
        spans.add(TextSpan(
          text: '\n',
          style: TextStyle(
            fontSize: 14 * textScale,
            fontFamily: 'Courier New',
          ),
        ));
      }
    }

    return TextSpan(children: spans);
  }

  Widget _buildScriptPreview(
      double uiScale, double textScale, SakiEngineConfig config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 脚本路径显示
        Container(
          padding: EdgeInsets.all(8 * uiScale),
          decoration: BoxDecoration(
            color: config.themeColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(config.baseWindowBorder),
            border: Border.all(
              color: config.themeColors.primary.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            _currentScriptPath.isNotEmpty
                ? _currentScriptPath.split('/').last
                : '无脚本文件',
            style: config.reviewTitleTextStyle.copyWith(
              fontSize: (config.reviewTitleTextStyle.fontSize! - 6) * textScale,
              color: config.themeColors.primary.withOpacity(0.8),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        SizedBox(height: 8 * uiScale),

        // 脚本内容编辑器
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E), // VS Code深色背景
              borderRadius: BorderRadius.circular(config.baseWindowBorder),
              border: Border.all(
                color: const Color(0xFF3E3E42), // 深色边框
                width: 1,
              ),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.vertical,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 行号区域
                  Container(
                    width: 50 * uiScale,
                    decoration: const BoxDecoration(
                      color: Color(0xFF252526), // 行号背景
                      border: Border(
                        right: BorderSide(
                          color: Color(0xFF3E3E42),
                          width: 1,
                        ),
                      ),
                    ),
                    child: _buildLineNumbers(uiScale, textScale),
                  ),
                  // 代码编辑区域
                  Expanded(
                    child: TextField(
                      controller: _scriptController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        color: const Color(0xFFD4D4D4), // 浅灰色文字
                        fontSize: 14 * textScale,
                        fontFamily: 'Courier New',
                        height: 1.5,
                        letterSpacing: 0.5,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12 * uiScale),
                        hintText: '脚本内容...',
                        hintStyle: TextStyle(
                          color: const Color(0xFF6A9955), // 绿色注释色
                          fontSize: 14 * textScale,
                          fontFamily: 'Courier New',
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        // 实时更新行号
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SizedBox(height: 8 * uiScale),

        // 操作按钮
        _buildActionButton(
          text: '保存并重载',
          onPressed: _saveAndReloadScript,
          color: Colors.green,
          config: config,
          uiScale: uiScale,
          textScale: textScale,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String text,
    required VoidCallback onPressed,
    required Color color,
    required SakiEngineConfig config,
    required double uiScale,
    required double textScale,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(config.baseWindowBorder),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.8),
            color.withOpacity(0.6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 4 * uiScale,
            offset: Offset(0, 2 * uiScale),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(config.baseWindowBorder),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: 6 * uiScale,
              horizontal: 12 * uiScale,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: config.reviewTitleTextStyle.copyWith(
                fontSize:
                    (config.reviewTitleTextStyle.fontSize! - 6) * textScale,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

class _CloseAction extends Action<_CloseIntent> {
  final VoidCallback onClose;

  _CloseAction(this.onClose);

  @override
  Object? invoke(_CloseIntent intent) {
    onClose();
    return null;
  }
}
