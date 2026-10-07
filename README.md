<p align="center">
  <img src="Git/readme-banner.svg" alt="SakiEngine — 跨平台视觉小说引擎" width="100%">
</p>

<h1 align="center">SakiEngine</h1>

<p align="center">
  <b>基于 Flutter 的跨平台视觉小说引擎</b><br>
  SKS 剧本 · 流式布局 · 矢量 UI · 跨平台发布<br>
  Windows · macOS · Linux · Android · iOS · Web
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-545C91?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Built with Flutter"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-6B82A8?style=flat-square&amp;logo=dart&amp;logoColor=white" alt="Written in Dart"></a>
  <a href="Engine/packages/saki_native"><img src="https://img.shields.io/badge/Rust-native_services-B88D83?style=flat-square&amp;logo=rust&amp;logoColor=white" alt="Rust native services"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-91A891?style=flat-square" alt="MIT License"></a>
  <a href="https://github.com/AimesSoft/SakiEngine/commits/main"><img src="https://img.shields.io/badge/Status-in_development-D6A0B6?style=flat-square" alt="持续开发中"></a>
</p>

<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="#quick-start">快速开始</a> ·
  <a href="#interface">界面与扩展</a> ·
  <a href="#performance">性能与内存</a> ·
  <a href="#features">核心功能</a> ·
  <a href="#launcher">启动器</a> ·
  <a href="#shortcuts">快捷键</a> ·
  <a href="#build">发布模式</a> ·
  <a href="docs/script-guide.md">脚本指南</a> ·
  <a href="docs/development.md">开发与发布</a> ·
  <a href="https://github.com/AimesSoft/SakiEngine/issues">问题反馈</a>
</p>

---

## 项目介绍

SakiEngine 是基于 **Flutter / Dart** 开发、面向高性能原生运行的开源视觉小说与 Galgame 引擎，支持 **Windows、macOS、Linux、Android、iOS 和 Web**。

引擎使用 `.sks` 编写剧情，提供对话与分支、角色演出、音视频、多语言、存档与回滚。图形化启动器负责项目创建、运行和打包；内置编辑器支持在游戏中调整剧本与演出，项目界面和逻辑可通过 Flutter 模块扩展。

