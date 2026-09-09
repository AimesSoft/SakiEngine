# `.yuyu` 映射兼容实现记录

日期：2026-09-08。对应 [完整设计](yuyu-package-compatibility-design.md)。

**已实现可以导出、校验、分发和加载的首版代码；完整设计尚未完成。** 当前版本用于验证映射与包执行路径，不能用它发布“NightBoat 已完整兼容”的结论。NightBoat 的全项目转换仍被明确拒绝，原游戏脚本和素材未修改。

## 当前可执行路径

```text
原始 RPY → 内置 Ren'Py AST → 受支持的 SKS/配置/映射表
        → 候选 .yuyu → Saki 实际解析器校验 → 正式 .yuyu
                                           ├─ YuYuball 执行包内原 RPY
                                           └─ Saki GameManager 执行包内 SKS
```

转换器没有执行游戏中的任意初始化 Python，没有引入第二套剧情 VM 或 ATL 解释器。所有未实现构造都会进入覆盖报告并阻止 Saki 兼容包替换旧产物。数千条未解析引用可能来自少量未实现定义，不能将诊断条数视为独立开发任务数。

**桌面编译现提供可选 `.yuyu`，默认不勾选。** 原生启动器和 Web 启动器共用 `Distributor`，未勾选时保留原来的普通发行包及 RPA 规则，勾选后生成原引擎可运行的内容包及各平台启动依赖。原 RPY、层叠/动画定义、素材与网页完整保留，同时附上可生成的映射和诊断；映射未完成时，Saki 明确拒绝加载。原引擎发行不再依赖完整 Saki 映射，否则现有游戏无法发布。它是完整兼容完成前的发行状态，最终双引擎映射目标保持不变。

## 已实现的内容

| 部分 | 代码位置 | 当前行为 |
|---|---|---|
| YuYuball 导出器 | `RenpyEngine/engine_core/yuyu/exporter.py` | 用固定 SDK 的真实 AST 转换定义、剧情、菜单和顺序 ATL；生成源映射、覆盖报告、角色/站位/动画及显式资源别名 |
| 包写入与原版加载 | `RenpyEngine/engine_core/yuyu/package.py`、`renpy.py` | 确定顺序的 ZIP64、SHA-256 索引、流式素材写入、原子替换；bootstrap 扫描前挂载原 `game/`；临时缓存与源目录分离 |
| YuYuball 发行 | `tools/yuyu.py`、`yuyu/distribution.py`、`launcher/game/distribute.rpy`、Rust launcher | 桌面编译默认输出普通发行包；勾选 `.yuyu` 后输出启动依赖、内置 `game.yuyu` 和独立内容副本；保留 SDK 新增字体与构建元信息；遵循文件分类并核对源快照；显式兼容包覆盖仍需 Saki 校验 |
| Saki 包读取 | `Engine/lib/src/compat/yuyu/yuyu_package.dart` | 校验清单、能力、全部载荷、ZIP 路径和大小限制；挂载资源别名；媒体使用真实文件路径 |
| Saki 校验器 | `yuyu_validator.dart`、`Engine/tool/yuyu_validate.dart` | 调用实际 SksParser；核对节点数量/类型、源文件哈希、标签、菜单目标、资源、层组合与动画配置 |
| 通用兼容模块 | `yuyu_game_module.dart`、引擎启动入口 | `--package` 或 `SAKI_YUYU_PACKAGE`；使用同一 GameManager；包模式绕过内置 compiled bundle；按 manifest 设置逻辑舞台尺寸 |
| 顺序动画 | `animation_config.dart`、`animation_manager.dart`、场景动画控制器 | 独立 profile，精确源曲线、hold、零时长赋值、循环边界；单 ticker 连续播放，取消时释放等待；原生 SKS 默认曲线保留 |
| 显示生命周期 | GameManager、GameModule、GamePlayScreen | 普通显示不添加隐式淡入；同背景 scene 清场并注销旧 ticker；无 at 的同尺寸 tag 显示继承站位/动作；对白与后续菜单保持独立交互 |
| WebView | `yuyu_webview.dart`、`yuyu_resource_server.dart` | 透明专用宿主、包内相对网页资源、MIME、HEAD/Range、原 `window.ipc`/`yuyuballOverlay.receive` 消息形状 |
| 核心 Web 桥接 | `yuyu_story_bridge.dart` | 主菜单开始、ADV 对白、打字状态、选项、基础键盘与指针；检查交互 ID，拒绝重复/迟到输入，重放当前快照 |
| NVL 1–6 映射 | `yuyu_nvl.dart`、NvlNode、GameState、二进制序列化 | 累积/逐句替换、跨模式保留行格式、居中预排版、原网页消息；存入原生快照 |
| 鼠标视差 | 既有 MouseParallax + GameModule 参数 | 使用原组件，接收网页外部指针并适配回正参数；没有另写视差渲染系统 |

