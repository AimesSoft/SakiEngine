# SakiEngine Sample Game

这是示例游戏 Flutter 项目（独立可运行），通过 `sakiengine` 包加载引擎核心。

- 引擎依赖: `../../Engine`
- 资源目录: `Assets/`、`GameScript*/`
- 默认项目标识: `default_game.txt`

启动方式（在本目录）:

```bash
flutter pub get
flutter run -d macos --dart-define=SAKI_GAME_PATH="$(pwd)"
```
