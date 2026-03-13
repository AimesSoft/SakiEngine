#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/Launcher"
REPO_ROOT="$(cd .. && pwd)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "错误: 未检测到 flutter，请先安装并配置 Flutter SDK。"
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    PREFERRED_DEVICE="macos"
    ;;
  Linux)
    PREFERRED_DEVICE="linux"
    ;;
  *)
    PREFERRED_DEVICE="chrome"
    ;;
esac

DEVICE=""
if flutter devices --machine | grep -Eq "\"id\"[[:space:]]*:[[:space:]]*\"${PREFERRED_DEVICE}\""; then
  DEVICE="$PREFERRED_DEVICE"
elif flutter devices --machine | grep -Eq "\"id\"[[:space:]]*:[[:space:]]*\"chrome\""; then
  DEVICE="chrome"
fi

if [ -z "$DEVICE" ]; then
  echo "错误: 未检测到可用运行设备（${PREFERRED_DEVICE}/chrome）。"
  flutter devices
  exit 1
fi

echo "使用设备: $DEVICE"

flutter pub get
flutter run -d "$DEVICE" --dart-define=SAKI_REPO_ROOT="$REPO_ROOT"