Flutter 依赖新增 `archive`、`crypto`、`unorm_dart`、`flutter_inappwebview`。本地 Flutter 3.44.0 构建时自动更新了 macOS Swift Package Manager 工程和 CocoaPods 锁文件；Windows WebView 插件注册文件也已更新。

macOS 配置只为资源服务使用的 `127.0.0.1` 添加 HTTP 例外。Apple 文档说明 macOS 14 起 IP 地址连接需要显式 ATS 例外，具体配置依据 [NSExceptionDomains](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains)。

### 首版支持范围

映射 profile：`yuyuball-to-sks-sequence-v1`。动画 profile：`yuyuball-sequence-v1`。

当前声明的能力：

- `sks.core@1`
- `sks.animation.yuyuball-sequence@1`
- `sks.layers.yuyuball-attributes@1`（条件层叠映射包）
- `sks.characters.yuyuball@1`（角色颜色、默认变换）
- 可选 `ui.yuyuball-web-core@1`
- 可选 `ui.yuyuball-web-nvl@1`（包含核心 Web 协议，使用 `--web-profile nvl`）

支持常量文件图像、Character 名称/图像、常量 color 和具名 default_at 声明、受限常量元信息、label/jump/return、普通对白、静态选项、scene/show/hide、数值 pause、基础音频指令。文本转义、标签、插值以及未经映射的音频选项会报错。

顺序 ATL 支持常量中心坐标、zoom、offset、alpha、rotate，linear/ease/easein/easeout、hold 和末尾整段 repeat。中心坐标区分整数像素与浮点相对值；rotate 从度转换到 Saki 弧度；zoom 按原素材高度换算。无法等价合并的坐标/偏移轨道、动态尺寸与位置组合会报错。首版普通 scene 要求源图尺寸等于逻辑舞台，避免隐式拉伸改变原画面；其他尺寸需要补几何映射。

**第二批已加入受限 layeredimage 映射。** 支持具名互斥 group、default、Null()、正/负属性、if_all/if_any/if_not，以及 NightBoat 使用的显式 multiply GL 元组。保留所有原图层，用映射表在 GameManager 的 show 路径解析属性，再交给既有 CharacterCompositeCache；不是新增剧情解释器。要求同一 layeredimage 的非空图层画布尺寸一致，且首组是有默认值的无条件基础图层。multiple group、auto、always、任意 when/Python 和不同尺寸的布局尚未声明支持。

默认属性只在选择图层时补入，显式属性编码在 CharacterState.pose 中；后续 show 继承同组之外的属性，负属性移除指定项，hide/scene 后重置。切换到同一 tag 的另一 layeredimage 时保留双方共有属性。该字符串已通过既有二进制快照往返测试，但动画相位和完整读档恢复仍未完成。

Character.color 是源端 who（姓名）的颜色：原生兼容对白框按 `#RRGGBB` / `#RRGGBBAA` 显示；原 Web 协议仍发送源端原有的普通 who/what，由网页控制样式。说话角色和显示 tag 使用不同命名空间，包模式关闭 Saki 原生对白的自动立绘显示。default_at 和 config.tag_transform 映射到角色默认站位/动画，首次 show 或 hide 后再次显示时应用，已有 tag 的无 at 显示继承当前动作；tag_transform 优先于 Character.default_at。只识别常量 blend 元组赋值和 tag_transform 赋值，不执行原初始化 Python。

