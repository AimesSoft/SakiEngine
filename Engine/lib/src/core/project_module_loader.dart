import 'package:flutter/foundation.dart';
import 'package:sakiengine/src/core/game_module.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';

// 自动模块发现系统 - 无需手动注册

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
    if (kDebugMode) {
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
        
        if (kDebugMode) {
          //print('[ProjectModuleLoader] 加载已注册模块: $projectName');
        }
        
        return _currentModule!;
      } catch (e) {
        if (kDebugMode) {
          //print('[ProjectModuleLoader] 加载已注册模块失败: $projectName, 错误: $e');
        }
      }
    }

    // 回退到默认模块
    _currentModule = DefaultGameModule();
    await _currentModule!.initialize();
    
    if (kDebugMode) {
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
}

/// 全局模块加载器实例
final moduleLoader = ProjectModuleLoader();
