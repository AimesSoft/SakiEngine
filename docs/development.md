# 开发与发布

[← 返回首页](../README.md) · [SKS 脚本指南](script-guide.md) · [English](../README.en.md) · [日本語](../README.ja.md)

SakiEngine 支持 Windows、macOS、Linux、Android、iOS 和 Web。本文说明启动器、运行配置、发布 / 演出构建及各平台的输出方式；游戏内操作见 [完整快捷键](../README.md#shortcuts)。

## 准备环境

在仓库根目录运行 `saki.bat`（Windows）或 `./saki.sh`（macOS / Linux）即可启动图形化 Launcher。入口优先使用系统 Node.js / Flutter；缺少时下载本地工具链。已有 SDK 过旧时需要自行更新，脚本不会自动替换它。

| 依赖 | 用途与要求 |
| --- | --- |
| Git | 克隆仓库与管理项目 |
| Flutter | stable 渠道；须包含满足项目约束的 Dart SDK。当前 Launcher 与示例要求 Dart `>=3.10.4 <4.0.0` |
| Node.js | 运行统一 CLI、项目创建与构建脚本；入口可引导安装 |
| Rust / rustup | 原生构建中的 `saki_native` 服务层；确保 `rustup`、`cargo` 可用 |
| 目标平台 SDK | Windows：Visual Studio 的「使用 C++ 的桌面开发」；macOS / iOS：Xcode、需要时安装 CocoaPods；Android：Android SDK / JDK / NDK；Linux：Flutter 桌面构建依赖及 GStreamer 音频依赖 |

本地 SDK 放在 `.saki_toolchain/`，下载归档缓存在 `tool/toolchain_cache/flutter/` 和 `tool/toolchain_cache/node/`。这些缓存不提交 Git。自动下载 Node.js / Flutter 不包含系统编译器、Rust 或平台 SDK。

使用系统 SDK 时，可通过 `flutter doctor -v` 检查目标平台环境。交叉构建另有严格版本要求，见下文。

## 启动与创建项目

Windows PowerShell：

```powershell
.\saki.bat
.\saki.bat SakiEngine
```

macOS / Linux：

```bash
./saki.sh
./saki.sh SakiEngine
```

无参数时打开 Launcher；传入 `Game/` 下的项目文件夹名则直接运行游戏。Launcher 可以创建项目、选择默认项目、运行与构建，并提供内置日志控制台和系统终端两种运行方式。需要 Flutter 终端热重载操作时，可选系统终端。

### Launcher 的运行配置

启动器扫描 `Game/` 中的项目，支持填写名称、Bundle ID、主题色来创建新项目，并生成配置、示例剧本、资源目录和 `ProjectCode`。选好项目后，分别设置运行设备、运行方式与运行配置：

| 运行配置 | 编译与资源行为 | 使用场景 |
| --- | --- | --- |
| Debug | Flutter Debug，保留引擎编辑工具 | 写 Dart 代码，热重载与热重启 |
| 演出模式 | Flutter Release + `SAKI_SHOW_MODE=true`，直接读取脚本，启用引擎编辑工具 | 使用发布性能调整对白、角色、背景、音乐与画布 |
| Profile | Flutter Profile，使用脚本预编译与发布资源管线 | 性能观察 |
| Release | Flutter Release，使用脚本预编译与发布资源管线 | 检查玩家版本 |

引擎的编辑工具通过 `kEngineDebugMode` 控制：Flutter Debug 或演出模式都会启用它。因此脚本编辑、多语言编辑、差分选择等不只在 Debug 下可用。

**内置控制台**支持查看 / 复制当前运行日志、Debug 热重载 `r`、热重启 `R`、安全重启和退出 `q`。安全重启会先停止进程再重新启动；Flutter 热重载与热重启按钮仅用于 Debug。

**系统终端**适合手动输入 Flutter 控制命令。Profile / Release 的发布资源运行管线目前要求内置控制台；演出配置虽然使用 Release 编译，仍保留自己的脚本直读与引擎重载流程。

### 统一 CLI

安装 Node.js 后，也可以在仓库根目录使用同一套 CLI：

```bash
node tool/saki_cli.js saki
node tool/saki_cli.js saki SakiEngine
node tool/saki_cli.js create
node tool/saki_cli.js select
node tool/saki_cli.js run
node tool/saki_cli.js build
```

`run.sh` / `node run.js`、`scripts/create_new_project.sh` / `.bat` 等旧入口仍保留。默认项目名保存在 `default_game.txt`。

## 项目结构与扩展

```text
SakiEngine/
├── Engine/                  # Flutter 引擎包、测试、脚本编译器
│   └── packages/saki_native/ # Rust 原生服务层
├── Launcher/                # 图形化开发启动器
├── Game/
│   └── SakiEngine/           # 仓库内置的轻量演示
├── scripts/                 # 项目创建、构建、资源打包
├── tool/                    # 统一 CLI 与工具链引导
├── toolchains/cross/        # macOS 交叉构建清单与目标包
├── third_party/             # 固定的原生依赖与本地修补
├── vscode-sakiengine-syntax/ # SKS 语法高亮扩展
└── docs/                    # 创作与开发指南
```

新建项目拥有独立的 `pubspec.yaml`、`lib/main.dart` 和平台目录，通过 `../../Engine` 引用引擎。创建器还会生成：

- `Assets/`：图片、字体、音乐、音效与语音等素材。
- `GameScript/configs/`：角色、站位、动画与系统配置。
- `GameScript/labels/`：剧情脚本。
- `ProjectCode/`：项目专用 Flutter 包，用于主题、界面和扩展逻辑。
- 项目级 `build.sh` 与 `.github/workflows/`。

项目入口使用 `registerProjectModule` 注册模块，再调用 `runSakiEngine`。`GameModule` 提供界面与主题扩展点、脚本命令以及 `scriptCanvases` 项目画布；设置界面可以通过 `SettingsScreen.extraTabs` 追加页签。未定制部分使用默认实现。内置轻量演示没有 `ProjectCode/`，可以直接查看其 [入口](../Game/SakiEngine/lib/main.dart)。

参考 [公共 API](../Engine/lib/sakiengine.dart)、[GameModule](../Engine/lib/src/core/game_module.dart) 与 [设置页签实现](../Engine/lib/src/widgets/settings_screen.dart)。

`Game/` 下除 `SakiEngine` 演示外的项目默认被引擎仓库忽略，适合使用各自的 Git 仓库管理。

<a id="interface"></a>

## 界面与系统扩展

### 流式布局与矢量绘制

项目界面使用标准 Flutter Widget，可组合 `Row`、`Column`、`Expanded`、`Wrap` 与 `LayoutBuilder`，根据可用空间调整排布、换行和尺寸。现有 [视频设置页](../Engine/lib/src/widgets/settings/video_settings_tab.dart)会按区域宽高切换单双列；[虚拟游戏画布](../Engine/lib/src/widgets/common/virtual_game_canvas.dart)负责逻辑分辨率、等比例缩放和画面比例适配。应用界面可以流式排版，场景画布则可保留稳定的演出坐标。

Flutter 的文字、图标和路径绘制，以及引擎接入的 [`flutter_svg`](https://pub.dev/packages/flutter_svg)，支持按目标尺寸绘制矢量 UI。项目还可使用 `CustomPainter` 定制形状与动效，例如现有 [命令轮盘](../Engine/lib/src/widgets/command_radial_wheel.dart)和[脚本画布绘制层](../Engine/lib/src/widgets/script_canvas_layer.dart)。位图背景与角色素材仍按其自身分辨率处理，矢量 UI 不会把位图转换成矢量图。

### 接入 Flutter / Dart 社区包

`ProjectCode` 是 Flutter 包，可以在自己的 `pubspec.yaml` 中声明 [pub.dev](https://pub.dev) 依赖，再通过 `GameModule` 的界面工厂、主题、设置页签或脚本扩展点接入项目。动画、网络请求、数据存储和平台服务都可以复用社区实现。若功能直接写在游戏入口包，则将依赖声明在对应游戏的 `pubspec.yaml` 中。

纯 Dart 包与原生插件按各自声明的支持平台使用；涉及平台权限、SDK 或 Runner 配置时，在游戏项目对应的 Android、iOS 或桌面目录完成配置。当前引擎已经使用 `flutter_animate`、`flutter_svg`、`window_manager`、`screen_retriever` 和 `path_provider` 等包，可从 [引擎依赖清单](../Engine/pubspec.yaml)查看集成示例。

### 操作系统交互与窗口扩展

引擎与工具已接入文本编辑、焦点管理、剪贴板和桌面快捷键；[本地存储路径](../Engine/lib/src/utils/local_storage_paths.dart)使用系统应用数据目录保存存档与元数据，[文件管理器接口](../Engine/lib/src/utils/desktop_file_manager.dart)调用 Windows Explorer、macOS Finder 或 Linux 文件管理器打开目录。

桌面 [`PlatformWindowManager`](../Engine/lib/src/utils/platform_window_manager_io.dart)基于 `window_manager` 与 `screen_retriever` 提供窗口标题、全屏、最大化 / 还原、宽高比约束和窗口事件。当前游戏内置 `5:4`、`16:10`、`16:9` 比例预设，按当前显示器可用工作区计算窗口边界，并支持等比例最大化后恢复原位置与尺寸。项目可通过 `GameModule.getAppTitle` 和 `showWindowCloseConfirmation` 定制标题与退出确认。

需要额外桌面行为时，可在项目层调用 [window_manager](https://pub.dev/packages/window_manager) 扩展窗口控制，或接入相应插件实现置顶、系统托盘等功能；这些属于项目扩展，并非引擎默认启用的功能。超出插件接口的系统能力，可通过 [Flutter 平台通道](https://docs.flutter.dev/platform-integration/platform-channels)连接原生代码。Web 使用[浏览器窗口适配层](../Engine/lib/src/utils/platform_window_manager_web.dart)，提供页面标题与浏览器全屏等操作；桌面窗口尺寸、位置控制不适用于浏览器页面。

## 本地发布构建

### 发布模式与演出模式

在 Launcher 的「构建模式」中选择：

| 对比项 | 发布模式 | 演出模式 |
| --- | --- | --- |
| 程序配置 | Flutter Release | Flutter Release，启用 `SAKI_SHOW_MODE=true` |
| 剧情执行 | `.sks` 预编译为 Dart | 不预编译 `.sks`，保留脚本直读 |
| 原生资源 | 生成 `game.sakipak` 并整理发布清单 | 桌面程序旁附带 `Game/<项目>/Assets/` 与 `GameScript*` |
| 引擎编辑器 | 关闭 | 保留脚本、多语言、差分、轮盘与网格等工具 |
| 日志入口 | 可输入 `console` 打开 | 可输入 `console` 打开 |
| 交付对象 | 玩家 | 编剧、演出和测试人员 |

桌面演出构建会同时复制 `game_config.txt`、`default_game.txt`、`icon.png`（如存在），让产物可以携带可编辑素材与脚本。启动后可修改这些文件，再用 `Shift + R` 或编辑器保存来重载；它不是 Flutter 的 Dart 代码热重载，修改项目代码仍需重新编译。

Launcher 在构建前执行 `flutter clean`、准备项目与依赖，成功后将产物目录打包成 `<作品名>-<版本>-<日期>.zip`；演出包在扩展名前添加 `-showcase`。ZIP 位于目标输出目录的上一级，完成后自动打开产物目录。构建期间对项目资源清单和引擎编译入口的临时修改会在结束后恢复。

### 开始构建

在 Launcher 选择项目与平台，或在根目录执行：

```bash
# 交互选择项目与平台
node tool/saki_cli.js build

# 显式指定项目与平台
node tool/saki_cli.js build SakiEngine windows
node tool/saki_cli.js build SakiEngine macos
node tool/saki_cli.js build SakiEngine linux
node tool/saki_cli.js build SakiEngine android
node tool/saki_cli.js build SakiEngine ios
node tool/saki_cli.js build SakiEngine web
```

上面是不同目标的调用示例，请选用当前宿主支持的目标。macOS / Linux 还可以使用 `./build.sh <项目名> <平台>`。CLI 的 `build` 走发布管线；演出构建与自动 ZIP 打包由 Launcher 提供。

| 目标 | 当前构建路径 |
| --- | --- |
| Windows | Windows 原生构建；macOS 可走下述 x64 交叉路径 |
| macOS | macOS 上使用 Flutter / Xcode 构建 |
| Linux | Linux 原生构建；macOS 可走下述 x64 交叉路径 |
| Android | 脚本生成 ARM64 release APK |
| iOS | macOS 上生成未签名 release 构建，签名与分发需另外完成 |
| Web | 生成浏览器可运行的静态站点，部署 `build/web/` 到 Web 服务器 |

产物位于 `Game/<项目>/build/`，下表为相对项目目录的常用输出位置：

| 平台 | 输出目录 |
| --- | --- |
| Windows | `build/windows/x64/runner/Release/` |
| macOS | `build/macos/Build/Products/Release/` |
| Linux | `build/linux/x64/release/bundle/` |
| Android | `build/app/outputs/flutter-apk/`，或 `build/app/outputs/apk/release/` |
| iOS | `build/ios/iphoneos/`，或 `build/ios/archive/` |
| Web | `build/web/` |

### 脚本预编译与 SakiPack

发布管线会把 `.sks` 预编译为 Dart，写入项目的 `.saki_cache/compiled_sks_bundle.g.dart`。原生平台使用 `.saki_cache/game.sakipak`；Launcher 的 Web 发布不生成 SakiPack，保留浏览器可以加载的原始资源。CLI 当前仍会生成包文件，但 Web 发布清单使用原始资源。构建期间临时调整项目资源清单及引擎编译脚本入口，结束后恢复。

原生发布资源清单不再单独列入散装的 `Assets/` 与 `GameScript*`，改为加载 SakiPack；剧情执行使用编译后的脚本。当前打包器仍会把 `GameScript*` 中的 `.sks` 文本收入包内，因此预编译不等于从发行包中移除源码。Web 保留原始资源清单。桌面 Debug 默认直接读取文件，方便编辑与重载。

SakiPack 将 `Assets/`、`GameScript*` 中支持的资源及 `default_game.txt` 集中为单个二进制包；音视频需要实际文件路径时按需提取。它和 `.sakisav` 都是引擎的数据格式，不应当作素材加密或防反编译承诺。

### macOS 交叉构建桌面目标

macOS 宿主可用以下命令请求 Linux x64 / Windows x64 构建：

```bash
./build.sh SakiEngine linux
./build.sh SakiEngine windows
```

该路径使用仓库中的 Runner、原生插件与 AOT snapshotter，并校验 SHA-256、Flutter Engine revision 和插件集合。当前 [清单](../toolchains/cross/manifest.json) 固定 **Flutter 3.44.0**；普通 stable SDK 不一定与目标包匹配。

缺少目标文件、校验不一致或项目原生插件集合变化时会拒绝构建。维护者需要通过 [目标包工作流](../.github/workflows/build-cross-target-packs.yml) 重建、导入匹配的目标包，不能直接复用旧 Runner。

输出目录：

- Linux：`Game/<项目>/build/linux/x64/release/bundle/`
- Windows：`Game/<项目>/build/windows/x64/runner/Release/`

<a id="performance"></a>

## 性能与内存

原生发布版采用 Dart AOT 与 Rust 原生服务，结合 [SKS 预编译](../Engine/tool/sks_compiler.dart)、[SakiPack 内存映射](../Engine/packages/saki_native/rust/src/api/assets.rs)和[历史快照 LZ4 压缩](../Engine/lib/src/utils/history_snapshot_codec_io.dart)，降低运行开销。自研 [Erika](https://github.com/AimesSoft/Erika) 将视频播放、渲染与时序控制保留在原生层。

**作者实测：SakiEngine 与 Ren’Py 双方均使用 Release 构建时，SakiEngine 空项目的内存占用约为 Ren’Py 的一半。**

## 媒体与原生依赖

[Erika](https://github.com/AimesSoft/Erika) 是 AimesSoft 自研的 Rust 媒体播放器内核。SakiEngine 通过仓库内的 [`erika_flutter`](../third_party/erika_flutter/README.zh.md) 桥接层接入 Erika，由原生层负责视频播放、画面呈现与播放时序控制，Dart 层负责播放指令、状态事件和游戏演出集成。循环、片段衔接、透明视频及混合模式等配置由引擎视频组件提供，具体支持情况依平台后端而定。

常规音乐、音效与语音使用 `just_audio`，Windows 使用其 Windows 后端，Linux 使用 GStreamer 相关后端。macOS universal / Windows x64 Erika 运行库固定在 `third_party/erika_flutter/native/`，对应构建脚本使用本地文件并校验摘要。

`third_party/media_kit*` 及其缓存脚本仍为旧依赖配置保留。只有项目仍依赖该链路、且遇到 Windows media_kit 依赖下载问题时，才需要：

```powershell
.\tool\cache_media_kit_windows_deps.bat
```

缓存位置是 `third_party/media_kit_libs_windows_video_hotfix/prebuilt/`。当前项目实际使用哪些依赖，应以 `pubspec.yaml` 和插件注册结果为准。

维护者更新 Erika 桥接层可参考 [导入脚本](../scripts/vendor-erika-flutter.js)。原生服务层的职责和绑定生成方式见 [saki_native](../Engine/packages/saki_native/README.md)。

## GitHub Actions 与工具链分发

现有 CI 模板面向**独立游戏仓库**：根目录必须有 `pubspec.yaml` 和 `Assets/`；推送到 `main` 且提交信息包含 `[build]` 才进入构建发布流程。模板编排 Android、iOS、macOS、Windows、Linux 构建、Release 发布与成功后的 patch 版本递增；引擎仓库本身不满足游戏仓库条件时会跳过。

**启用前先核对 SDK 版本。** 当前 [主工作流](../.github/workflows/main.yml) 仍指定 Flutter `3.35.1`，低于当前示例与 Launcher 的 Dart SDK 要求，不能直接当作已验证可用的发布流水线。使用模板的项目应先更新相应 Flutter 版本并验证自己的平台依赖。

如需制作携带工具链的开发分发包，可使用：

```bash
./tool/package_distribution.sh
```

该脚本在 `dist/` 生成带时间戳的目录与 ZIP，并准备多平台 Flutter stable、Node.js LTS 归档及旧 media_kit Windows 缓存。它用于分发开发环境，与单个游戏的 release 构建不同；也不会替代目标平台的系统 SDK。

## 运行现有测试

修改引擎行为时，在配置好 Flutter / Rust 环境后按改动范围运行测试。例如：

```bash
cd Engine
flutter pub get
flutter test test/character_expression_layers_test.dart
flutter test test/script_localization_editing_test.dart
flutter test test/settings_screen_extra_tabs_test.dart
```

更多回归覆盖见 [Engine/test](../Engine/test)。仅修改文档时，检查链接、命令与实际实现是否一致即可。