multiply 的目标公式为 `RGB = srcRGB × dstRGB + dstRGB × (1 − srcAlpha)`、`A = dstAlpha`（预乘值）。现有合成器通过白底 source-over 加 modulate 实现，已验证半透明与透明像素，以及包资源经过真实合成器的输出。截图路径使用同一合成结果。包切换清空角色合成缓存，并拒绝上一代未完成合成任务回填缓存。

参数化 transform、parallel、事件处理和 Python 动画仍未宣布支持。

Web 核心 profile 仅覆盖测试页使用的基础协议。原网页可以原样装入 WebView，但原 NightBoat 页面的完整设置、存档、历史、视频及 WebWith 消息仍需逐项映射。未知消息会显示具体错误，不会静默吞掉。原生 WebView 目前在入口层限定为 Windows/macOS；未验证 Windows 真机和透明合成。

### NVL 映射与状态保存

第三批已映射 YuYuball 的 `nvl`、`nvl2`～`nvl6` 及各自的 `end`。它们属于该引擎的 Web 扩展，不等同于 Ren’Py 自带的 `nvl clear`。源语句映射到 Saki 的 `NvlNode` / `EndNvlNode`，新语法示例：

```text
nvl style:yuyu_nvl2 layout:yu_block_id preserve
nvl style:yuyu_nvl3 layout:yu_random_block preserve replace
endnvl
```

`style` 选择项目呈现方式，`layout` 引用静态预排版数据；`preserve` 保留连续模式的累积段落，`replace` 在下一句替换当前列表。普通 `nvl` 仍保持 Saki 原行为。模式、布局引用、累积规则和每行进入时的模式存入 GameState；BinarySerializer 升级到 v19，同时读取 v18 及更早存档。每行保留原模式，确保 `nvl2 → nvl6` 后旧行的中文引号不被改写。

`mappings/nvl.json` 保存居中模式的 expectedLines。构建阶段先按原 AST 链接 `.next`，再调用 YuYuball 原有只读预读函数，保留同样的终止条件与 1000 节点上限，不执行剧情 Python。网页仍负责字体、逐字动画和随机位置；兼容模块订阅 GameManager 的每次状态发射，防止 Flutter 合并帧时漏掉 `end → begin`。输入继续经过现有 DialogueProgressionManager。

含这些 NVL 指令的 Saki 兼容包必须同时有网页入口、`--web-profile nvl`、`yuyuball-web-nvl-v1` 和 `ui.yuyuball-web-nvl@1`，缺一项即拒绝发布为兼容包。NVL profile 只扩展核心协议中的对白模式数据，不表示原 NightBoat 页面的全部协议已经支持。

### 校验状态的含义

| 状态 | 含义 |
|---|---|
| `incomplete` | 有未映射源行为，不能发布为兼容包 |
| `not-validated` | 原引擎发行包，无已报告映射缺口但未经过 Saki 校验 |
| `converted` | 转换器账本没有未实现项，尚未经过目标解析器 |
| `mapping-validated` | 最终包已通过目标解析与结构/资源校验 |
| `runtimeParity: not-verified` | 尚未通过双引擎画面、时序和恢复对照 |

`mapping-validated` 不表示逐帧或全游戏兼容验收通过。包内目标报告绑定候选包哈希；旁边的 `.validation-report.json` 绑定最终发布包哈希，避免报告写入自身造成循环哈希。

勾选 `.yuyu` 后的包声明 `sourceRuntime.releaseProfile: yuyuball-native-v1` 与 `compatibility.publicationTarget: yuyuball`。原网页使用 `yuyuball-web-native-v1` 标识保留的原端协议，并不声明 Saki Web 能力。`incomplete/not-validated` 均不能进入 Saki 正常播放或目标校验；错误提示用户使用 YuYuball。

## 使用方式

以下 YuYuball 命令在该仓库根目录运行；`--dart` 和 `--saki-root` 按本机路径调整。