视频播放集成 **AimesSoft 自研的 Rust 播放器内核 [Erika](https://github.com/AimesSoft/Erika)**，为游戏中的视频演出提供底层播放能力。

引擎名称 **Saki** 来自《来自新世界》中的**渡边早季（渡辺早季 / Saki Watanabe）**。

<a id="interface"></a>

## 界面、生态与系统集成

SakiEngine 将 **Flutter 的布局、绘制、组件生态与平台接口**开放给游戏项目，既能制作视觉小说，也能围绕作品构建完整的应用界面和桌面交互。

- **流式布局与自适应界面**：组件可随可用空间重新排布、换行和伸缩；设置页支持单双列切换，游戏画布提供逻辑分辨率与比例适配，兼顾窗口变化与演出构图。
- **矢量绘制 UI**：文字、图标、路径与 SVG 可按目标尺寸绘制，在高 DPI 和窗口缩放时保持清晰；结合自定义绘制、动画与主题，可制作作品专属的菜单、控件和交互效果。
- **丰富的社区包生态**：直接使用 [pub.dev](https://pub.dev) 上的 Flutter / Dart 包，将动画、网络、数据存储及平台服务接入 `ProjectCode`。项目 UI、主题和逻辑均可用标准 Flutter 组件扩展。
- **原生操作系统交互**：接入文本输入、焦点、剪贴板与桌面快捷键，按系统规范存储存档和日志，并可从工具中打开系统文件管理器。更深层的系统能力可通过 Flutter 插件或平台通道接入。
- **灵活的窗口控制与扩展**：桌面端支持窗口 / 全屏切换、`5:4` / `16:10` / `16:9` 比例预设、等比例最大化与还原、当前显示器工作区适配，以及自定义关闭确认；项目还可通过社区插件扩展窗口置顶、系统托盘等桌面行为。

桌面窗口控制面向 Windows、macOS 与 Linux；移动端和 Web 使用各自的平台能力。社区插件按目标平台选择与集成，开发入口见 [界面与系统扩展](docs/development.md#interface)。

<a id="performance"></a>

## 高性能设计

**Dart AOT + Rust 原生服务 + Erika 播放器内核**构成原生发布版的性能基础。Dart 代码提前编译为机器码，Rust 承担资源索引、存档与历史快照等数据处理，Erika 将视频播放、渲染和时序控制保留在原生层，Dart 只传递播放命令与状态事件。

### 与 Ren’Py 的运行开销和内存对比

以下比较 **SakiEngine 原生发布模式**与 **Ren’Py 8 / Python 3** 的架构，不代表同场景实测成绩。Web 使用浏览器编译与运行管线，需单独评估。

| 维度 | SakiEngine | Ren’Py 8 / Python 3 |
| --- | --- | --- |
| **逻辑执行开销** | Dart AOT 与 Rust 执行机器码，避免这些路径上的 Python 字节码解释开销 | Python 层逻辑由解释器执行；原生扩展中的工作不承担相同的解释开销 |
| **剧本加载** | 构建时将 SKS 预生成 Dart 脚本节点，省去发布时的剧情文本解析；运行时仍有节点调度 | 使用 `.rpyc` 编译缓存加速加载，并由 Ren’Py 运行时调度剧情 |
| **渲染与视频** | Flutter 原生渲染管线与自研 Erika；视频热路径不经过 Dart 逐帧处理 | 同样使用 GPU 渲染与 FFmpeg 等原生组件，不能按纯 Python 的速度估算画面和解码性能 |
| **内存管理** | Rust 数据结构、SakiPack 内存映射与历史快照 LZ4 压缩控制部分数据开销；Dart 堆仍有 GC | Python 对象、回滚状态与图片预测缓存占用内存；图像和解码器也有原生缓冲区 |

**性能优势主要体现在逻辑与数据处理路径。** 相比等价的纯 Python 循环和对象操作，AOT 与 Rust 通常有更低的执行开销；收益取决于这部分工作在整帧中的占比，不能直接换算为整款游戏的帧率倍数。

**总内存占用需要按场景比较。** Rust 可以减少部分对象和分配开销，但 Flutter 引擎、Dart 堆、解码后的图片、GPU 纹理及视频缓冲同样占用内存。AOT 不会消除 GC，也不保证游戏比 Ren’Py 更省内存。这里未提供同素材、同分辨率的对照实测，因此不标注内存降幅。实现依据与测试口径见 [性能与内存说明](docs/development.md#performance)。

<a id="features"></a>

## 核心功能

| 模块 | 功能 |
| --- | --- |
| **剧情与阅读** | SKS 对白、选项与条件跳转，普通 / NVL / 电影旁白，自动播放、快进、历史与回滚，`.sakisav` 存读档与已读记录 |
| **角色与演出** | 自动站位、姿势与表情、第二层叠加差分，CG、WebP 动画、场景转场、滤镜、鼠标视差与项目画布 |
| **声音与影像** | 音乐、音效与语音控制；自研 Erika 播放器内核驱动视频演出，支持循环、衔接及透明视频相关配置，具体能力依平台而定 |
| **多语言创作** | 同一句脚本内写简中、繁中、英语与日语；缺失翻译回退，内置逐句翻译编辑器与单语言脚本视图 |
| **实时编辑** | 桌面 Debug 与演出模式内置脚本编辑、差分预览、画布选择与开发者面板；保存后重载脚本与资源 |
| **项目扩展** | Launcher 管理与创建项目；`ProjectCode` 定制主题、界面和脚本扩展，设置页可追加项目页签，提供 Steam 成就接入 |
| **运行与发布** | SKS 预编译、SakiPack 资源单包，以及 Rust 原生服务层，负责资源索引、存档、脚本索引与历史快照等工作 |

平台 SDK、签名要求与输出位置见 [开发与发布](docs/development.md)。

### Erika 播放器内核

**Erika** 是以 Rust 开发的媒体播放器内核，通过 `erika_flutter` 桥接层接入 SakiEngine，负责视频播放、原生画面呈现与播放时序控制。

基于 Erika，引擎提供背景视频、循环与片段衔接、播放速度控制，以及透明视频、混合模式和不透明度配置，用于将视频融入场景演出。具体能力依平台后端而定；集成方式与原生依赖见 [媒体与原生依赖](docs/development.md#媒体与原生依赖)。

<a id="launcher"></a>

## 启动器

**SakiEngine Launcher** 提供项目管理、运行和构建界面。它扫描 `Game/` 中的项目，支持新建项目、设置默认项目、选择运行设备和查看日志。创建器根据项目名称、Bundle ID 与主题颜色，生成脚本、配置、资源目录和 `ProjectCode` 代码包。

启动器提供四种运行配置；构建模式单独选择：

| 运行配置 | 用途 |
| --- | --- |
| **Debug** | 开发引擎或项目代码，使用 Flutter 热重载、热重启与引擎创作工具 |
| **演出模式** | 以 Release 配置运行，同时保留脚本直读、重载和引擎编辑工具，适合调整对白、差分、背景与音乐 |
| **Profile** | 使用发布资源管线运行，观察接近发布环境的性能 |
| **Release** | 使用发布资源管线运行，检查面向玩家的版本 |

**内置控制台**会显示任务日志，提供 Debug 热重载 / 热重启、安全重启、退出和日志复制。**系统终端**适合用 `r` / `R` / `q` 控制 Flutter；Profile / Release 的发布资源运行管线需要使用内置控制台。构建则可选「发布模式」或「演出模式」，完成后自动生成 ZIP 并打开产物目录，区别见 [发布模式](#build)。

<a id="quick-start"></a>

## 快速开始

先准备 Git 与目标平台的开发环境。原生游戏构建还需要 **Rust / rustup**；Flutter 需包含 **Dart 3.10.4 或更高的 3.x 版本**，以满足当前 Launcher 和示例项目约束。

```bash
git clone https://github.com/AimesSoft/SakiEngine.git
cd SakiEngine
```

**Windows · PowerShell**

```powershell
.\saki.bat
```

**macOS / Linux**

```bash
./saki.sh
```

入口会优先使用系统 Node.js / Flutter，缺少时自动下载到仓库内。系统编译器、Rust 与平台 SDK 需要另行准备，已有 Flutter 过旧时也需要更新。完整清单见 [环境准备](docs/development.md#准备环境)。

在 Launcher 中选择 **SakiEngine** 运行演示，或创建新项目。直接运行演示的命令：

```powershell
# Windows
.\saki.bat SakiEngine
```

```bash
# macOS / Linux
./saki.sh SakiEngine
```

### SKS 脚本示例

下面的例子使用演示项目里的 `yk` 角色与 `bg school` 背景。SKS 借鉴了 Ren’Py 的书写习惯，使用独立的解析器与运行时。

```sks
label start
scene bg school with dissolve
yk pose2 happy "这是一个带选项分支的示例。"

menu
"角色对白" dialogue_branch
"旁白" narration_branch
endmenu

label dialogue_branch
yk "这里是角色对白分支。"
return

label narration_branch
"这里是旁白分支。"
return
```

完整示例见 [演示剧本](Game/SakiEngine/GameScript/labels/start.sks)，语法说明见 [SKS 脚本指南](docs/script-guide.md)。

### 脚本多语言

```sks
yk "/zhs 你好。/ /zhc 你好。/ /en Hello./ /jp こんにちは。/"
```

对白、选项与角色显示名都可以使用语言片段；缺少当前语言时，按 `script_default_language` 回退。也可以从 `"你好。 /en Hello./"` 这样的渐进写法开始。日语脚本标签使用 `jp`。

<a id="build"></a>

## 构建与发布模式

启动器提供两种构建模式。它们都生成 Release 程序，但资源组织和创作工具的保留方式不同：

| 对比项 | 发布模式 | 演出模式 |
| --- | --- | --- |
| 用途 | 给玩家分发正式作品 | 给编剧、演出或测试人员继续调整作品 |
| 剧情 | SKS 预编译为 Dart，运行编译后的剧情 | 跳过 SKS 预编译，保留脚本直读与重载 |
| 资源 | 原生平台生成 `game.sakipak`；Web 保留浏览器可访问的资源 | 桌面产物附带外置 `Game/<项目>/Assets` 与 `GameScript*` |
| 创作工具 | 关闭引擎编辑工具；保留 `console` 日志入口 | 开启引擎编辑工具与演出快捷键 |
| 打包 | 自动生成带作品名、版本和日期的 ZIP | 同样生成 ZIP，文件名附加 `-showcase` |

桌面演出模式适合在不重新编译程序的情况下改脚本、替换资源并查看效果；改动 Dart 项目代码仍需要重新构建。发布前，在启动器中选择 **构建模式 → 发布模式 → 构建目标 → 发布构建**，完成后会自动打开输出目录。

在 Launcher 中选择构建目标，或使用已安装的 Node.js：

```bash
node tool/saki_cli.js build
# 示例：在 Windows 上构建演示项目
node tool/saki_cli.js build SakiEngine windows
```

| 平台 | 发布方式 |
| --- | --- |
| Windows | 桌面应用，使用 Windows 原生构建或 macOS 交叉构建 |
| macOS | macOS 应用，使用 Flutter / Xcode 构建 |
| Linux | 桌面应用，使用 Linux 原生构建或 macOS 交叉构建 |
| Android | 当前脚本生成 ARM64 APK |
| iOS | 在 macOS 上构建；当前默认不签名，分发时完成签名 |
| Web | 生成 `build/web` 静态站点，部署到 Web 服务器后通过浏览器游玩 |
| macOS → Windows / Linux | 提供 x64 交叉构建路径，要求清单匹配的 Flutter SDK、目标包与原生插件集合 |

产物位于 `Game/<项目>/build/`，启动器生成的 ZIP 位于对应产物目录的上一级。命令行 `build` 走发布构建流程；需要演出构建或自动 ZIP 打包时使用 Launcher。具体输出、环境要求、资源打包方式及 CI 模板现状见 [开发与发布](docs/development.md)。

<a id="shortcuts"></a>

## 快捷键与操作

### 阅读与通用操作

| 操作 | 功能 |
| --- | --- |
| `Enter` / `Space` / 方向键下 / 滚轮向下 | 显示完整对白或推进剧情 |
| 方向键上 / 滚轮向上 | 按设置回退剧情或打开观看记录 |
| 按住 `Ctrl` / `Command` | 强制快进；松开停止 |
| 鼠标右键 | 隐藏 / 恢复游戏 UI；在支持的覆盖界面中关闭该界面 |
| `Esc` | 关闭当前编辑工具或支持的覆盖界面 |
| 依次输入 `console` | 打开日志面板，发布版也可用；不要按修饰键，相邻按键间隔不超过 3 秒 |

### 创作与演出

以下为桌面 **Debug / 演出模式**的内置操作。游戏窗口需获得焦点，编辑文本时会暂停会干扰输入的全局快捷键。

| 快捷键 | 创作工具 |
| --- | --- |
| `Shift + R` | 重载当前脚本，用于查看磁盘上的剧情与资源修改 |
| `Shift + A` | 表情 / 姿势轮盘，选择后松开 Shift 应用 |
| `Shift + C` | 当前对白的角色 / 旁白轮盘，选择后松开 Shift 应用 |
| `Shift + B` | 背景网格，预览并双击应用 |
| `Shift + 1` | 音乐网格，试听并双击应用 |
| `Shift + V` | 项目画布网格，预览并双击放置 |
| `Shift + E` | 完整差分选择器，分别预览基础表情与第二层叠加 |
| `Shift + D` | 开发者面板 |
| `Shift + P` | 脚本编辑器，支持完整源码与单语言视图 |
| `Shift + L` | 多语言编辑器，逐句编辑对白与角色名 |

背景、音乐与画布网格松开 Shift 后保持打开，再按对应快捷键或 `Esc` 关闭；轮盘在松开 Shift 时应用。项目还可以通过 `GameModule.debugCommandMenus` 注册自己的 Shift 快捷键。`Shift + R` 是游戏脚本重载，与 Flutter 终端的 `r` 热重载、`R` 热重启不同。

<details>
<summary>编辑器内的完整快捷键</summary>

下表中的 `Mod` 在 Windows / Linux 上指 `Ctrl`，macOS 上指 `Command`。

| 快捷键 | 功能 |
| --- | --- |
| `Mod + S` | 保存并重载；脚本和多语言编辑器均支持 |
| `Mod + W` / `Esc` | 关闭编辑器；脚本编辑器中 Esc 优先关闭查找栏，多语言编辑器会提示处理未保存修改 |
| `Mod + F` | 打开脚本查找栏 |
| `Mod + G` / `F3` | 查找下一处；查找栏未打开时先打开 |
| `Mod + Shift + G` / `Shift + F3` | 查找上一处 |
| `Mod + /` | 切换所选脚本行的注释 |
| `Mod + Z` | 撤销脚本编辑 |
| `Mod + Shift + Z` / `Mod + Y` | 重做脚本编辑 |
| `Mod + A` / `C` / `X` / `V` | 全选 / 复制 / 剪切 / 粘贴 |

保存前会检查磁盘文件是否被其他编辑器修改；冲突时保留草稿并提示处理。

</details>

<a id="showcase"></a>

## 界面截图

<table>
  <tr>
    <td width="50%"><img src="Git/main.png" alt="作品展示：主菜单界面" width="100%"></td>
    <td width="50%"><img src="Git/say.png" alt="作品展示：角色立绘与对话框" width="100%"></td>
  </tr>
  <tr>
    <td align="center">主菜单</td>
    <td align="center">角色与对白</td>
  </tr>
  <tr>
    <td width="50%"><img src="Git/history.png" alt="作品展示：对话历史记录" width="100%" loading="lazy"></td>
    <td width="50%"><img src="Git/dialog.png" alt="作品展示：返回主菜单的确认对话框" width="100%" loading="lazy"></td>
  </tr>
  <tr>
    <td align="center">对话历史</td>
    <td align="center">确认弹窗</td>
  </tr>
</table>

<p align="center"><sub>仓库中保留的作品截图；具体界面由项目主题与模块决定。</sub></p>

<a id="explore"></a>

## 文档与示例

| 资源 | 内容 |
| --- | --- |
| [SKS 脚本与创作指南](docs/script-guide.md) | 场景、差分、动画、画布、文字效果、转场与多语言 |
| [开发与发布](docs/development.md) | 工具链、CLI、项目结构、模块定制、SakiPack 与构建 |
| [轻量演示](Game/SakiEngine) | 随仓库提供的可编辑项目 |
| [《空之歌：每当磁针再次振动，我便在此等待》](https://store.steampowered.com/app/3536120/) | 使用 SakiEngine 制作的游戏，已上架 Steam · [源码仓库](https://github.com/MCDFsteve/SoraNoUta-SakiEngine) |
| [VS Code 扩展](vscode-sakiengine-syntax) | `.sks` 语法高亮；在扩展面板选择「从 VSIX 安装」，使用目录中最新的 `.vsix` |
| [Rust 原生服务](Engine/packages/saki_native/README.md) | 资源与脚本索引、存档、历史快照和已读记录 |

## 反馈与贡献

通过 [Issues](https://github.com/AimesSoft/SakiEngine/issues) 提交问题、功能建议或翻译修正，通过 Pull Request 贡献代码与文档。问题报告请附操作系统、启动命令、复现步骤和相关日志。

## 许可证

引擎代码采用 [MIT License](LICENSE)。第三方依赖与游戏素材遵循各自的许可，发布作品时请同时查看对应授权。
