// 模块注册中心（显式注册）
//
// 每个游戏项目在自己的 `main.dart` 中调用 `registerProjectModule` 即可。
// 引擎不再维护自动扫描/自动生成的模块注册。
import 'package:sakiengine/src/core/project_module_loader.dart';

/// 创建项目特定模块的助手函数
/// 这个函数提供了一个便捷的方式来创建符合规范的项目模块
/// 
/// 使用示例：
/// ```dart
/// // 在 Game/MyProject/ProjectCode/lib/myproject/myproject_module.dart 中:
/// import 'package:sakiengine/src/core/game_module.dart';
/// import 'package:sakiengine/src/core/module_registry.dart';
/// 
/// class MyProjectModule extends DefaultGameModule {
///   // 覆盖需要自定义的方法
/// }
/// 
/// // 在模块入口处调用:
/// final _ = registerProjectModule('myproject', () => MyProjectModule());
/// ```
void registerProjectModule(String projectName, GameModuleFactory factory) {
  ProjectModuleLoader().registerModule(projectName, factory);
}