```sh
python3 tools/yuyu.py distribute Games/NightBoat \
  --output Builds --platform mac --platform win --yuyu

python3 tools/yuyu.py export tools/tests/fixtures/sequence \
  --output /tmp/YuyuFixture.yuyu \
  --game-id org.yuyu.fixture --name Fixture \
  --saki-root /Library/Afolder/FlutterProject/SakiEngine \
  --dart /Library/Afolder/FlutterProject/flutter/bin/dart \
  --web-profile core

python3 tools/yuyu.py validate /tmp/YuyuFixture.yuyu \
  --saki-root /Library/Afolder/FlutterProject/SakiEngine \
  --dart /Library/Afolder/FlutterProject/flutter/bin/dart

python3 tools/yuyu.py inspect /tmp/YuyuFixture.yuyu
python3 tools/yuyu.py play /tmp/YuyuFixture.yuyu

python3 tools/yuyu.py distribute tools/tests/fixtures/sequence \
  --content /tmp/YuyuFixture.yuyu --output /tmp/YuyuFixture-dist \
  --platform mac --format app-zip
```

`distribute` 和两个启动器的“编译”使用同一发行器，桌面发行的“编译 .yuyu”选项默认关闭；勾选或传入 `--yuyu` 才启用，重新打开启动器即可使用。`--content` 可选，仅用于覆盖为已通过 Saki 校验的内容包。导出命令按需加载构建模块，正常 Launcher 初始化后直接进入发行器；已移除临时的 Python 搜索路径补丁。

Windows 内容位置是程序旁的 `game.yuyu`；macOS 是 `应用.app/Contents/Resources/autorun/game.yuyu`；同次编译额外输出 `Builds/<发行名>.yuyu`，字节与各平台内置内容一致。原文件分类排除规则继续生效，生成缓存/存档不入包，SDK 字体与版本/构建元信息入包并记录 `mappings/distribution.json`。正常工程初始化仍由既有编译流程执行，映射则在独立干净 SDK 中解析。可选 `.yuyu` 格式目前针对标准桌面发行目标，Android/iOS/Web 保留原流程。

在 SakiEngine 的 `Engine/` 目录运行：

```sh
flutter pub get
flutter build macos --release
build/macos/Build/Products/Release/SoraNoUta.app/Contents/MacOS/SoraNoUta \
  --package /tmp/YuyuFixture.yuyu
```

也可使用 `SAKI_YUYU_PACKAGE=/绝对路径/游戏.yuyu` 启动。当前工程生成的应用文件名仍由原项目平台配置决定；包内游戏名在运行时加载。Windows 入口同样接受 `--package`，但本次没有 Windows 构建环境。

Saki 兼容导出失败时会保留 `.mapping-report.json`，退出码为 2，已有正式包不会被替换。SDK 低层 `yuyu-export` 还会输出 `.mapped/` 供审查；普通模式生成候选包，应通过封装命令进行目标校验。发行器内部使用 `--native-release`，包内保留全部未支持诊断，不能借此宣称兼容完成。设计中的独立 `convert` 与 `parity` CLI 尚未实现。

## 本次验证

测试包位于 `Engine/test/fixtures/yuyu/sequence.yuyu`，源小样位于 YuYuball `tools/tests/fixtures/sequence/game/`。小样及小 PNG/网页是新建测试数据。

最终小样 SHA-256：

```text
bc4b7e81dcb7217ad324594157166f28de8e2138a5ae259b49097d959392275e
```

该包有 16 个实际 SKS 节点、5 个标签、1 个顺序动画。它保留原剧情、动画定义、素材和网页，同时包含生成的 SKS 与映射表。

