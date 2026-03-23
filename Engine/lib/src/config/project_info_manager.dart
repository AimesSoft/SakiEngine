import 'dart:io';

import 'package:sakiengine/src/config/game_path_resolver.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sakiengine/src/config/runtime_project_config.dart';

class ProjectInfoManager {
  static final ProjectInfoManager _instance = ProjectInfoManager._internal();
  factory ProjectInfoManager() => _instance;
  ProjectInfoManager._internal();

  String? _cachedProjectName;
  String? _cachedAppName;

  // 检查是否应该从外部加载资源（仅桌面平台的Debug模式）
  static bool _shouldLoadFromExternal() {
    return GamePathResolver.shouldUseFileSystemAssets;
  }

  /// 获取当前项目名称（文件夹名）
  Future<String> getProjectName() async {
    if (_cachedProjectName != null) {
      return _cachedProjectName!;
    }

    try {
      final runtimeConfig = RuntimeProjectConfigStore().config;
      if (runtimeConfig.projectName != null) {
        _cachedProjectName = runtimeConfig.projectName!;
        return _cachedProjectName!;
      }

      if (runtimeConfig.gamePath != null) {
        _cachedProjectName = p.basename(runtimeConfig.gamePath!);
        return _cachedProjectName!;
      }

      final resolvedGamePath = await GamePathResolver.resolveGamePath();
      if (resolvedGamePath != null && resolvedGamePath.isNotEmpty) {
        _cachedProjectName = p.basename(resolvedGamePath);
        return _cachedProjectName!;
      }

      final resolvedProjectName = await GamePathResolver.resolveProjectName();
      if (resolvedProjectName != null && resolvedProjectName.isNotEmpty) {
        _cachedProjectName = resolvedProjectName;
        return _cachedProjectName!;
      }

      // 从assets读取default_game.txt
      final assetContent = await _loadDefaultGameNameFromAssets();
      final projectName = assetContent.trim();

      if (projectName.isEmpty) {
        throw Exception('Project name is empty in default_game.txt');
      }

      _cachedProjectName = projectName;
      return _cachedProjectName!;
    } catch (e) {
      if (_shouldLoadFromExternal()) {
        print('Error getting project name: $e');
      }
      // 如果无法获取项目名称，使用默认值
      _cachedProjectName = 'SakiEngine';
      return _cachedProjectName!;
    }
  }

  /// 获取应用显示名称（从game_config.txt读取）
  Future<String> getAppName() async {
    if (_cachedAppName != null) {
      return _cachedAppName!;
    }

    try {
      final runtimeConfig = RuntimeProjectConfigStore().config;
      if (runtimeConfig.appName != null) {
        _cachedAppName = runtimeConfig.appName!;
        return _cachedAppName!;
      }

      // 优先尝试从game_config.txt获取应用名称
      String gamePath = '';

      if (runtimeConfig.gamePath != null) {
        gamePath = runtimeConfig.gamePath!;
      }

      if (gamePath.isEmpty) {
        final resolvedPath = await GamePathResolver.resolveGamePath();
        if (resolvedPath != null && resolvedPath.isNotEmpty) {
          gamePath = resolvedPath;
        }
      }

      if (gamePath.isEmpty) {
        final projectName = await getProjectName();
        if (projectName.isNotEmpty) {
          final localFallback =
              p.join(Directory.current.path, 'Game', projectName);
          if (await Directory(localFallback).exists()) {
            gamePath = localFallback;
          }
        }
      }

      if (gamePath.isNotEmpty && _shouldLoadFromExternal()) {
        final configFile = File(p.join(gamePath, 'game_config.txt'));
        if (await configFile.exists()) {
          final lines = await configFile.readAsLines();
          if (lines.isNotEmpty) {
            _cachedAppName = lines.first.trim();
            return _cachedAppName!;
          }
        }
      }

      // 如果无法从配置读取，使用项目名称
      _cachedAppName = await getProjectName();
      return _cachedAppName!;
    } catch (e) {
      if (_shouldLoadFromExternal()) {
        print('Error getting app name: $e');
      }
      // fallback到项目名称
      _cachedAppName = await getProjectName();
      return _cachedAppName!;
    }
  }

  /// 清除缓存（用于项目切换时）
  void clearCache() {
    _cachedProjectName = null;
    _cachedAppName = null;
    GamePathResolver.clearCache();
  }

  Future<String> _loadDefaultGameNameFromAssets() async {
    try {
      return await rootBundle.loadString('assets/default_game.txt');
    } catch (_) {
      return await rootBundle.loadString('default_game.txt');
    }
  }
}
