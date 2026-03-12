#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$(dirname "$0")"
PROJECT_ROOT=$(pwd)
DEFAULT_GAME_FILE="$PROJECT_ROOT/default_game.txt"
source "$PROJECT_ROOT/scripts/asset_utils.sh"

is_supported_platform() {
  case "$1" in
    macos|linux|windows|android|ios|web) return 0 ;;
    *) return 1 ;;
  esac
}

platform_display_name() {
  case "$1" in
    macos) echo "macOS" ;;
    linux) echo "Linux" ;;
    windows) echo "Windows" ;;
    android) echo "Android" ;;
    ios) echo "iOS" ;;
    web) echo "Web" ;;
    *) echo "$1" ;;
  esac
}

detect_host_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux) echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

list_game_projects() {
  local game_dirs=()
  while IFS= read -r dir; do
    if [ -f "$dir/pubspec.yaml" ]; then
      game_dirs+=("$(basename "$dir")")
    fi
  done < <(find "$PROJECT_ROOT/Game" -mindepth 1 -maxdepth 1 -type d | sort)

  if [ "${#game_dirs[@]}" -eq 0 ]; then
    echo -e "${RED}错误: 未找到可构建的游戏项目（Game/*/pubspec.yaml）${NC}"
    exit 1
  fi

  printf '%s\n' "${game_dirs[@]}"
}

choose_game_project() {
  local current_default=""
  local game_projects=()
  if [ -f "$DEFAULT_GAME_FILE" ]; then
    current_default=$(tr -d '\r\n' < "$DEFAULT_GAME_FILE" | xargs || true)
  fi

  while IFS= read -r game; do
    if [ -n "$game" ]; then
      game_projects+=("$game")
    fi
  done < <(list_game_projects)

  if [ "${#game_projects[@]}" -eq 0 ]; then
    echo -e "${RED}错误: 未找到可构建的游戏项目（Game/*/pubspec.yaml）${NC}"
    exit 1
  fi

  local default_index=1
  local i
  for i in "${!game_projects[@]}"; do
    if [ "${game_projects[$i]}" = "$current_default" ]; then
      default_index=$((i + 1))
      break
    fi
  done

  echo -e "${YELLOW}请选择要编译的游戏项目:${NC}"
  for i in "${!game_projects[@]}"; do
    local idx=$((i + 1))
    local mark=""
    if [ "$idx" -eq "$default_index" ]; then
      mark=" ${BLUE}(默认)${NC}"
    fi
    echo -e "${BLUE}  $idx. ${game_projects[$i]}${mark}${NC}"
  done
  echo ""
  echo -ne "${YELLOW}请输入项目编号 (默认 ${default_index}): ${NC}"
  read -r project_choice

  if [ -z "$project_choice" ]; then
    project_choice="$default_index"
  fi

  if ! [[ "$project_choice" =~ ^[0-9]+$ ]] ||
     [ "$project_choice" -lt 1 ] ||
     [ "$project_choice" -gt "${#game_projects[@]}" ]; then
    echo -e "${RED}错误: 无效的项目编号 ${project_choice}${NC}"
    exit 1
  fi

  GAME_NAME="${game_projects[$((project_choice - 1))]}"
  GAME_DIR="$PROJECT_ROOT/Game/$GAME_NAME"
  echo "$GAME_NAME" > "$DEFAULT_GAME_FILE"
}

choose_platform() {
  local host_platform
  host_platform=$(detect_host_platform)
  local options=()

  case "$host_platform" in
    macos)
      options=(macos ios android web)
      ;;
    linux)
      options=(linux android web)
      ;;
    windows)
      options=(windows android web)
      ;;
    *)
      options=(macos linux windows android ios web)
      ;;
  esac

  local default_index=1
  local i
  for i in "${!options[@]}"; do
    if [ "${options[$i]}" = "$host_platform" ]; then
      default_index=$((i + 1))
      break
    fi
  done

  echo -e "${YELLOW}请选择要构建的平台:${NC}"
  for i in "${!options[@]}"; do
    local idx=$((i + 1))
    local mark=""
    if [ "$idx" -eq "$default_index" ]; then
      mark=" ${BLUE}(默认)${NC}"
    fi
    echo -e "${BLUE}  $idx. $(platform_display_name "${options[$i]}")${mark}${NC}"
  done
  echo ""
  echo -ne "${YELLOW}请输入平台编号 (默认 ${default_index}): ${NC}"
  read -r platform_choice

  if [ -z "$platform_choice" ]; then
    platform_choice="$default_index"
  fi

  if ! [[ "$platform_choice" =~ ^[0-9]+$ ]] ||
     [ "$platform_choice" -lt 1 ] ||
     [ "$platform_choice" -gt "${#options[@]}" ]; then
    echo -e "${RED}错误: 无效的平台编号 ${platform_choice}${NC}"
    exit 1
  fi

  PLATFORM="${options[$((platform_choice - 1))]}"
}

