import 'dart:io' show Directory, File, FileMode, Platform, stderr;

import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/asset_manager.dart';
import 'package:sakiengine/src/game/game_script_localization.dart';
import 'package:sakiengine/src/sks_compiler/compiled_sks_bundle.dart';
import 'package:sakiengine/src/sks_compiler/compiled_sks_registry.dart';
import 'package:sakiengine/src/sks_parser/sks_ast.dart';
import 'package:sakiengine/src/sks_parser/sks_parser.dart';

class ScriptMerger {
  static const bool _forceScriptDiagnostics =
      bool.fromEnvironment('SAKI_SCRIPT_DIAG', defaultValue: true);
  static final String _diagFilePath = (() {
    const configuredPath =
        String.fromEnvironment('SAKI_SCRIPT_DIAG_FILE', defaultValue: '');
    if (configuredPath.trim().isNotEmpty) {
      return configuredPath.trim();
    }
    return '${Directory.systemTemp.path}${Platform.pathSeparator}saki_script_diag.log';
  })();
  static const int _maxResolvePathDiagLines = 120;
  static int _resolvePathDiagCount = 0;

  final Map<String, ScriptNode> _loadedScripts = {};
  final Map<String, int> _fileStartIndices = {}; // 记录每个文件在合并脚本中的起始索引
  final Map<String, String> _globalLabelMap = {}; // label -> filename
  ScriptNode? _mergedScript;

  static bool _shouldScriptDiagnostics() {
    if (kEngineDebugMode) {
      return true;
    }
    return _forceScriptDiagnostics;
  }