- Python 包/真实 AST/发行集成测试：30 项通过。新增不勾选时保留 RPA 并成功加载、Web 编译消息缺省/勾选/取消的参数转发验证。新增默认发行、原应用自动找包、文件分类排除、SDK 元信息入包、未完成映射的原 RPY 运行和跨进程诊断稳定性回归。新增普通工程模块/包导入、SDK/Launcher 初始化和实际 macOS `.app` 入口回归。新增六模式 AST/预读数据、NVL profile 拒绝路径、原 Web 实现参考数据复现。新增条件层叠、角色与 tag 同名、默认变换优先级、未知属性/混合拒绝和不执行 Python、拒绝初始化前向引用和原始 RPY 加载的回归。包含源快照变化、损坏、路径碰撞、大小限制、原子发布失败保护、曲线配置与继承输出、未支持 ATL 拒绝。
- Flutter 针对包、动画、Web 桥接、显示生命周期及相关原生回归：53 项通过。新增 NVL 六模式执行、逐句原协议数据对照、同帧 end/begin、模式切换、页面快照重放、NVL 首句输入绑定、v19 历史/存档往返、v18 旧存档升级；原生 NVL 的立绘、滚动和右键回归也通过。新增属性继承/移除/重置、快照往返、姓名颜色、混合像素公式和真实合成器输出。包含同背景清场、旧 ticker 取消、换表情继承、舞台留黑边、菜单交互边界、范围资源请求、重复输入与外部视差。
- Saki macOS Debug（首版）和 Release（本轮重建）构建成功。Release 应用约 183.0 MB。
- YuYuball macOS `app-zip` 小样构建成功。检查了包中只有一份 `game.yuyu`、没有散装游戏 RPY，且包含包加载模块；包内内容哈希与 Saki 测试包相同。
- 解开的 YuYuball 发行应用使用 `--package … quit` 成功完成原始脚本加载并退出。SDK 也通过同一方式加载原 RPY。该检查没有验证播放画面。
- Rust Launcher 编译通过；本次没有把仓库的多平台预编译 Launcher 文件全部重建。Python 启动入口也能识别旁边的默认 `game.yuyu`。
- 修改范围的分析没有新增错误。仓库既有 `game_style_dropdown.dart:93` dead_code 警告仍在；全目录分析另有既有 `bin/test_script_modifier.dart:16` 缺少 File 导入的问题。
- 电脑操作工具报告 Mac 锁屏，实际 WebView 窗口、透明叠加与鼠标输入尚未进行人工画面对照，已请求解锁。没有把构建成功当作画面验收成功。

复现测试：

```sh
# YuYuball 仓库根目录
python3 -m unittest discover -s tools/tests -v

# SakiEngine/Engine
flutter test test/yuyu_package_test.dart test/yuyu_animation_test.dart \
  test/yuyu_web_test.dart test/yuyu_display_lifecycle_test.dart test/yuyu_layers_test.dart \
  test/yuyu_nvl_test.dart test/nvl_character_rendering_test.dart \
  test/nvl_auto_scroll_test.dart test/nvl_right_click_ui_test.dart \
  test/animation_persistence_test.dart test/mouse_parallax_bleed_test.dart \
  test/game_manager_choice_seek_test.dart test/virtual_game_canvas_test.dart
```

新增可发布的小样为 `Engine/test/fixtures/yuyu/layered.yuyu`，源为 YuYuball `tools/tests/fixtures/layered/game/`。它包含 20 个目标节点、4 个标签、2 个动画，哈希为 `424b4c5d72bfd3289a5ce2a132c5a30eb4f8c32ae7751abb969e71835e120f49`。同包也已用 YuYuball SDK 的 `--package … quit` 成功加载原始 RPY；这不等同于双端画面对照。

NVL 小样为 `Engine/test/fixtures/yuyu/nvl.yuyu`，源为 YuYuball `tools/tests/fixtures/nvl/game/`。它包含 35 个目标节点、1 个标签，哈希为 `9092008f989d911921ac6724f425bba2ea692c8676ced3649403be4c4246a7d7`，使用 `--web-profile nvl`。同包已通过原 SDK `--package … quit` 加载。SKS 编译器也已将它编译为 Dart，加载编译后的 Dart 后，35 个节点的类型及全部 9 个 NVL 定义参数与解析模式一致。

