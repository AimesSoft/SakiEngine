<p align="center">
  <img src="Git/readme-banner.svg" alt="SakiEngine — Cross-platform visual novel engine" width="100%">
</p>

<h1 align="center">SakiEngine</h1>

<p align="center">
  <b>A cross-platform visual novel engine built with Flutter</b><br>
  SKS scripts · Fluid layouts · Vector UI · Cross-platform builds<br>
  Windows · macOS · Linux · Android · iOS · Web
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-545C91?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Built with Flutter"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-6B82A8?style=flat-square&amp;logo=dart&amp;logoColor=white" alt="Written in Dart"></a>
  <a href="Engine/packages/saki_native"><img src="https://img.shields.io/badge/Rust-native_services-B88D83?style=flat-square&amp;logo=rust&amp;logoColor=white" alt="Rust native services"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-91A891?style=flat-square" alt="MIT License"></a>
  <a href="https://github.com/AimesSoft/SakiEngine/commits/main"><img src="https://img.shields.io/badge/Status-in_development-D6A0B6?style=flat-square" alt="Actively growing"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#interface">UI and extensions</a> ·
  <a href="#performance">Performance and memory</a> ·
  <a href="#features">Features</a> ·
  <a href="#launcher">Launcher</a> ·
  <a href="#shortcuts">Shortcuts</a> ·
  <a href="#build">Release modes</a> ·
  <a href="docs/script-guide.md">Script guide (中文)</a> ·
  <a href="docs/development.md">Development (中文)</a> ·
  <a href="https://github.com/AimesSoft/SakiEngine/issues">Issues</a>
</p>

---

## Overview

SakiEngine is an open-source visual novel engine built with **Flutter / Dart**, designed for high-performance native execution and supporting **Windows, macOS, Linux, Android, iOS and Web**.

It uses `.sks` scripts for dialogue, branching and scene direction, with audio, video, localization, saves and rollback. The graphical launcher manages project creation, execution and packaging. Built-in editors support script and scene editing during gameplay, while Flutter modules provide custom interfaces and project logic.