GAME_NAME=""
GAME_DIR=""
PLATFORM=""

if [ $# -ge 1 ]; then
  if is_supported_platform "$1"; then
    PLATFORM="$1"
  else
    GAME_NAME="$1"
  fi
fi

if [ $# -ge 2 ]; then
  PLATFORM="$2"
fi

if [ -z "$GAME_NAME" ]; then
  choose_game_project
else
  GAME_DIR="$PROJECT_ROOT/Game/$GAME_NAME"
fi

if [ ! -d "$GAME_DIR" ] || [ ! -f "$GAME_DIR/pubspec.yaml" ]; then
  echo -e "${RED}错误: 游戏项目无效: $GAME_DIR${NC}"
  exit 1
fi

if [ -z "$PLATFORM" ]; then
  choose_platform
elif ! is_supported_platform "$PLATFORM"; then
  echo -e "${RED}错误: 不支持的平台 '$PLATFORM'。${NC}"
  exit 1
fi

ENGINE_COMPILED_LOADER="$PROJECT_ROOT/Engine/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart"
GAME_SKS_CACHE_DIR="$GAME_DIR/.saki_cache"
GAME_SKS_BUNDLE_FILE="$GAME_SKS_CACHE_DIR/compiled_sks_bundle.g.dart"
GAME_PUBSPEC_FILE="$GAME_DIR/pubspec.yaml"
GAME_PUBSPEC_BACKUP_FILE="$GAME_SKS_CACHE_DIR/pubspec.yaml.backup"

restore_engine_compiled_loader() {
  cat > "$ENGINE_COMPILED_LOADER" <<'EOF'
import 'package:sakiengine/src/sks_compiler/compiled_sks_bundle.dart';

CompiledSksBundle? loadGeneratedCompiledSksBundle() {
  return null;
}
EOF
}

restore_game_pubspec() {
  if [ -f "$GAME_PUBSPEC_BACKUP_FILE" ]; then
    mv -f "$GAME_PUBSPEC_BACKUP_FILE" "$GAME_PUBSPEC_FILE"
  fi
}

strip_sks_assets_from_pubspec() {
  mkdir -p "$GAME_SKS_CACHE_DIR"
  cp -f "$GAME_PUBSPEC_FILE" "$GAME_PUBSPEC_BACKUP_FILE"
  perl -ne 'print unless /^\s*-\s*GameScript[^\s]*\/\s*$/' \
    "$GAME_PUBSPEC_BACKUP_FILE" > "$GAME_PUBSPEC_FILE"
}

cleanup_on_exit() {
  restore_engine_compiled_loader
  restore_game_pubspec
}

trap cleanup_on_exit EXIT

echo -e "${GREEN}使用游戏项目: $GAME_NAME${NC}"
echo -e "${GREEN}目标平台: $(platform_display_name "$PLATFORM")${NC}"

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

echo -e "${YELLOW}正在从构建资源中排除 .sks 脚本目录...${NC}"
strip_sks_assets_from_pubspec

echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get
generate_app_icons "$GAME_DIR" || true

echo -e "${YELLOW}正在预编译 .sks 脚本为 Dart...${NC}"
mkdir -p "$GAME_SKS_CACHE_DIR"
flutter pub run ../../Engine/tool/sks_compiler.dart \
  --game-dir "$GAME_DIR" \
  --output "$GAME_SKS_BUNDLE_FILE" \
  --game-name "$GAME_NAME"

if [ ! -f "$GAME_SKS_BUNDLE_FILE" ]; then
  echo -e "${RED}错误: 预编译产物不存在: $GAME_SKS_BUNDLE_FILE${NC}"
  exit 1
fi

cp -f "$GAME_SKS_BUNDLE_FILE" "$ENGINE_COMPILED_LOADER"

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