`nvl-web-reference.json` 来自固定 SDK 的 `web_overlay.show_dialogue` / `set_dialogue_mode`，在干净测试工程内生成；只关闭无窗口环境中的调试编辑器注入，不替换模式和对白函数。Flutter 对每句的完整对白载荷做比较（排除生成 ID 与已读标记）。`native-v18-nvl.sakisav` 使用基线提交的 v18 写入格式生成，含 NVL 活动状态和嵌套历史。协议/状态测试不等同于逐帧视觉一致性，随机布局、真实 WebView、完整读档后的动画相位仍需双端播放验收。

## NightBoat 覆盖结果与剩余任务

真实 AST 扫描覆盖 60 个 RPY 文件，账本 11,586 条记录，未支持诊断先从 6,489 降至 2,922 条，本轮再降至 1,321 条（映射了 1,601 条 NVL 指令）；源文件哈希与上一轮完全一致。摘要及源文件哈希已保存为 [覆盖摘要](yuyu-nightboat-coverage-summary.json)。记录包含 init 包装与级联未解析引用，不代表 6,489 种功能。

NightBoat 的 `characters.rpy`、`yuman.rpy`、`yuman2.rpy` 已无映射诊断。当前主要缺口为 170 条注册指令、541 条未解析图像引用、423 条剧情构造（包含 Python）及动态图像工厂等。尚有 6 条 show 使用未在对应模型中声明的属性（例如 frown_smile、closed_2、shy_smile）；导出器保留诊断，没有替换成猜测表情。其他 layeredimage 结构、扩展音频、项目 Python、转场和 WebWith 仍待实现。第 15 章的部分解析诊断来自干净导出环境未注册项目自己的 `web text` 语句，并非原剧本写错；应增加对应构建适配器，不能改写原剧情来绕过错误。

| 阶段 | 当前状态 | 下一项验收工作 |
|---|---|---|
| P0 映射小样 | 已有真实 AST → 原生 GameManager 小样 | 增加实际项目动作族和条件控制流 |
| P1 动画/层叠 | 顺序 profile、互斥条件层叠、属性继承及指定 multiply 已实现 | 参数实例化、其余层叠结构、并行轨道和实际源画面对照 |
| P2 双内容包 | 已打通；macOS 同包加载与发行结构通过 | 更多真实资源与发布环境、其余缓存跨包隔离和退出清理回归 |
| P3 Web/特效 | 核心宿主、六模式 NVL 协议与快照数据已实现 | 原网页全协议、WebWith、阻塞/取消规则、焦点/IME/透明合成 |
| P4 完整游戏 | 未完成，NightBoat 的 Saki 兼容导出被拒绝 | 补全项目规则、保存兼容状态、读档/回滚/快进与分支回归 |
| P5 发布 | 可选桌面 `.yuyu` 发行已接入，NightBoat 双平台包构建及 macOS 加载通过；整体未完成 | Windows 真机运行、两边画面对照与完整兼容验收 |

此外，动画相位/兼容效果状态尚未接入保存序列化；存档不互通，Saki 原生保存能力不能替代兼容状态验收。包更新后的进度迁移、WebView 崩溃恢复、其余跨包缓存和退出挂载清理仍需完善。当前版本也没有发布签名、像素对照报告或“全部动画忠实映射”的声明。

## 启动器回归修复（2026-09-07）

新增 `yuyu-export` 命令时，`renpy.arguments.pre_init()` 曾直接导入 `yuyu.exporter`。此时 `config.searchpath` 仍为空，导入操作使 RenpyImporter 缓存空的模块索引，随后 Launcher 的 `gui7`、`change_icon`、`installer` 导入失败。此前记录中的“SDK 路径问题”判断不准确，根因是新增命令的加载时机。

现已改为注册轻量命令函数，仅在 `post_init` 执行导出时加载导出器，同时移除 `tools/yuyu.py distribute` 的临时 `sys.path` 包装。新增 `test_yuyu_startup.py` 在修复前复现普通工程及 Launcher 导入失败，修复后 3 项测试通过，覆盖 SDK 根目录、显式 Launcher 目录和现有 macOS `.app` 可执行入口。检查同时验证错误输出和实际 init 完成标记，避免把 Ren’Py 错误界面的零退出码误判为成功。

