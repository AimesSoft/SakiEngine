# test

这是独立 Flutter 项目层目录（可直接运行）。

- 引擎依赖: `../../Engine`
- 项目代码包: `./ProjectCode`
- 资源目录: `Assets/`、`GameScript*/`
- 默认项目标识: `default_game.txt`

快速启动:

```bash
flutter pub get
flutter run -d macos --dart-define=SAKI_GAME_PATH="$(pwd)"
```
