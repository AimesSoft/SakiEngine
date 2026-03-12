#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "${1:-}" ]; then
  echo -e "${RED}错误: 请提供平台参数 (macos, linux, windows, android, ios, web)。${NC}"
  exit 1
fi

PLATFORM="$1"

cd "$(dirname "$0")"
PROJECT_ROOT=$(pwd)
DEFAULT_GAME_FILE="$PROJECT_ROOT/default_game.txt"
source "$PROJECT_ROOT/scripts/asset_utils.sh"

if [ ! -f "$DEFAULT_GAME_FILE" ]; then
  echo -e "${RED}错误: 未找到 default_game.txt。${NC}"
  exit 1
fi

GAME_NAME=$(tr -d '\r\n' < "$DEFAULT_GAME_FILE" | xargs)
if [ -z "$GAME_NAME" ]; then
  echo -e "${RED}错误: default_game.txt 为空。${NC}"
  exit 1
fi

GAME_DIR="$PROJECT_ROOT/Game/$GAME_NAME"
if [ ! -d "$GAME_DIR" ]; then
  echo -e "${RED}错误: 游戏目录不存在: $GAME_DIR${NC}"
  exit 1
fi

if [ ! -f "$GAME_DIR/pubspec.yaml" ]; then
  echo -e "${RED}错误: $GAME_DIR 不是 Flutter 项目（缺少 pubspec.yaml）${NC}"
  exit 1
fi

echo -e "${GREEN}使用游戏项目: $GAME_NAME${NC}"

GAME_CONFIG=$(read_game_config "$GAME_DIR" || true)
if [ -n "$GAME_CONFIG" ]; then
  APP_NAME=$(echo "$GAME_CONFIG" | cut -d'|' -f1)
  BUNDLE_ID=$(echo "$GAME_CONFIG" | cut -d'|' -f2)
  set_app_identity "$GAME_DIR" "$APP_NAME" "$BUNDLE_ID"
else
  echo -e "${YELLOW}未找到有效 game_config.txt，跳过应用身份同步${NC}"
fi
ensure_project_icon "$GAME_DIR" "$PROJECT_ROOT" || true

cd "$GAME_DIR"

echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get
generate_app_icons "$GAME_DIR" || true

echo -e "${YELLOW}正在构建 $PLATFORM ...${NC}"
case "$PLATFORM" in
  macos)
    flutter build macos --release
    ;;
  linux)
    flutter build linux --release
    ;;
  windows)
    flutter build windows --release
    ;;
  android)
    flutter build apk --release --target-platform android-arm64
    ;;
  ios)
    (cd ios && pod install)
    flutter build ios --release --no-codesign
    ;;
  web)
    flutter build web --release
    ;;
  *)
    echo -e "${RED}错误: 不支持的平台 '$PLATFORM'。${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}构建完成: $PLATFORM${NC}"