  static void _scriptDiag(String message) {
    if (!_shouldScriptDiagnostics()) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final line = '[SAKI_SCRIPT_DIAG][$now] $message';
    stderr.writeln(line);
    try {
      File(_diagFilePath).writeAsStringSync(
        '$line\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static void _scriptDiagResolvePath(String message) {
    if (_resolvePathDiagCount >= _maxResolvePathDiagLines) {
      return;
    }
    _resolvePathDiagCount++;
    _scriptDiag(message);
  }

  /// 构建全局标签映射，扫描所有脚本文件
  Future<void> _buildGlobalLabelMap() async {
    _globalLabelMap.clear();
    _loadedScripts.clear();
    _resolvePathDiagCount = 0;

    final precompiledBundle = CompiledSksRegistry.instance.activeBundle;
    _scriptDiag(
      '构建标签映射开始: precompiled=${precompiledBundle != null}, '
      'hasLabelScripts=${precompiledBundle?.hasLabelScripts ?? false}, '
      'diagFile=$_diagFilePath',
    );
    if (precompiledBundle != null && precompiledBundle.hasLabelScripts) {
      _loadFromCompiledBundle(precompiledBundle);
      _scriptDiag(
        '预编译加载完成: loadedScripts=${_loadedScripts.length}, '
        'labels=${_globalLabelMap.length}',
      );
      if (_loadedScripts.isNotEmpty) {
        if (!_loadedScripts.containsKey('start')) {
          _scriptDiag(
              '预编译脚本缺少 start.sks，当前脚本: ${_loadedScripts.keys.toList()}');
          throw StateError(
            '[ScriptMerger] 预编译脚本缺少 start.sks，无法继续构建脚本图',
          );
        }
        _scriptDiag(
            '使用预编译脚本: files=${_loadedScripts.length}, labels=${_globalLabelMap.length}');
        return;
      }
      _scriptDiag('预编译脚本为空，无法构建脚本图');
      throw StateError('[ScriptMerger] 预编译脚本为空，无法继续构建脚本图');
    }

    try {
      // 获取所有 .sks 文件
      final scriptFiles =
          await AssetManager().listAssets('assets/GameScript/labels/', '.sks');

      for (final fileName in scriptFiles) {
        final fileNameWithoutExt = fileName.replaceAll('.sks', '');
        try {
          final scriptContent = await AssetManager()
              .loadString('assets/GameScript/labels/$fileName');
          final script = SksParser().parse(scriptContent);
          _loadedScripts[fileNameWithoutExt] = script;
          _collectLabels(fileNameWithoutExt, script);
        } catch (e) {
          _scriptDiag('文件系统脚本加载失败: $fileName, error=$e');
        }
      }
      _scriptDiag(
        '文件系统脚本加载完成: scripts=${_loadedScripts.length}, '
        'labels=${_globalLabelMap.length}',
      );
    } catch (e) {
      _scriptDiag('构建全局标签映射失败: $e');
    }
  }

  void _loadFromCompiledBundle(CompiledSksBundle bundle) {
    final scriptFiles = _collectLabelFileNames(bundle);
    _scriptDiag(
      '扫描预编译标签文件: bundleLabelAssets=${bundle.labelAssetPaths.length}, '
      'uniqueLabelFiles=${scriptFiles.length}',
    );

    var unresolvedCount = 0;
    for (final fileName in scriptFiles) {
      final script = _resolveLocalizedLabelScript(bundle, fileName);
      if (script == null) {
        unresolvedCount++;
        continue;
      }

      final fileNameWithoutExt = fileName.replaceAll('.sks', '');
      _loadedScripts[fileNameWithoutExt] = script;
      _collectLabels(fileNameWithoutExt, script);
    }
    if (unresolvedCount > 0) {
      _scriptDiag('预编译标签解析缺失: unresolved=$unresolvedCount');
    }
  }

  List<String> _collectLabelFileNames(CompiledSksBundle bundle) {
    final fileNames = <String>[];
    final seen = <String>{};

    for (final rawAssetPath in bundle.labelAssetPaths) {
      final assetPath = CompiledSksBundle.normalizeAssetPath(rawAssetPath);
      if (!assetPath.startsWith('assets/GameScript') ||
          !assetPath.endsWith('.sks')) {
        continue;
      }

      final markerIndex = assetPath.indexOf('/labels/');
      if (markerIndex < 0) {
        continue;
      }

      final fileName = assetPath.substring(markerIndex + '/labels/'.length);
      if (fileName.isEmpty || fileName.contains('/')) {
        continue;
      }

      if (seen.add(fileName)) {
        fileNames.add(fileName);
      }
    }

    fileNames.sort();
    return fileNames;
  }

  ScriptNode? _resolveLocalizedLabelScript(
    CompiledSksBundle bundle,
    String fileName,
  ) {
    final candidateDirs = GameScriptLocalization.candidateDirectories();
    for (final dir in candidateDirs) {
      final assetPath = 'assets/$dir/labels/$fileName';
      final script = bundle.loadLabelScriptByAssetPath(assetPath);
      if (script != null) {
        _scriptDiagResolvePath('标签解析命中(首选目录): $fileName <- $assetPath');
        return script;
      }
    }

    // 发布模式下如果当前语言目录不完整，回退到任意可用语言目录的同名脚本。
    final fallbackAssetPaths = <String>[];
    for (final rawAssetPath in bundle.labelAssetPaths) {
      final assetPath = CompiledSksBundle.normalizeAssetPath(rawAssetPath);
      if (!assetPath.startsWith('assets/GameScript')) {
        continue;
      }
      if (assetPath.endsWith('/labels/$fileName')) {
        fallbackAssetPaths.add(assetPath);
      }
    }

    fallbackAssetPaths.sort();
    for (final assetPath in fallbackAssetPaths) {
      final script = bundle.loadLabelScriptByAssetPath(assetPath);
      if (script != null) {
        _scriptDiagResolvePath('标签解析命中(回退目录): $fileName <- $assetPath');
        return script;
      }
    }
    _scriptDiag('标签解析失败: $fileName');
    return null;
  }

  void _collectLabels(String fileNameWithoutExt, ScriptNode script) {
    for (final node in script.children) {
      if (node is LabelNode) {
        _globalLabelMap[node.name] = fileNameWithoutExt;
        if (kEngineDebugMode) {
          //print('[ScriptMerger] 发现标签: ${node.name} 在文件 $fileNameWithoutExt 中');
        }
      }
    }
  }

  /// 合并所有脚本文件成一个连续的脚本
  Future<ScriptNode> getMergedScript() async {
    if (_mergedScript != null) {
      _scriptDiag(
        '复用已合并脚本缓存: nodes=${_mergedScript!.children.length}, '
        'files=${_fileStartIndices.length}',
      );
      return _mergedScript!;
    }

    await _buildGlobalLabelMap();

    final mergedChildren = <SksNode>[];
    _fileStartIndices.clear();

    // 从 start 文件开始，按照 jump 顺序拼接
    final processedFiles = <String>{};
    await _mergeFileRecursively('start', mergedChildren, processedFiles);

    _mergedScript = ScriptNode(mergedChildren);
    _scriptDiag(
      '合并脚本完成: mergedNodes=${mergedChildren.length}, '
      'processedFiles=${processedFiles.length}, '
      'fileStartIndices=${_fileStartIndices.length}',
    );
    return _mergedScript!;
  }

  /// 递归合并文件，按照 jump 顺序
  Future<void> _mergeFileRecursively(String fileName,
      List<SksNode> mergedChildren, Set<String> processedFiles) async {
    if (processedFiles.contains(fileName)) {
      _scriptDiag('递归跳过(已处理): $fileName');
      return;
    }
    if (!_loadedScripts.containsKey(fileName)) {
      _scriptDiag(
        '递归跳过(缺文件): $fileName, loadedScripts=${_loadedScripts.length}',
      );
      return;
    }

    processedFiles.add(fileName);
    final script = _loadedScripts[fileName]!;
    _fileStartIndices[fileName] = mergedChildren.length;

    // 添加文件开始标记
    mergedChildren.add(CommentNode('=== 文件: $fileName ==='));

    // 收集当前文件中的所有 jump 目标
    final jumpTargets = <String>[];

    for (final node in script.children) {
      // 先添加当前节点
      mergedChildren.add(_cloneNode(node));

      // 如果是 jump 节点，记录目标但不立即处理
      if (node is JumpNode) {
        final targetLabel = node.targetLabel;
        if (_globalLabelMap.containsKey(targetLabel)) {
          final targetFile = _globalLabelMap[targetLabel]!;
          if (!jumpTargets.contains(targetFile) && targetFile != fileName) {
            jumpTargets.add(targetFile);
          }
        }
      }

      // 如果是 menu 节点，也要处理选项中的目标标签
      if (node is MenuNode) {
        for (final choice in node.choices) {
          final targetLabel = choice.targetLabel;
          if (_globalLabelMap.containsKey(targetLabel)) {
            final targetFile = _globalLabelMap[targetLabel]!;
            if (!jumpTargets.contains(targetFile) && targetFile != fileName) {
              jumpTargets.add(targetFile);
            }
          }
        }
      }
    }

    // 添加文件结束标记
    mergedChildren.add(CommentNode('=== 文件 $fileName 结束 ==='));

    // 递归处理所有被 jump 的文件
    for (final targetFile in jumpTargets) {
      await _mergeFileRecursively(targetFile, mergedChildren, processedFiles);
    }
  }

  /// 递归查找脚本中的所有跳转目标（保留用于其他可能的用途）
  void _findJumpTargets(ScriptNode script, Set<String> targets) {
    for (final node in script.children) {
      if (node is JumpNode) {
        targets.add(node.targetLabel);
      } else if (node is MenuNode) {
        for (final option in node.choices) {
          targets.add(option.targetLabel);
        }
      }
    }
  }

  /// 深拷贝节点
  SksNode _cloneNode(SksNode node) {
    // 这里简化实现，实际中可能需要更完整的克隆逻辑
    return node;
  }

  /// 将节点转换为可读的字符串（调试用）
  String _nodeToString(SksNode node) {
    if (node is CommentNode) {
      return 'Comment: ${node.comment}';
    } else if (node is LabelNode) {
      return 'Label: ${node.name}';
    } else if (node is SayNode) {
      final speaker = node.character != null ? '${node.character}: ' : '';
      return 'Say: $speaker"${node.dialogue}"';
    } else if (node is BackgroundNode) {
      return 'Background: ${node.background}';
    } else if (node is ShowNode) {
      return 'Show: ${node.character} (${node.pose ?? 'default'}, ${node.expression ?? 'default'})';
    } else if (node is CgNode) {
      return 'CG: ${node.character} (${node.pose ?? 'default'}, ${node.expression ?? 'default'})';
    } else if (node is HideNode) {
      return 'Hide: ${node.character}';
    } else if (node is JumpNode) {
      return 'Jump: ${node.targetLabel}';
    } else if (node is MenuNode) {
      return 'Menu: ${node.choices.length} choices';
    } else if (node is ReturnNode) {
      return 'Return';
    } else if (node is NvlNode) {
      return 'NVL: Start';
    } else if (node is NvlMovieNode) {
      return 'NVLM: Start';
    } else if (node is EndNvlNode) {
      return 'NVL: End';
    } else if (node is EndNvlMovieNode) {
      return 'NVLM: End';
    } else {
      return 'Unknown: ${node.runtimeType}';
    }
  }

  /// 获取指定文件在合并脚本中的起始索引
  int? getFileStartIndex(String fileName) {
    return _fileStartIndices[fileName];
  }

  /// 获取所有文件的起始索引映射
  Map<String, int> get fileStartIndices => Map.unmodifiable(_fileStartIndices);

  /// 根据合并脚本中的索引找到对应的原始文件名
  String? getFileNameByIndex(int index) {
    String? result;
    int maxStartIndex = -1;

    for (final entry in _fileStartIndices.entries) {
      if (entry.value <= index && entry.value > maxStartIndex) {
        maxStartIndex = entry.value;
        result = entry.key;
      }
    }

    return result;
  }

  /// 清理缓存，强制重新合并
  void clearCache() {
    _mergedScript = null;
    _loadedScripts.clear();
    _fileStartIndices.clear();
    _globalLabelMap.clear();
  }
}