Video playback is powered by **[Erika](https://github.com/AimesSoft/Erika), a Rust media player kernel developed in-house by AimesSoft**, providing the foundation for video-based scenes.

The name **Saki** comes from **Saki Watanabe (渡辺早季)** in *From the New World* (*Shinsekai Yori* /《来自新世界》).

<a id="interface"></a>

## UI, ecosystem and system integration

SakiEngine gives game projects access to **Flutter's layouts, drawing tools, package ecosystem and platform APIs**, supporting complete application interfaces and desktop interactions alongside visual novel scenes.

- **Fluid, adaptive layouts**: Components can reflow, wrap and resize with the available space. Settings pages switch between one and two columns, while the game canvas uses logical resolution and aspect-ratio adaptation to accommodate window changes and scene composition.
- **Vector-drawn UI**: Text, icons, paths and SVG graphics can be drawn at the target size to stay sharp on high-DPI displays and resized windows. Custom drawing, animation and themes support distinctive menus, controls and interactions.
- **A broad package ecosystem**: Use Flutter / Dart packages from [pub.dev](https://pub.dev) to integrate animation, networking, storage and platform services through `ProjectCode`. Extend project interfaces, themes and logic with standard Flutter components.
- **Native OS integration**: Text input, focus, clipboard access and desktop shortcuts work alongside platform-appropriate save and log storage and tools that open the system file manager. Flutter plugins and platform channels provide access to further system APIs.
- **Flexible window controls and extensions**: Desktop support includes windowed / fullscreen modes, `5:4` / `16:10` / `16:9` presets, aspect-preserving maximize and restore, fitting to the current display's work area and custom close confirmation. Projects can add always-on-top behavior, system trays and other desktop features through community plugins.

Desktop window controls target Windows, macOS and Linux; mobile and Web use their respective platform capabilities. Select and integrate community plugins for your target platforms. See [UI and system extensions (中文)](docs/development.md#interface).

<a id="performance"></a>

## High performance and low memory overhead

**Dart AOT and native Rust execution** reduce script and data-processing overhead, while the in-house **Erika** kernel provides native video playback. **In the author's tests with both engines using Release builds, an empty SakiEngine project used approximately half the memory of an empty Ren’Py project.**

<a id="features"></a>

## Features

| Area | Available features |
| --- | --- |
| **Story and reading** | SKS dialogue, choices and conditional jumps; standard, NVL and cinematic narration; auto-play, skip, history, rollback, `.sakisav` saves and read tracking |
| **Characters and scenes** | Automatic positioning, poses, expressions and a second overlay layer; CGs, animated WebP, transitions, filters, mouse parallax and project-defined canvases |
| **Sound and video** | Music, sound effects and voice controls; video scenes powered by the in-house Erika player kernel, with looping, sequencing and alpha-video options, subject to platform support |
| **Localization** | Simplified Chinese, Traditional Chinese, English and Japanese in the same script line; fallback text, a translation editor and a single-language script view |
| **Live editing** | Desktop Debug and Showcase tools for script editing, expression previews, canvas placement and developer controls; save and reload to preview changes |
| **Project extensions** | Launcher project management and creation; `ProjectCode` themes, screens and script extensions; extra settings tabs and Steam achievement integration |
| **Runtime and delivery** | SKS precompilation, SakiPack resource bundles and Rust services for asset indexes, saves, script indexes and history snapshots |

Platform SDKs, signing requirements and output locations are covered in [Development and releases (中文)](docs/development.md).

### Erika media player kernel

**Erika** is a media player kernel written in Rust. SakiEngine integrates it through the `erika_flutter` bridge for video playback, native rendering and playback timing.

Built on Erika, the engine provides background video, looping, clip sequencing, playback speed control, alpha video, blend modes and opacity settings for integrating video into scenes. Capabilities vary by platform backend; see [Media and native dependencies (中文)](docs/development.md#媒体与原生依赖) for integration details.

<a id="launcher"></a>

## Launcher

**SakiEngine Launcher** provides project management, execution and build controls. It scans `Game/`, creates projects, sets the default project, selects run devices and displays logs. The project generator uses a name, Bundle ID and theme color to create scripts, configuration, assets and a `ProjectCode` package.

Run configurations and build modes are separate controls:

| Run configuration | When to use it |
| --- | --- |
| **Debug** | Develop engine or project code with Flutter hot reload, hot restart and engine authoring tools |
| **Showcase / 演出模式** | Run with Release compilation while retaining direct script loading, script reload and authoring tools for dialogue, expressions, backgrounds and music |
| **Profile** | Run through the release asset pipeline to investigate performance closer to a release build |
| **Release** | Run through the release asset pipeline to check the player-facing version |

The **embedded console** provides task logs, Debug hot reload / restart, safe restart, quit and log copying. The **system terminal** supports Flutter's `r` / `R` / `q` controls; Profile / Release runs using the release asset pipeline require the embedded console. Builds offer Release and Showcase modes, then create a ZIP and open the output folder. See [Release modes](#build) below.

<a id="quick-start"></a>

## Quick start

Prepare Git and your target platform's development tools. Native game builds also need **Rust / rustup**. Use Flutter with **Dart 3.10.4 or a newer 3.x release** to satisfy the current launcher and demo constraints.

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

The entry scripts use system Node.js and Flutter when available, otherwise downloading local copies into the repository. They do not install Rust, system compilers or platform SDKs, or upgrade an outdated system Flutter. For Windows desktop, install Visual Studio's **Desktop development with C++** workload. macOS / iOS require Xcode and, where needed, CocoaPods; Android requires its SDK, JDK and NDK; Linux needs Flutter desktop build dependencies and GStreamer audio dependencies. See the [environment guide (中文)](docs/development.md#准备环境).

Select **SakiEngine** in the launcher to run the demo, or create a new project. Direct demo launch commands:

```powershell
# Windows
.\saki.bat SakiEngine
```

```bash
# macOS / Linux
./saki.sh SakiEngine
```

### SKS script example

This example uses the demo's `yk` character and `bg school` background. SKS borrows writing conventions from Ren’Py, with its own parser and runtime.

```sks
label start
scene bg school with dissolve
yk pose2 happy "This example demonstrates a branching menu."

menu
"Character dialogue" dialogue_branch
"Narration" narration_branch
endmenu

label dialogue_branch
yk "This is the character dialogue branch."
return

label narration_branch
"This is the narration branch."
return
```

See the [complete demo script](Game/SakiEngine/GameScript/labels/start.sks) and the [SKS guide (中文)](docs/script-guide.md).

### Script localization

```sks
yk "/zhs 你好。/ /zhc 你好。/ /en Hello./ /jp こんにちは。/"
```

Language segments work in dialogue, choices and character display names. Missing translations fall back according to `script_default_language`. You can add translations gradually, as in `"Hello. /jp こんにちは。/"`, with `script_default_language: en` in your project's `GameScript/configs/configs.sks`. The Japanese script tag is `jp`.

<a id="build"></a>

## Build and release modes

The launcher offers two build modes. Both compile a Release executable, with different resource layouts and authoring tools:

| Aspect | Release mode | Showcase mode |
| --- | --- | --- |
| Purpose | Distribute the finished game to players | Continue scene editing with writers, directors and testers |
| Story | Precompile SKS into Dart and execute compiled story data | Skip SKS precompilation and retain direct script loading and reload |
| Resources | Native targets use `game.sakipak`; Web retains browser-accessible resources | Desktop output includes external `Game/<project>/Assets` and `GameScript*` directories |
| Authoring tools | Disabled; the `console` log entry remains available | Enabled, including scene-editing shortcuts |
| Packaging | ZIP named with the game, version and build date | The same ZIP convention with a `-showcase` suffix |

Desktop Showcase mode lets you change scripts and resources without recompiling the executable; Dart code changes still need a rebuild. To publish, choose **Build mode → Release mode → Build target → Release build** in the launcher. The output folder opens when the build finishes.

Choose a build target in the launcher, or use an installed Node.js:

```bash
node tool/saki_cli.js build
# Example: build the demo on Windows
node tool/saki_cli.js build SakiEngine windows
```

| Platform | Delivery |
| --- | --- |
| Windows | Desktop application; native Windows build or cross-build from macOS |
| macOS | macOS application built with Flutter / Xcode |
| Linux | Desktop application; native Linux build or cross-build from macOS |
| Android | The current build script produces an ARM64 APK |
| iOS | Build on macOS; current builds are unsigned, so complete signing for distribution |
| Web | Static site in `build/web`; deploy to a web server for browser play |
| macOS → Windows / Linux | x64 cross-build path requiring an exact match between the Flutter SDK, target packs and native plugin set |

Output lives under `Game/<project>/build/`. Launcher ZIPs are placed in the corresponding output folder's parent directory. CLI `build` uses the release pipeline; use Launcher for Showcase builds and automatic ZIP packaging. The cross-build [manifest](toolchains/cross/manifest.json) currently pins **Flutter 3.44.0**. Outdated packs or mismatched plugins are rejected and need rebuilding.

The independent-game CI template still pins Flutter **3.35.1**, which does not meet the current demo's Dart requirement. Update and verify the template before using it for releases. Output paths, packaging and CI details are in [Development and releases (中文)](docs/development.md).

<a id="shortcuts"></a>

## Shortcuts and controls

### Reading and general controls

| Input | Action |
| --- | --- |
| `Enter` / `Space` / Down arrow / Scroll down | Reveal the current dialogue or advance the story |
| Up arrow / Scroll up | Roll back or open history, according to settings |
| Hold `Ctrl` / `Command` | Force skip; release to stop |
| Right-click | Hide / restore the game UI, or close a supported overlay |
| `Esc` | Close the current authoring tool or supported overlay |
| Type `console` in sequence | Open the log panel, including in release builds; use no modifiers and leave no more than 3 seconds between keys |

### Authoring and scene editing

These built-in controls are available in **desktop Debug / Showcase mode**. Focus the game window first; global shortcuts that would interfere with text input pause while editing.

| Shortcut | Tool |
| --- | --- |
| `Shift + R` | Reload the current script to pick up story and resource edits on disk |
| `Shift + A` | Expression / pose wheel; release Shift to apply the selection |
| `Shift + C` | Speaker / narrator wheel for the current line; release Shift to apply |
| `Shift + B` | Background grid; preview and double-click to apply |
| `Shift + 1` | Music grid; listen and double-click to apply |
| `Shift + V` | Project canvas grid; preview and double-click to place |
| `Shift + E` | Full expression picker with separate base and overlay previews |
| `Shift + D` | Developer panel |
| `Shift + P` | Script editor with full-source and single-language views |
| `Shift + L` | Translation editor for dialogue and character names |

Background, music and canvas grids stay open after releasing Shift; use the same shortcut or `Esc` to close them. Wheels apply on Shift release. Projects can register additional Shift shortcuts through `GameModule.debugCommandMenus`. `Shift + R` reloads game scripts; it is distinct from Flutter terminal `r` hot reload and `R` hot restart.

<details>
<summary>Complete editor shortcuts</summary>

`Mod` means `Ctrl` on Windows / Linux and `Command` on macOS.

| Shortcut | Action |
| --- | --- |
| `Mod + S` | Save and reload in both script and translation editors |
| `Mod + W` / `Esc` | Close the editor; Esc closes script search first, and the translation editor prompts about unsaved changes |
| `Mod + F` | Open script search |
| `Mod + G` / `F3` | Next search match, or open search if it is closed |
| `Mod + Shift + G` / `Shift + F3` | Previous search match |
| `Mod + /` | Toggle comments on selected script lines |
| `Mod + Z` | Undo script edits |
| `Mod + Shift + Z` / `Mod + Y` | Redo script edits |
| `Mod + A` / `C` / `X` / `V` | Select all / copy / cut / paste |

Saving checks for external file changes; a conflict preserves your draft and asks you to resolve it.

</details>

<a id="showcase"></a>

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="Git/main.png" alt="Game showcase: main menu" width="100%"></td>
    <td width="50%"><img src="Git/say.png" alt="Game showcase: character sprites and dialogue" width="100%"></td>
  </tr>
  <tr>
    <td align="center">Main menu</td>
    <td align="center">Characters and dialogue</td>
  </tr>
  <tr>
    <td width="50%"><img src="Git/history.png" alt="Game showcase: dialogue history" width="100%" loading="lazy"></td>
    <td width="50%"><img src="Git/dialog.png" alt="Game showcase: return-to-menu confirmation dialog" width="100%" loading="lazy"></td>
  </tr>
  <tr>
    <td align="center">Dialogue history</td>
    <td align="center">Confirmation dialog</td>
  </tr>
</table>

<p align="center"><sub>Existing project screenshots from this repository. Each game can supply its own theme and interface.</sub></p>

<a id="explore"></a>

## Documentation and examples

| Resource | Contents |
| --- | --- |
| [SKS guide (中文)](docs/script-guide.md) | Scenes, expressions, animations, canvases, text effects, transitions and localization |
| [Development and releases (中文)](docs/development.md) | Toolchains, CLI, project structure, modules, SakiPack and builds |
| [Demo project](Game/SakiEngine) | An editable project included in the repository |
| [SoraNoUta](https://store.steampowered.com/app/3536120/) | A game built with SakiEngine, available on Steam · [Source repository](https://github.com/MCDFsteve/SoraNoUta-SakiEngine) |
| [VS Code extension](vscode-sakiengine-syntax) | SKS highlighting; choose **Install from VSIX** and select the newest `.vsix` in this directory |
| [Rust native services](Engine/packages/saki_native/README.md) | Asset and script indexes, saves, history snapshots and read tracking |

## Feedback and contributions

Submit bugs, feature requests and translation corrections through [Issues](https://github.com/AimesSoft/SakiEngine/issues), or contribute code and documentation through Pull Requests. Bug reports should include the operating system, launch command, reproduction steps and relevant logs.

## License

Engine code is released under the [MIT License](LICENSE). Third-party dependencies and game assets retain their own licenses; check those when distributing a game.
