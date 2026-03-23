# flutter_steamworks

让 Flutter 开发的桌面游戏、壁纸引擎、桌宠等应用能够直接调用 Steamworks 接口的插件。在应用启动时向 Steam 客户端上报游玩状态并打通后续 Steam 特性，现已支持 **macOS / Linux / Windows** 三端共用同一套 Dart API。

> ⚠️ **最重要的一步：确保在 macOS 构建目标中关闭 App Sandbox。**
>
> 如果不关闭沙箱（Xcode `Signing & Capabilities` → `App Sandbox` 关闭或移除），应用进程无法与 Steam 客户端通信，`initSteam` 会一直失败并无法显示游玩状态。你也可以直接编辑 entitlements 文件来取消沙箱：
> - 修改 `macos/Runner/DebugProfile.entitlements` 与 `macos/Runner/Release.entitlements`，定位 `<key>com.apple.security.app-sandbox</key>`。
> - 将紧随其后的 `<true/>` 替换为 `<false/>`，或连同该键一起删除。
> - 重新构建 Flutter macOS 应用即可验证 Steam 连接是否恢复。

## 特性
- 通过 `initSteam(appId)` 初始化 Steam API，成功后 Steam 会显示对应 AppID 的游玩状态。
- 提供通用的 MethodChannel 封装，Dart 侧仅需传入整数 AppID。
- macOS 内置 `libsteam_api.dylib`，Linux / Windows 只需把官方 SDK 的运行库放到约定目录即可自动复制到产物里。

## 安装
在目标项目的 `pubspec.yaml` 中添加 git 依赖：

```yaml
dependencies:
  flutter_steamworks:
    git:
      url: https://github.com/MCDFsteve/flutter_steamworks.git
      ref: main   # 或指定 tag/commit
```

执行 `flutter pub get` 拉取依赖。

## 快速上手
```dart
import 'package:flutter_steamworks/flutter_steamworks.dart';

Future<void> setupSteam() async {
  const appId = 480; // Spacewar 测试 AppID，可替换为你自己的游戏 ID
  final steamworks = FlutterSteamworks();

  final ok = await steamworks.initSteam(appId);
  if (!ok) {
    // 处理失败情形，例如提示用户先启动 Steam 客户端
  }
}
```

> 注意：为了让 Steam 正确显示状态，需要：
> 1. 用户本地安装并登录 Steam 客户端。
> 2. AppID 必须是合法的 Steam 应用。如果只是测试，可以用 Valve 提供的 Spacewar(`480`)。
> 3. 在 macOS 上运行时，macOS 会校验应用及依赖项签名。插件内部已对嵌入的 `libsteam_api.dylib` 和插件框架进行 adhoc 签名，如需发布版本请结合自己的签名证书重新处理。

### 分发 Steam 运行库

插件会按下表依次查找 Steam SDK 的运行库，并在构建完成后自动拷贝到 Flutter 桌面应用目录。请从 Valve 官方 SDK 中拷贝对应文件到任意一个候选位置：

| 平台 | 必需文件 | 搜索顺序（命中即停止） |
| --- | --- | --- |
| macOS | `macos/libsteam_api.dylib` | 仓库内已提供 |
| Linux | `libsteam_api.so`（建议 64 位版本） | `linux/libsteam_api.so(.1)` → `third_party/steamworks/redistributable_bin/linux64/` → `third_party/steamworks/public/steam/lib/linux64/` → 系统默认搜索路径 |
| Windows | `steam_api64.dll` | `windows/steam_api64.dll` → `third_party/steamworks/redistributable_bin/win64/` → `third_party/steamworks/public/steam/lib/win64/` → 系统默认搜索路径 |

> Flutter 桌面默认构建 64 位二进制，如需 32 位 Runner，请自行放置 `steam_api.dll` 并在相同目录扩展搜索逻辑。

插件内部会在初始化成功后缓存上下文，并在插件析构时自动调用 `SteamAPI_Shutdown()`。重复调用 `initSteam` 会复用已经建立的连接。

## 可扩展方向
- 当前聚焦于 `SteamAPI_Init/Shutdown` 与游玩状态上报，如需成就、好友、工作坊等高级能力，欢迎基于现有桥接层继续扩展。

## 许可证
MIT License。详细信息见仓库内 `LICENSE` 文件。
