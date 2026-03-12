import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sakiengine/src/core/game_module.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';

/// test 项目的自定义模块
class TestModule extends DefaultGameModule {
  
  @override
  ThemeData? createTheme() {
    // test 项目的自定义主题
    return ThemeData(
      primarySwatch: Colors.blue,
      fontFamily: 'SourceHanSansCN',
      colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.blue).copyWith(
        secondary: const Color(0xFF137B8B),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF137B8B),
        elevation: 0,
      ),
    );
  }

  @override
  SakiEngineConfig? createCustomConfig() {
    // 可以返回项目特定的配置
    return null; // 使用默认配置
  }

  @override
  bool get enableDebugFeatures => true; // 启用调试功能

  @override
  Future<String> getAppTitle() async {
    // 自定义应用标题（可选）
    try {
      final defaultTitle = await super.getAppTitle();
      return defaultTitle; // 使用默认标题，或自定义如: '$defaultTitle - test'
    } catch (e) {
      return 'test'; // 项目名作为标题
    }
  }

  @override
  Future<void> initialize() async {
    if (kDebugMode) {
      print('[TestModule] 🎯 test 项目模块初始化完成');
    }
    // 在这里可以进行项目特定的初始化
    // 比如加载特殊的资源、设置特殊的配置等
  }
}

GameModule createProjectModule() => TestModule();
