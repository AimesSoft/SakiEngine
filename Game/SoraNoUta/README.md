# SoraNoUta

这是独立的 Flutter 项目层仓库结构（可直接 `flutter run`）。

- 引擎依赖: `../../Engine`（`sakiengine` 包）
- 项目代码包: `./ProjectCode`（`soranouta_project`）
- 资源目录: `Assets/`、`GameScript*/`
- 默认项目标识: `default_game.txt`

启动方式（在本目录）:

```bash
flutter pub get
flutter run -d macos --dart-define=SAKI_GAME_PATH="$(pwd)"
```
