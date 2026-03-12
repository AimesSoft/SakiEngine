import 'package:sakiengine/src/core/project_module_loader.dart';

/// 自动模块注册器
///
/// 当前模块由 `generated_module_registry.dart` 统一注册。
/// 这个类只保留查询与兼容接口。
class AutoModuleRegistry {
  static bool _initialized = false;

  static void initializeAllModules() {
    if (_initialized) {
      return;
    }
    _initialized = true;
  }

  static List<String> scanForAvailableModules() {
    return ProjectModuleLoader().getRegisteredModules();
  }

  static String generateAutoRegistrationCode() {
    final modules = scanForAvailableModules();
    final buffer = StringBuffer();
    buffer.writeln('// 已注册模块: ${modules.join(', ')}');
    buffer.writeln('// 模块注册由 generated_module_registry.dart 自动维护。');
    return buffer.toString();
  }
}
