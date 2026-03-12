import 'dart:io';
import 'package:flutter/foundation.dart';
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
    if (!kDebugMode) return false;
    // 只在桌面平台从外部加载
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
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

      // 优先从环境变量获取游戏路径
      const fromDefine =
          String.fromEnvironment('SAKI_GAME_PATH', defaultValue: '');
      if (fromDefine.isNotEmpty) {
        _cachedProjectName = p.basename(fromDefine);
        return _cachedProjectName!;
      }

      final fromEnv = Platform.environment['SAKI_GAME_PATH'];
      if (fromEnv != null && fromEnv.isNotEmpty) {
        _cachedProjectName = p.basename(fromEnv);
        return _cachedProjectName!;
      }

      if (_shouldLoadFromExternal()) {
        final currentDir = Directory.current.path;
        final gameConfigFile = File(p.join(currentDir, 'game_config.txt'));
        if (await gameConfigFile.exists()) {
          _cachedProjectName = p.basename(currentDir);
          return _cachedProjectName!;
        }

        final localDefaultGameFile =
            File(p.join(currentDir, 'default_game.txt'));
        if (await localDefaultGameFile.exists()) {
          final defaultGame =
              (await localDefaultGameFile.readAsString()).trim();
          if (defaultGame.isNotEmpty) {
            _cachedProjectName = defaultGame;
            return _cachedProjectName!;
          }
        }
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

      // 获取游戏路径
      if (gamePath.isEmpty) {
        const fromDefine =
            String.fromEnvironment('SAKI_GAME_PATH', defaultValue: '');
        if (fromDefine.isNotEmpty) {
          gamePath = fromDefine;
        }
      }

      if (gamePath.isEmpty) {
        final fromEnv = Platform.environment['SAKI_GAME_PATH'];
        if (fromEnv != null && fromEnv.isNotEmpty) {
          gamePath = fromEnv;
        }
      }

      if (gamePath.isEmpty && _shouldLoadFromExternal()) {
        final currentDir = Directory.current.path;
        final gameConfigFile = File(p.join(currentDir, 'game_config.txt'));
        if (await gameConfigFile.exists()) {
          gamePath = currentDir;
        }
      }

      if (gamePath.isEmpty) {
        final assetContent = await _loadDefaultGameNameFromAssets();
        final projectName = assetContent.trim();
        if (projectName.isNotEmpty) {
          gamePath = p.join(Directory.current.path, 'Game', projectName);
        }
      }

      if (gamePath.isNotEmpty && _shouldLoadFromExternal()) {
        // 在桌面调试模式下，尝试从game_config.txt读取应用名称
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
  }

  Future<String> _loadDefaultGameNameFromAssets() async {
    try {
      return await rootBundle.loadString('assets/default_game.txt');
    } catch (_) {
      return await rootBundle.loadString('default_game.txt');
    }
  }
}
