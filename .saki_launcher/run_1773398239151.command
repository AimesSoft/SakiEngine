#!/usr/bin/env bash
set -euo pipefail

cd '/Library/Afolder/FlutterProject/SakiEngine'
node '/Library/Afolder/FlutterProject/SakiEngine/scripts/launcher-bridge.js' prepare-project --game 'SoraNoUta'
cd '/Library/Afolder/FlutterProject/SakiEngine/Game/SoraNoUta'
flutter pub get
node '/Library/Afolder/FlutterProject/SakiEngine/scripts/launcher-bridge.js' prepare-project --game 'SoraNoUta' --generate-icons

echo ""
echo "启动 Flutter 运行（支持 r/R/q 热更新命令）..."
set +e
flutter run -d 'macos' '--dart-define=SAKI_GAME_PATH=/Library/Afolder/FlutterProject/SakiEngine/Game/SoraNoUta'
status=$?
set -e

echo ""
echo "运行已结束（退出码: $status）"
read -r -p "按回车关闭终端..." _
exit $status
