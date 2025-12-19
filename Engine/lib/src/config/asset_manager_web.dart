import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/game/game_script_localization.dart';

class AssetManager {
  static final AssetManager _instance = AssetManager._internal();
  factory AssetManager() => _instance;
  AssetManager._internal() {
    // Web平台不需要初始化日志
    if (kDebugMode) {
      print("AssetManager (Web): Using bundle assets only");
    }
  }

  Map<String, dynamic>? _assetManifest;
  final Map<String, String> _imageCache = {};

  // Web平台总是返回空字符串
  static String get _debugRoot => '';

  // Web平台总是返回空字符串，强制使用bundle模式
  static Future<String> _getGamePath() async => '';

  Future<String> loadString(String path) async {
    final candidates = GameScriptLocalization.resolveAssetPaths(path);
    Object? lastError;

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
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    _assetManifest = listToManifestMap(assetManifest.listAssets());
  }

  Future<List<String>> listAssets(String directory, String extension) async {
    final assets = <String>[];
    final seen = <String>{};
    final candidates =
        GameScriptLocalization.resolveAssetDirectories(directory);
    final resolvedDirectories = <String>[];

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
    return assets;
  }

  Future<String?> findAsset(String name) async {
    if (_imageCache.containsKey(name)) {
      return _imageCache[name];
    }

    // Web平台总是使用bundle搜索
    return _findAssetInBundle(name);
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
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    final supportedExtensions = [...imageExtensions, ...videoExtensions];

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

  /// Web平台返回空列表
  static Future<List<String>> getAvailableCharacterLayersRecursive(
      String characterId) async {
    return <String>[];
  }

  /// Web平台返回空列表
  static Future<List<String>> getAvailableCharacterLayers(
      String characterId) async {
    return <String>[];
  }

  /// Web平台返回null
  static Future<String?> getDefaultLayerForLevel(
      String characterId, int layerLevel) async {
    return null;
  }
}
