import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/core/game_module.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';

// 显式模块注册系统：由游戏项目在入口处主动调用 registerProjectModule。

/// 项目模块工厂函数类型
typedef GameModuleFactory = GameModule Function();

/// 项目模块加载器 - 核心中转层
class ProjectModuleLoader {
  static final ProjectModuleLoader _instance = ProjectModuleLoader._internal();
  factory ProjectModuleLoader() => _instance;
  ProjectModuleLoader._internal();

  /// 注册的项目模块工厂
  final Map<String, GameModuleFactory> _registeredModules = {};

  /// 当前加载的模块
  GameModule? _currentModule;
  String? _currentProjectName;

  /// 注册项目模块
  /// [projectName] 项目名称（不区分大小写）
  /// [factory] 模块工厂函数
  void registerModule(String projectName, GameModuleFactory factory) {
    final normalizedName = projectName.toLowerCase();
    _registeredModules[normalizedName] = factory;
    if (kEngineDebugMode) {
      //print('[ProjectModuleLoader] 注册项目模块: $normalizedName');
    }
  }

  /// 获取当前项目的模块
  Future<GameModule> getCurrentModule() async {
    final projectName = await ProjectInfoManager().getProjectName();

    // 如果项目没有变化，返回缓存的模块
    if (_currentModule != null && _currentProjectName == projectName) {
      return _currentModule!;
    }

    // 清理之前的模块
    _currentModule = null;
    _currentProjectName = projectName;

    // 首先尝试从注册的模块加载
    final normalizedProjectName = projectName.toLowerCase();
    if (_registeredModules.containsKey(normalizedProjectName)) {
      try {
        _currentModule = _registeredModules[normalizedProjectName]!();
        await _currentModule!.initialize();

        if (kEngineDebugMode) {
          //print('[ProjectModuleLoader] 加载已注册模块: $projectName');
        }

        return _currentModule!;
      } catch (e) {
        if (kEngineDebugMode) {
          //print('[ProjectModuleLoader] 加载已注册模块失败: $projectName, 错误: $e');
        }
      }
    }

    // 回退到默认模块
    _currentModule = DefaultGameModule();
    await _currentModule!.initialize();

    if (kEngineDebugMode) {
      //print('[ProjectModuleLoader] 使用默认模块: $projectName');
    }

    return _currentModule!;
  }

  /// 重新加载模块（用于项目切换时）
  Future<void> reloadModule() async {
    _currentModule = null;
    _currentProjectName = null;
    ProjectInfoManager().clearCache();
  }

  /// 获取已注册的模块列表
  List<String> getRegisteredModules() {
    return _registeredModules.keys.toList();
  }

  /// 检查项目是否有自定义模块
  bool hasCustomModule(String projectName) {
    final normalizedName = projectName.toLowerCase();
    return _registeredModules.containsKey(normalizedName);
  }

  @visibleForTesting
  void resetForTest() {
    _registeredModules.clear();
    _currentModule = null;
    _currentProjectName = null;
  }
}

/// 全局模块加载器实例
final moduleLoader = ProjectModuleLoader();
