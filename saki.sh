#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
TARGET_GAME="${1:-}"

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

if [ -n "$TARGET_GAME" ]; then
  GAME_DIR="$REPO_ROOT/Game/$TARGET_GAME"
  BRIDGE_SCRIPT="$REPO_ROOT/scripts/launcher-bridge.js"

  if [ ! -f "$GAME_DIR/pubspec.yaml" ]; then
    echo "错误: 指定项目不存在或不是 Flutter 项目: $TARGET_GAME"
    echo "可用项目:"
    while IFS= read -r -d '' candidate; do
      if [ -f "$candidate/pubspec.yaml" ]; then
        echo "  - $(basename "$candidate")"
      fi
    done < <(find "$REPO_ROOT/Game" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    exit 1
  fi

  echo "直启游戏项目: $TARGET_GAME"

  if command -v node >/dev/null 2>&1; then
    node "$BRIDGE_SCRIPT" prepare-project --game "$TARGET_GAME"
  else
    echo "警告: 未检测到 node，跳过项目准备步骤（应用身份/图标同步）。"
  fi

  cd "$GAME_DIR"
  flutter pub get

  if command -v node >/dev/null 2>&1; then
    node "$BRIDGE_SCRIPT" prepare-project --game "$TARGET_GAME" --generate-icons
  fi

  flutter run -d "$DEVICE" --dart-define=SAKI_GAME_PATH="$GAME_DIR"
  exit $?
fi

cd "$REPO_ROOT/Launcher"
flutter pub get
flutter run -d "$DEVICE" --dart-define=SAKI_REPO_ROOT="$REPO_ROOT"
