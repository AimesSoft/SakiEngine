# SKS 脚本与创作指南

[← 返回首页](../README.md) · [开发与发布](development.md)

本文介绍 SKS 的对白、分支、场景、差分、动画和多语言语法。完整示例见 [演示剧本](../Game/SakiEngine/GameScript/labels/start.sks)，角色、站位与动画定义见 [配置目录](../Game/SakiEngine/GameScript/configs)。

代码里的资源名用于说明语法，使用前请替换为项目已有资源。

**快速导航：** [对白与分支](#脚本语法示例) · [多语言](#脚本内嵌多语言) · [图像与差分](#图像绘制语法) · [文字效果](#文本标签语法) · [转场](#转场效果语法)

## 脚本语法示例

SakiEngine 使用 `.sks` 脚本文件。语法借鉴 Ren’Py，但两者的脚本并不直接兼容。下面的角色与资源 ID 需要在项目中定义：

```sks
// 开始标签
label start
// 设置背景场景
scene bg school

// 角色对话（角色标识 姿势 表情 对话）
yk pose2 happy "欢迎来到SakiEngine！"

// 选择菜单
menu
"给她巧克力" choice_chocolate
"保持沉默" choice_silence
"表情测试" choice_expressions
endmenu

// 巧克力选项
label choice_chocolate
yk "呀，谢谢！"
"嘿嘿，喜欢吗？"
yk happy "当然喜欢！"
return

// 沉默选项
label choice_silence
yk sad "你怎么不说话？"
yk "不理你了。"
return

// 表情变化
label choice_expressions
yk pose1 "这是不同的姿势和表情"
yk happy "开心的表情"
yk sad "难过的表情"
return
```

## 脚本内嵌多语言

SakiEngine 支持在同一条 `""` 文本中写多语言片段，运行时只显示当前语言对应内容：

```sks
yk "/zhs 你好/ /zhc 你好呀/ /jp こんにちは/ /en Hello/"
```

也支持“已有文本 + 新增语言片段”的渐进写法（默认语言文本无需立刻包 `/zhs.../`）：

```sks
yk "你好 /en Hello/"
```

默认脚本语言可在 `GameScript/configs/configs.sks` 中设置：

```sks
script_default_language: zhs // zhs / zhc / en / jp
```

说明：

- 对 `.sks` 中所有 `""` 包裹文本生效（如对话、`menu` 选项、角色配置显示名等）
- 推荐语法是 `/tag 文本/ /tag 文本/`；写成紧贴的 `...//tag .../` 也会被兼容解析
- 如果当前语言缺失对应片段，会按默认脚本语言回退
- 不含语言标记的旧文本会保持原样显示（兼容旧项目）

桌面 Debug 或演出模式提供两种编辑视图：

- **Shift+L 多语言编辑器**：读取 `GameScript` 中的对白、条件对白和旁白，按文件逐句展示。每种语言单独一行，角色名与正文均可编辑；角色名写回 `configs/characters.sks`，同一角色别名的其他句子同步更新。菜单和演出命令不混入剧情列表。
- 可勾选显示简体中文、繁体中文、日语和英语。点击「新增语言」会为所有剧情句子和角色名添加该语言的空白行，填写后保存；空白翻译在游戏中仍使用原有回退规则。
- **Shift+P 脚本编辑器**：路径栏的语言菜单可切换单语言视图或「完整源码」。编辑单语言文本时会保留其他语言版本及演出指令，切换语言也会保留草稿。缺少的翻译显示为空，避免将原文误认为已翻译内容。
- **⌘/Ctrl+S** 保存并重载；多语言编辑器关闭时会提示处理未保存修改。保存前检查磁盘文件是否被其他编辑器修改，冲突时保留草稿。

行内翻译仍遵循 SKS 引号和 `/tag 文本/` 语法：正文使用中文引号或 `「」`，标签内的斜杠使用全角 `／`，文本换行使用字面量 `\n`。

## 图像绘制语法

SakiEngine 支持五种主要的图像显示方式：

### 场景背景 (scene)

```sks
// 显示背景图片，自动铺满窗口
scene bg school          // 显示学校背景，铺满整个窗口
scene bg sunset_beach    // 显示夕阳海滩背景，自动缩放适配
```

### 角色立绘 (show)

```sks
// 显示角色立绘，自动调节窗口内站位
show yk pose1 happy      // 显示yk角色，引擎自动分配站位
show alice pose2 sad     // 显示alice角色，自动与其他角色协调位置
show character          // 多角色同时显示时自动分配最佳站位
```

### 第二层差分（叠加层）

角色差分支持两层：第一层是基础表情，第二层叠加绘制在它之上。剧本里把第二层直接
接在第一层后面即可：

```sks
x happy                  // 只换第一层，当前第二层保留
x happy mask             // happy 作为第一层，mask 作为第二层盖在它上面
x happy --mask           // 与上一行等价（显式层级前缀）
x happy angry            // 换成另一组两层
x happy --none           // 只摘掉第二层，保留第一层 happy
```

对应的文件命名：

| 层级 | 文件名示例 | 说明 |
|---|---|---|
| 第一层 | `xiayo1-happy.png` | 基础表情 |
| 第二层 | `xiayo1--mask.png` | 叠加层，盖在第一层之上 |

第二层是"叠加"语义：只写第一层时角色当前的第二层会被保留，只有显式写出第二层
或 `--none` 才会改动它。显式写出的第二层如果缺图，引擎会跳过该层而不是换成别的
差分。Debug 或演出模式下按 `Shift+E` 打开差分选择器，第一层与第二层各有独立的展示与
预览区域。

### 动画效果 (anime)

```sks
// 播放WebP动图，自动铺满窗口，默认播放一次后消失
anime flash_effect       // 播放闪光动画，播放完自动消失
anime explosion          // 播放爆炸效果，默认一次性播放

// 使用参数控制播放行为
anime rain keep          // 播放雨滴动画，播放完后保持显示
anime fire loop          // 播放火焰动画，循环播放不停止
anime magic keep loop    // 播放魔法效果，循环播放且保持显示
```

### 项目画布 (canvas)

```sks
// 显示项目模块注册的持续绘制效果；覆盖游戏画面，但不遮挡 UI
canvas pixel_rain

// 清除当前画布
hide canvas
```

项目通过 `GameModule.scriptCanvases` 注册画布 ID、显示名与绘制回调。Debug 或演出
模式下按 `Shift+V` 可打开画布预览/放置网格，双击把命令放到当前对话前。

### CG插图 (cg)

```sks
// 显示CG图片，结合scene和show特性：铺满窗口 + 自动识别切换
cg ending_kiss          // 显示CG，自动铺满窗口
cg battle_scene         // CG会自动识别和切换到对应场景
cg romantic_moment      // 支持CG之间的自动过渡和识别
```

## 文本标签语法

SakiEngine 支持在对话文本中使用特殊标签来控制显示效果：

### 等待标签 [w]

```sks
// 在指定位置暂停文字显示
yk "你好...[w=1]我是小雪。"        // 在省略号后暂停1秒
alice "等等[w=5]让我想想..."       // 在"等等"后暂停5秒文字显示
```

### 文字大小标签 [size]

```sks
// 改变文字大小
"这是[size=1.3]大字[/size]和正常字。"     // 显示大字
"[size=0.8]小字提示[/size]正常对话"       // 显示小字
"[size=1.5]重要提醒！[/size]"             // 显示更大的字
```

### 快进标签 [pass]

```sks
// 跳过打字机效果，瞬间显示文字
"[pass]这段文字会瞬间显示出来！[/pass]"          // 整句瞬间显示
"正常显示[pass]后面瞬间显示[/pass]"             // 部分瞬间显示
```

## 转场效果语法

SakiEngine 支持多种场景转场效果，使用 `with 转场类型` 语法：

### 淡入淡出 (fade)

```sks
// 黑屏淡入淡出转场，经典过渡效果
scene sky with fade           // 先淡出到黑屏，再淡入新场景
```

### 溶解 (diss/dissolve)

```sks
// 图片直接渐变过渡，无黑屏阶段
scene home with diss          // 旧场景溶解到新场景
scene school with dissolve    // 支持 dissolve 别名
```

### 擦除 (wipe)

```sks
// 旋转扇形擦除效果，适合时空转换
scene flashback with wipe     // 扇形旋转覆盖并显示新场景
```

### 睁眼 (blink/eyeopen)

```sks
// 从黑屏睁眼显示场景，不会遮挡UI
scene bedroom with blink      // 适合醒来场景
scene reality with eyeopen    // 从梦境/回忆回到现实
scene world with eye          // 支持简写别名
```

**睁眼转场特点：**

- 从完全黑屏开始（已经闭眼状态）
- 上下遮罩移开，逐渐显示新场景
- **不会遮挡UI**（对话框、菜单等保持可见）
- 只有睁眼过程，没有闭眼过程

**睁眼转场适用场景：**

- 角色从睡梦中醒来
- 失去意识后恢复
- 从回忆/幻觉回到现实
- 从黑屏过渡到新场景

### 转场效果对比表

| 转场类型 | 关键词 | 视觉效果 | 是否遮挡UI | 适用场景 |
|---------|--------|---------|-----------|---------|
| 淡入淡出 | `fade` | 黑屏渐变 | 遮挡 | 通用场景切换 |
| 溶解 | `diss`, `dissolve` | 图片直接渐变 | 不遮挡 | 平滑的场景过渡 |
| 擦除 | `wipe` | 旋转扇形擦除 | 遮挡 | 时空转换、特效 |
| 睁眼 | `blink`, `eyeopen`, `eye` | 黑屏入，上下移开 | **不遮挡** | 醒来、恢复意识 |

## 语法特点

- **无需缩进**：所有命令都在同一级别
- **使用 `//` 注释**：支持单行注释说明
- **简单的角色对话语法**：角色名 + 可选姿势 + 可选表情 + 对话内容
- **灵活的图像控制**：支持背景、立绘、动画、CG等多种显示方式
- **富文本标签**：支持等待、大小、快进等文字效果
- **直观的选择菜单系统**：menu/endmenu 包围选择项