该修复当时的 24 项 Python 回归全通过；移除路径补丁后重新完成 macOS `.yuyu` 小样发行。现有应用重新启动即加载此修复，无需重建 Saki 播放器。

## 默认桌面编译与 NightBoat 实包验证（2026-09-07）

以下记录保留当天产物；2026-09-08 已按用户要求改为可选，默认不勾选。

此前 Launcher GUI/Web“编译”仍生成散装 `game/`，只有显式 `--yuyu-package` 入口使用新格式；这是“编译的包里没有 `.yuyu`”的直接原因。现已在共用 `Distributor` 中接入默认内容生成，正常编译不再要求先导出兼容小样。

本机产物位于 YuYuball 的 `Builds/`：

| 文件 | 字节数 | 内容位置 |
|---|---:|---|
| `Night_Voyage_0.1.0_20260907.yuyu` | 636,922,390 | 独立完整内容包 |
| `Night_Voyage_0.1.0_20260907_mac.zip` | 637,741,111 | `NightBoat.app/Contents/Resources/autorun/game.yuyu` |
| `Night_Voyage_0.1.0_20260907_win.zip` | 631,402,848 | `Night_Voyage_0.1.0_20260907_win/game.yuyu` |

同次编译仅生成一次内容，三处 `.yuyu` SHA-256 完全一致：

```text
151641f56b9c9c5d030f56198d7ac4e485726caf33304c4d7965ccb323005f57
```

实包包含 1,337 个原始游戏文件（其中 60 个 RPY），并附上 SDK 生成的 `script_version.txt`、`cache/build_info.json` 及映射资料。1,353 个索引载荷均通过校验；编译前后原始文件清单和哈希完全一致；两份平台 ZIP 不再含散装 `game/`。版本/构建时间属于打包元信息，分别运行两次编译的包不要求相同哈希。转换诊断中的 Python AST 内存地址已规范化，避免进程地址造成无意义的差异。

NightBoat 原端包保留 1,322 条目标诊断：原先 1,321 条映射缺口，加上本次未选择 Saki NVL bridge profile 的提示。它使用原端 Web profile，可由 YuYuball 执行原始内容；Saki CLI 对该实际包返回明确拒绝，退出码为 2，没有将未完成映射标记为兼容成功。

验证包括 28 项 Python 回归、4 项 Flutter 包测试及相关文件的 Dart 静态分析。新增发行集成测试通过正常 Launcher 命令构建，验证自定义排除规则、缓存排除、独立副本、SDK 元信息和原 `.app` 自动找包；没有传入 `--package`，用原脚本 init 标记确认实际加载。已有显式 Saki 已校验包发行入口也重新构建通过。

最终 NightBoat macOS ZIP 解压后，实际应用使用 `quit --savedir <临时目录>` 自动找到内置包、完成原始脚本初始化并正常退出。该检查不等同于全流程游玩或画面对照；Windows 本轮只有打包和结构校验，没有 Windows 真机运行。机器可读结果见 [发行验证记录](yuyu-nightboat-distribution-verification.json)。

## 可选编译开关（2026-09-08）

原生构建页“Options”及 Web 构建页新增“编译 .yuyu”，初始关闭。未勾选时直接使用既有文件分类、RPA 打包和平台发行流程；勾选时才生成内容包、替换散装 `game/` 并输出独立副本。CLI `distribute` 同样默认普通发行，使用 `--yuyu` 启用内容包；已有 `--content` / `--yuyu-package` 已校验内容覆盖入口保持有效。Web 切换工程后取消该选项，缺省或 false 的消息不会启用；非布尔值拒绝处理。

回归测试使用独立小样分别构建两种模式并加载原应用。普通模式验证原脚本、RPA 素材可读取，ZIP 内及本次输出均无 `.yuyu`；选中模式验证内容包及自动挂载。Python 共 30 项通过，网页脚本语法检查通过。本轮未重建或覆盖 NightBoat 既有发行产物，也未修改新增剧情与素材。
