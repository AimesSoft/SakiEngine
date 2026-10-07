# SakiEngine 开发启动器

该目录是 SakiEngine 的图形化开发启动器（Flutter 项目），在桌面端统一完成项目创建、运行预览、演出调试和发布构建。游戏可面向 Windows、macOS、Linux、Android、iOS 与 Web 发布，启动器根据宿主环境提供对应目标。

[返回引擎首页](../README.md#launcher) · [完整开发与发布指南](../docs/development.md) · [游戏内快捷键](../README.md#shortcuts)

## 主要功能

- 扫描 `Game/*` 并选择默认项目
- GUI 创建新项目（非交互桥接 `scripts/create-new-project.js`）
- 选择运行设备，以及 Debug / 演出 / Profile / Release 四种运行配置
- 内置控制台与系统终端两种运行方式；显示和复制日志，支持 Debug 热重载 / 热重启、安全重启与退出
- 选择发布模式或演出模式构建，构建前执行 `flutter clean`，完成后生成 ZIP 并打开产物目录

## 运行配置

| 配置 | 行为 |
| --- | --- |
| Debug | Flutter Debug，支持代码热重载 / 热重启和引擎编辑器 |
| 演出模式 | 使用 Release 编译，保留脚本直读、引擎重载与编辑工具 |
| Profile | 使用发布资源管线，以 Profile 配置观察性能 |
| Release | 使用发布资源管线，预览玩家版本 |

Profile / Release 的发布资源运行管线需要内置控制台。系统终端可使用 Flutter 的 `r` / `R` / `q`，其中代码热重载 / 热重启用于 Debug；游戏内的 `Shift + R` 则重载剧本。

## 构建模式

**发布模式**将 SKS 预编译为 Dart，原生平台生成 SakiPack，Web 保留浏览器资源，关闭引擎创作工具，适合交付玩家。

**演出模式**同样生成 Release 程序，但开启引擎创作工具，不预编译 SKS。桌面产物旁会附带 `Game/<项目>/Assets/`、`GameScript*` 和相关配置，方便修改脚本或素材后直接重载。Dart 代码改动仍需重新构建。

两种模式都会生成带作品名、版本和日期的 ZIP，演出包加上 `-showcase` 后缀。`console` 日志入口在两种模式下都可使用。

## 启动方式

推荐在仓库根目录执行：

```bash
./saki.sh

# 直启指定项目（跳过 Launcher UI）
./saki.sh SakiEngine
./saki.sh <项目名>
```

Windows:

```bat
saki.bat
saki.bat SakiEngine
saki.bat <项目名>
```

首次运行会自动引导工具链：

- 系统已安装 Flutter/Node.js 时直接使用系统环境
- 系统缺失时自动下载到仓库内 `.saki_toolchain/` 并继续启动

脚本说明：

- `saki.sh / saki.bat` 仅负责入口转发
- 业务逻辑集中在 `tool/saki_cli.js`（跨平台）
