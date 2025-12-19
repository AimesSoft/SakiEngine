import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/game/game_script_localization.dart';

class AssetManager {
  static final AssetManager _instance = AssetManager._internal();
  factory AssetManager() => _instance;
  AssetManager._internal() {
    // Print the CWD at initialization
    if (_shouldLoadFromExternal()) {
      print("AssetManager CWD: ${Directory.current.path}");
      print("Game path from environment: $_debugRoot");
    }
  }

  Map<String, dynamic>? _assetManifest;
  final Map<String, String> _imageCache = {};

  // 检查是否应该从外部加载资源（仅桌面平台的Debug模式）
  static bool _shouldLoadFromExternal() {
    if (!kDebugMode) return false;
    // 只在桌面平台从外部加载
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // 获取游戏路径，从dart-define或环境变量获取
  static String get _debugRoot {
    const fromDefine =
        String.fromEnvironment('SAKI_GAME_PATH', defaultValue: '');
    if (fromDefine.isNotEmpty) return fromDefine;

    final fromEnv = Platform.environment['SAKI_GAME_PATH'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    return '';
  }

  // 获取游戏路径，优先使用环境变量，如果没有则从assets读取default_game.txt
  static Future<String> _getGamePath() async {
    // 如果环境变量已设置，直接使用
    if (_debugRoot.isNotEmpty) {
      return _debugRoot;
    }

    try {
      // 从assets读取default_game.txt
      final assetContent =
          await rootBundle.loadString('assets/default_game.txt');
      final defaultGame = assetContent.trim();

      if (defaultGame.isEmpty) {
        throw Exception('default_game.txt is empty');
      }

      final gamePath = p.join(Directory.current.path, 'Game', defaultGame);
      if (_shouldLoadFromExternal()) {
        print("Using game from assets: $defaultGame");
        print("Game path resolved to: $gamePath");
      }

      return gamePath;
    } catch (e) {
      throw Exception('Failed to load default_game.txt from assets: $e');
    }
  }

  Future<String> loadString(String path) async {
    final candidates = GameScriptLocalization.resolveAssetPaths(path);
    Object? lastError;

    if (_shouldLoadFromExternal()) {
      final gamePath = await _getGamePath();
      if (gamePath.isEmpty) {
        throw Exception(
            'Game path is not defined. Please set SAKI_GAME_PATH environment variable or create default_game.txt');
      }

      for (final candidate in candidates) {
        final assetPath = GameScriptLocalization.stripAssetsPrefix(candidate);
        final fileSystemPath = p.normalize(p.join(gamePath, assetPath));

        try {
          return await File(fileSystemPath).readAsString();
        } catch (e) {
          lastError = e;
          if (_shouldLoadFromExternal()) {
            print(
                '[AssetManager] Failed to load $fileSystemPath, trying fallback if available. Error: $e');
          }
        }
      }

      throw Exception(
          'Failed to load asset from file system. Tried: ${candidates.join(', ')}. Last error: $lastError');
    } else {
      for (final candidate in candidates) {
        try {
          return await rootBundle.loadString(candidate, cache: false);
        } catch (e) {
          lastError = e;
        }
      }

      throw Exception(
          'Failed to load asset from bundle. Tried: ${candidates.join(', ')}. Last error: $lastError');
    }
  }

  Map<String, dynamic> listToManifestMap(List<String> assets) {
    final Map<String, dynamic> manifest = {};

    for (final path in assets) {
      manifest[path] = [path];
    }

    return manifest;
  }

  Future<void> _loadManifest() async {
    if (_assetManifest != null) return;
    // final manifestJson = await rootBundle.loadString('AssetManifest.json');
    // _assetManifest = json.decode(manifestJson);
    // https://docs.flutter.dev/release/breaking-changes/asset-manifest-dot-json
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    _assetManifest = listToManifestMap(assetManifest.listAssets());
  }

  Future<List<String>> listAssets(String directory, String extension) async {
    final assets = <String>[];
    final seen = <String>{};
    final candidates =
        GameScriptLocalization.resolveAssetDirectories(directory);
    final resolvedDirectories = <String>[];

    if (_shouldLoadFromExternal()) {
      final gamePath = await _getGamePath();
      if (gamePath.isEmpty) {
        print('Game path is not set, cannot list assets from file system.');
        return assets;
      }

      for (final candidate in candidates) {
        final assetPath = GameScriptLocalization.stripAssetsPrefix(candidate);
        final dirPath = p.join(gamePath, assetPath);
        final dir = Directory(dirPath);
        final currentAssets = <String>[];

        if (await dir.exists()) {
          await for (final file in dir.list()) {
            if (file is File && file.path.endsWith(extension)) {
              currentAssets.add(p.basename(file.path));
            }
          }
        }

        if (currentAssets.isNotEmpty) {
          resolvedDirectories.add(candidate);
          for (final fileName in currentAssets) {
            if (seen.add(fileName)) {
              assets.add(fileName);
            }
          }
        }
      }
    } else {
      await _loadManifest();
      if (_assetManifest != null) {
        for (final candidate in candidates) {
          final currentAssets = <String>[];

          for (final assetPath in _assetManifest!.keys) {
            if (assetPath.startsWith(candidate) &&
                assetPath.endsWith(extension)) {
              currentAssets.add(p.basename(assetPath));
            }
          }

          if (currentAssets.isNotEmpty) {
            resolvedDirectories.add(candidate);
            for (final fileName in currentAssets) {
              if (seen.add(fileName)) {
                assets.add(fileName);
              }
            }
          }
        }
      }
    }
    return assets;
  }

  Future<String?> findAsset(String name) async {
    if (_imageCache.containsKey(name)) {
      return _imageCache[name];
    }

    if (_shouldLoadFromExternal()) {
      return _findAssetInFileSystem(name);
    } else {
      return _findAssetInBundle(name);
    }
  }

  Future<String?> _findAssetInBundle(String name) async {
    await _loadManifest();
    if (_assetManifest == null) {
      print("AssetManifest is null - cannot find assets");
      return null;
    }

    final imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.avif'
    ];
    final videoExtensions = [
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.webm'
    ]; // 新增：视频扩展名
    final supportedExtensions = [
      ...imageExtensions,
      ...videoExtensions
    ]; // 合并支持的扩展名

    // 从查询名称中提取文件名，例如 "backgrounds/sky" -> "sky"
    final targetFileName = name.split('/').last;

    // 提取路径部分，例如 "backgrounds/sky" -> "backgrounds"
    final pathParts = name.split('/');
    final targetPath = pathParts.length > 1
        ? pathParts.sublist(0, pathParts.length - 1).join('/')
        : '';

    // 检测是否包含cg关键词（不区分大小写）
    final nameToCheck = name.toLowerCase();
    final fileNameToCheck = targetFileName.toLowerCase();
    final isCgRelated =
        nameToCheck.contains('cg') || fileNameToCheck.contains('cg');

    // 如果检测到cg关键词，优先在cg路径下搜索（支持递归子文件夹）
    if (isCgRelated) {
      for (final key in _assetManifest!.keys) {
        final keyParts = key.split('/');
        final keyFileName = keyParts.last;
        final keyFileNameWithoutExt = keyFileName.split('.').first;

        // 检查文件名是否匹配且路径包含cg（支持cg的任意子文件夹）
        if (keyFileNameWithoutExt.toLowerCase() ==
            targetFileName.toLowerCase()) {
          final keyPath = key.toLowerCase();
          // 更精确的cg路径检测：支持 /cg/ 或 /cg/任意子目录/
          if (keyPath.contains('/cg/') ||
              keyPath.startsWith('cg/') ||
              keyPath.contains('assets/images/cg/')) {
            _imageCache[name] = key;
            return key;
          }
        }
      }
    }

    // 1. 精确匹配：路径和文件名都要匹配
    for (final key in _assetManifest!.keys) {
      final keyParts = key.split('/');
      final keyFileName = keyParts.last;
      final keyFileNameWithoutExt = keyFileName.split('.').first;

      // 检查文件名是否匹配
      if (keyFileNameWithoutExt.toLowerCase() == targetFileName.toLowerCase()) {
        // 如果查询有路径要求，检查路径是否匹配
        if (targetPath.isNotEmpty) {
          final keyPath = key.toLowerCase();
          if (keyPath.contains('/${targetPath.toLowerCase()}/') ||
              keyPath.contains('${targetPath.toLowerCase()}/')) {
            _imageCache[name] = key;
            //print("Found asset in bundle (path + name match): $name -> $key");
            return key;
          }
        } else {
          // 没有路径要求，直接匹配文件名
          _imageCache[name] = key;
          //print("Found asset in bundle (name match): $name -> $key");
          return key;
        }
      }
    }

    // 2. 宽松匹配：只匹配文件名，忽略路径
    for (final key in _assetManifest!.keys) {
      final keyParts = key.split('/');
      final keyFileName = keyParts.last;
      final keyFileNameWithoutExt = keyFileName.split('.').first;

      if (keyFileNameWithoutExt.toLowerCase() == targetFileName.toLowerCase()) {
        _imageCache[name] = key;
        //print("Found asset in bundle (fallback name match): $name -> $key");
        return key;
      }
    }
    return null;
  }

  Future<String?> _findAssetInFileSystem(String name) async {
    final gamePath = await _getGamePath();
    if (gamePath.isEmpty) {
      print("Game path is not set, cannot find assets in file system.");
      return null;
    }

    // 从资源名中提取文件名用于搜索，例如 "backgrounds/bg-school" -> "bg-school"
    final fileNameToSearch = name.split('/').last;

    final searchBase = p.join(gamePath, 'Assets', 'images');

    // 检测是否包含cg关键词（不区分大小写）
    final nameToCheck = name.toLowerCase();
    final fileNameToCheck = fileNameToSearch.toLowerCase();
    final isCgRelated =
        nameToCheck.contains('cg') || fileNameToCheck.contains('cg');

    // 如果检测到cg关键词，优先从cg文件夹搜索
    final searchPaths = <String>[];
    if (isCgRelated) {
      searchPaths.add(p.join(searchBase, 'cg'));
    }

    // 添加其他常规搜索路径
    searchPaths.addAll([
      p.join(searchBase, 'backgrounds'),
      p.join(searchBase, 'characters'),
      p.join(searchBase, 'items'),
      p.join(gamePath, 'Assets', 'gui'),
      p.join(gamePath, 'Assets', 'movies'), // 新增：视频文件搜索路径
    ]);

    for (final dirPath in searchPaths) {
      final directory = Directory(dirPath);
      if (await directory.exists()) {
        await for (final file in directory.list(recursive: true)) {
          if (file is File) {
            final fileNameWithoutExt = p.basenameWithoutExtension(file.path);
            if (fileNameWithoutExt.toLowerCase() ==
                fileNameToSearch.toLowerCase()) {
              // Debug模式下直接返回绝对路径，用于FileImage
              final assetPath = file.path.replaceAll('\\', '/');
              _imageCache[name] = assetPath;
              return assetPath;
            }
          }
        }
      }
    }

    return null;
  }

  /// 递归扫描指定角色ID的所有可用图层文件
  /// 使用与findAsset相同的递归搜索逻辑
  static Future<List<String>> getAvailableCharacterLayersRecursive(
      String characterId) async {
    final availableLayers = <String>[];

    try {
      final gamePath = await _getGamePath();
      if (gamePath.isEmpty) {
        return availableLayers;
      }

      final searchBase = p.join(gamePath, 'Assets', 'images');
      final charactersDir = Directory(p.join(searchBase, 'characters'));

      if (!await charactersDir.exists()) {
        return availableLayers;
      }

      final prefix = '$characterId-';
      final imageExtensions = ['.png', '.jpg', '.jpeg', '.webp', '.avif'];

      // 使用递归搜索，和findAsset一样
      await for (final file in charactersDir.list(recursive: true)) {
        if (file is File) {
          final fileName = p.basename(file.path);
          final fileNameWithoutExt = p.basenameWithoutExtension(fileName);

          // 检查是否以指定角色ID开头且是图片文件
          if (fileNameWithoutExt.startsWith(prefix) &&
              imageExtensions
                  .any((ext) => fileName.toLowerCase().endsWith(ext))) {
            // 提取图层名称（去掉角色ID前缀）
            final layerName = fileNameWithoutExt.substring(prefix.length);
            if (layerName.isNotEmpty) {
              availableLayers.add(layerName);
            }
          }
        }
      }

      // 按字母顺序排序
      availableLayers.sort();
    } catch (e) {
      if (_shouldLoadFromExternal()) {
        print("AssetManager: 递归扫描角色图层出错 $characterId: $e");
      }
    }

    return availableLayers;
  }

  /// 扫描指定角色ID的所有可用图层文件
  /// 返回按字母顺序排序的文件名列表（不包含扩展名和角色ID前缀）
  static Future<List<String>> getAvailableCharacterLayers(
      String characterId) async {
    final availableLayers = <String>[];

    try {
      final gamePath = await _getGamePath();
      final charactersDir =
          Directory(p.join(gamePath, 'Assets', 'images', 'characters'));
      if (!await charactersDir.exists()) {
        return availableLayers;
      }

      final prefix = '$characterId-';
      final imageExtensions = ['.png', '.jpg', '.jpeg', '.webp', '.avif'];
      var fileCount = 0;
      await for (final file in charactersDir.list()) {
        if (file is File) {
          final fileName = p.basename(file.path);
          fileCount++;
          final fileNameWithoutExt = p.basenameWithoutExtension(fileName);

          // 检查是否以指定角色ID开头且是图片文件
          if (fileNameWithoutExt.startsWith(prefix) &&
              imageExtensions
                  .any((ext) => fileName.toLowerCase().endsWith(ext))) {
            // 提取图层名称（去掉角色ID前缀）
            final layerName = fileNameWithoutExt.substring(prefix.length);
            if (layerName.isNotEmpty) {
              availableLayers.add(layerName);
            }
          }
        }
      }
      // 按字母顺序排序
      availableLayers.sort();
    } catch (e) {
      if (_shouldLoadFromExternal()) {
        print("AssetManager: 扫描角色图层出错 $characterId: $e");
      }
    }

    return availableLayers;
  }

  /// 获取指定角色ID和图层级别的默认图层名称
  /// 返回该级别下按字母顺序第一个可用的图层
  static Future<String?> getDefaultLayerForLevel(
      String characterId, int layerLevel) async {
    final availableLayers = await getAvailableCharacterLayers(characterId);

    // 筛选出指定级别的图层
    final layersForLevel = availableLayers.where((layer) {
      // 解析图层级别
      int dashCount = 0;
      for (int i = 0; i < layer.length; i++) {
        if (layer[i] == '-') {
          dashCount++;
        } else {
          break;
        }
      }

      int currentLayerLevel;
      if (dashCount == 0) {
        currentLayerLevel = 1; // 无"-"，作为基础表情
      } else if (dashCount == 1) {
        currentLayerLevel = 1; // 单"-"，保持兼容
      } else {
        currentLayerLevel = dashCount; // 多"-"，按数量确定层级
      }

      return currentLayerLevel == layerLevel;
    }).toList();

    // 提取实际的图层名称（去掉前缀"-"）
    if (layersForLevel.isNotEmpty) {
      String firstLayer = layersForLevel.first;

      // 提取实际名称
      int dashCount = 0;
      for (int i = 0; i < firstLayer.length; i++) {
        if (firstLayer[i] == '-') {
          dashCount++;
        } else {
          break;
        }
      }

      return dashCount > 0 ? firstLayer.substring(dashCount) : firstLayer;
    }

    return null;
  }
}
