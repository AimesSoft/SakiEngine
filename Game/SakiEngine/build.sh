#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_NAME=$(cat "$PROJECT_DIR/default_game.txt" 2>/dev/null | tr -d '\r\n' | xargs || true)
if [ -z "$GAME_NAME" ]; then
  GAME_NAME="$(basename "$PROJECT_DIR")"
fi

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

detect_engine_dir() {
  local candidates=()

  if [ -n "${SAKI_ENGINE_PATH:-}" ]; then
    candidates+=("$SAKI_ENGINE_PATH")
  fi

  candidates+=(
    "$PROJECT_DIR/Engine"
    "$PROJECT_DIR/../Engine"
    "$PROJECT_DIR/../../Engine"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate/tool/sks_compiler.dart" ] &&
       [ -f "$candidate/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart" ]; then
      (cd "$candidate" && pwd)
      return 0
    fi
  done

  return 1
}

_escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\/&]/\\&/g'
}

_sanitize_binary_name() {
  local name="$1"
  name=$(printf '%s' "$name" | sed -E 's/[^A-Za-z0-9]+/_/g; s/^_+|_+$//g')
  if [ -z "$name" ]; then
    name="saki_game"
  fi
  printf '%s' "$name"
}

sync_app_identity() {
  local config_file="$PROJECT_DIR/game_config.txt"
  if [ ! -f "$config_file" ]; then
    echo -e "${YELLOW}未找到 game_config.txt，跳过应用名称同步${NC}"
    return 0
  fi

  local app_name
  local bundle_id
  app_name=$(sed -n '1p' "$config_file" | tr -d '\r')
  bundle_id=$(sed -n '2p' "$config_file" | tr -d '\r')

  if [ -z "$app_name" ] || [ -z "$bundle_id" ]; then
    echo -e "${YELLOW}game_config.txt 缺少应用名或包名，跳过应用名称同步${NC}"
    return 0
  fi

  local binary_name
  local app_name_escaped
  local bundle_id_escaped
  local binary_name_escaped
  local company_name
  local company_name_escaped

  binary_name=$(_sanitize_binary_name "$app_name")
  app_name_escaped=$(_escape_sed "$app_name")
  bundle_id_escaped=$(_escape_sed "$bundle_id")
  binary_name_escaped=$(_escape_sed "$binary_name")
  company_name="${bundle_id%.*}"
  company_name_escaped=$(_escape_sed "$company_name")

  echo -e "${YELLOW}正在同步应用信息: ${app_name} (${bundle_id})${NC}"
  echo -e "${YELLOW}正在同步产物名称: ${binary_name}${NC}"

  if [ -f "$PROJECT_DIR/android/app/src/main/AndroidManifest.xml" ]; then
    sed -i.bak -E "s/android:label=\"[^\"]*\"/android:label=\"$app_name_escaped\"/" \
      "$PROJECT_DIR/android/app/src/main/AndroidManifest.xml"
    rm -f "$PROJECT_DIR/android/app/src/main/AndroidManifest.xml.bak"
  fi

  if [ -f "$PROJECT_DIR/android/app/build.gradle.kts" ]; then
    sed -i.bak -E "s/applicationId = \"[^\"]*\"/applicationId = \"$bundle_id_escaped\"/" \
      "$PROJECT_DIR/android/app/build.gradle.kts"
    rm -f "$PROJECT_DIR/android/app/build.gradle.kts.bak"
  fi

  if [ -f "$PROJECT_DIR/ios/Runner/Info.plist" ]; then
    APP_NAME="$app_name" perl -0777 -i.bak -pe \
      's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)#$1$ENV{APP_NAME}$2#s; s#(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)#$1$ENV{APP_NAME}$2#s' \
      "$PROJECT_DIR/ios/Runner/Info.plist"
    rm -f "$PROJECT_DIR/ios/Runner/Info.plist.bak"
  fi

  if [ -f "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj" ]; then
    BUNDLE_ID="$bundle_id" perl -i.bak -pe \
      'if(/PRODUCT_BUNDLE_IDENTIFIER = /){ if(/\.RunnerTests;/){ s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{BUNDLE_ID}.RunnerTests;/; } else { s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{BUNDLE_ID};/; } }' \
      "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj"
    rm -f "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj.bak"
  fi

  if [ -f "$PROJECT_DIR/macos/Runner/Configs/AppInfo.xcconfig" ]; then
    sed -i.bak -E \
      -e "s/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = $bundle_id_escaped/" \
      -e "s/^PRODUCT_NAME = .*/PRODUCT_NAME = $binary_name_escaped/" \
      "$PROJECT_DIR/macos/Runner/Configs/AppInfo.xcconfig"
    rm -f "$PROJECT_DIR/macos/Runner/Configs/AppInfo.xcconfig.bak"
  fi

  if [ -f "$PROJECT_DIR/linux/CMakeLists.txt" ]; then
    sed -i.bak -E \
      -e "s/set\(APPLICATION_ID \"[^\"]*\"\)/set(APPLICATION_ID \"$bundle_id_escaped\")/" \
      -e "s/set\(BINARY_NAME \"[^\"]*\"\)/set(BINARY_NAME \"$binary_name_escaped\")/" \
      "$PROJECT_DIR/linux/CMakeLists.txt"
    rm -f "$PROJECT_DIR/linux/CMakeLists.txt.bak"
  fi

  if [ -f "$PROJECT_DIR/linux/runner/my_application.cc" ]; then
    sed -i.bak -E \
      -e "s/gtk_header_bar_set_title\(header_bar, \"[^\"]*\"\);/gtk_header_bar_set_title(header_bar, \"$app_name_escaped\");/" \
      -e "s/gtk_window_set_title\(window, \"[^\"]*\"\);/gtk_window_set_title(window, \"$app_name_escaped\");/" \
      "$PROJECT_DIR/linux/runner/my_application.cc"
    rm -f "$PROJECT_DIR/linux/runner/my_application.cc.bak"
  fi

  if [ -f "$PROJECT_DIR/windows/CMakeLists.txt" ]; then
    sed -i.bak -E \
      -e "s/^project\([^)]+ LANGUAGES CXX\)/project($binary_name_escaped LANGUAGES CXX)/" \
      -e "s/^set\(BINARY_NAME \"[^\"]*\"\)/set(BINARY_NAME \"$binary_name_escaped\")/" \
      "$PROJECT_DIR/windows/CMakeLists.txt"
    rm -f "$PROJECT_DIR/windows/CMakeLists.txt.bak"
  fi

  if [ -f "$PROJECT_DIR/windows/runner/main.cpp" ]; then
    sed -i.bak -E \
      -e "s/window\.Create\(L\"[^\"]*\"/window.Create(L\"$app_name_escaped\"/" \
      "$PROJECT_DIR/windows/runner/main.cpp"
    rm -f "$PROJECT_DIR/windows/runner/main.cpp.bak"
  fi

  if [ -f "$PROJECT_DIR/windows/runner/Runner.rc" ]; then
    sed -i.bak -E \
      -e "s/VALUE \"CompanyName\", \"[^\"]*\"/VALUE \"CompanyName\", \"$company_name_escaped\"/" \
      -e "s/VALUE \"FileDescription\", \"[^\"]*\"/VALUE \"FileDescription\", \"$app_name_escaped\"/" \
      -e "s/VALUE \"ProductName\", \"[^\"]*\"/VALUE \"ProductName\", \"$app_name_escaped\"/" \
      -e "s/VALUE \"InternalName\", \"[^\"]*\"[[:space:]]+\"\\\\0\"/VALUE \"InternalName\", \"$binary_name_escaped\" \"\\\\0\"/" \
      -e "s/VALUE \"OriginalFilename\", \"[^\"]*\"[[:space:]]+\"\\\\0\"/VALUE \"OriginalFilename\", \"$binary_name_escaped.exe\" \"\\\\0\"/" \
      "$PROJECT_DIR/windows/runner/Runner.rc"
    rm -f "$PROJECT_DIR/windows/runner/Runner.rc.bak"
  fi
}

PLATFORM="${1:-}"
if [ -z "$PLATFORM" ]; then
  choose_platform
elif ! is_supported_platform "$PLATFORM"; then
  echo -e "${RED}错误: 不支持的平台 '$PLATFORM'。${NC}"
  exit 1
fi

ENGINE_DIR=$(detect_engine_dir || true)
if [ -z "$ENGINE_DIR" ]; then
  echo -e "${RED}错误: 未找到可用的 Engine 目录。${NC}"
  echo -e "${YELLOW}请确认以下任一路径存在并有效:${NC}"
  echo "  - SAKI_ENGINE_PATH"
  echo "  - $PROJECT_DIR/Engine"
  echo "  - $PROJECT_DIR/../Engine"
  echo "  - $PROJECT_DIR/../../Engine"
  exit 1
fi

ENGINE_COMPILED_LOADER="$ENGINE_DIR/lib/src/sks_compiler/generated/compiled_sks_bundle.g.dart"
GAME_SKS_CACHE_DIR="$PROJECT_DIR/.saki_cache"
GAME_SKS_BUNDLE_FILE="$GAME_SKS_CACHE_DIR/compiled_sks_bundle.g.dart"
GAME_PUBSPEC_FILE="$PROJECT_DIR/pubspec.yaml"
GAME_PUBSPEC_BACKUP_FILE="$GAME_SKS_CACHE_DIR/pubspec.yaml.backup"

restore_engine_compiled_loader() {
  cat > "$ENGINE_COMPILED_LOADER" <<'LOADER_EOF'
import 'package:sakiengine/src/sks_compiler/compiled_sks_bundle.dart';

CompiledSksBundle? loadGeneratedCompiledSksBundle() {
  return null;
}
LOADER_EOF
}

prepare_release_pubspec_assets() {
  mkdir -p "$GAME_SKS_CACHE_DIR"
  cp -f "$GAME_PUBSPEC_FILE" "$GAME_PUBSPEC_BACKUP_FILE"

  local assets_start_line
  assets_start_line=$(grep -n -E "^  assets:\s*$" "$GAME_PUBSPEC_BACKUP_FILE" | head -1 | cut -d: -f1)
  if [ -z "${assets_start_line:-}" ]; then
    echo -e "${RED}错误: pubspec.yaml 未找到 flutter/assets 段${NC}"
    exit 1
  fi

  local assets_end_line="$assets_start_line"
  local total_lines
  total_lines=$(wc -l < "$GAME_PUBSPEC_BACKUP_FILE" | xargs)
  while [ "$assets_end_line" -lt "$total_lines" ]; do
    local next_line_num=$((assets_end_line + 1))
    local line
    line=$(sed -n "${next_line_num}p" "$GAME_PUBSPEC_BACKUP_FILE")
    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]{4}-[[:space:]]+ ]]; then
      assets_end_line="$next_line_num"
      continue
    fi
    break
  done

  local raw_assets_file="$GAME_SKS_CACHE_DIR/raw_assets_entries.txt"
  local expanded_assets_file="$GAME_SKS_CACHE_DIR/expanded_assets_entries.txt"
  local unique_assets_file="$GAME_SKS_CACHE_DIR/unique_assets_entries.txt"
  local temp_pubspec="$GAME_SKS_CACHE_DIR/pubspec.yaml.temp"

  sed -n "$((assets_start_line + 1)),$((assets_end_line))p" "$GAME_PUBSPEC_BACKUP_FILE" \
    | sed -n -E "s/^[[:space:]]{4}-[[:space:]]+(.+)$/\1/p" \
    | sed -E "s/[[:space:]]+#.*$//" \
    | sed -E "s/^['\"](.*)['\"]$/\1/" \
    > "$raw_assets_file"

  : > "$expanded_assets_file"
  while IFS= read -r entry; do
    entry=$(echo "$entry" | xargs)
    [ -n "$entry" ] || continue

    case "$entry" in
      GameScript|GameScript/|GameScript/*|GameScript_*)
        continue
        ;;
    esac

    local normalized="${entry%/}"
    local full_path="$PROJECT_DIR/$normalized"

    if [ -d "$full_path" ]; then
      while IFS= read -r file_path; do
        [ -n "$file_path" ] || continue
        local relative="${file_path#$PROJECT_DIR/}"
        relative=${relative//\\//}
        case "$relative" in
          GameScript/*|GameScript_*)
            continue
            ;;
        esac
        echo "$relative" >> "$expanded_assets_file"
      done < <(find "$full_path" -type f ! -name '.DS_Store' | sort)
    elif [ -f "$full_path" ]; then
      echo "$normalized" >> "$expanded_assets_file"
    else
      echo -e "${YELLOW}警告: 资源路径不存在，已跳过: $entry${NC}"
    fi
  done < "$raw_assets_file"

  awk 'NF && !seen[$0]++' "$expanded_assets_file" > "$unique_assets_file"

  local expanded_count
  expanded_count=$(wc -l < "$unique_assets_file" | xargs)
  if [ "$expanded_count" -eq 0 ]; then
    echo -e "${RED}错误: 发布资源清单为空，已中止构建。${NC}"
    exit 1
  fi

  local image_count
  image_count=$(grep -E -i "^Assets/images/.*\.(png|jpg|jpeg|gif|bmp|webp|avif|mp4|mov|avi|mkv|webm)$" \
    "$unique_assets_file" | wc -l | xargs)
  if grep -q -E "^Assets/?$" "$raw_assets_file" && [ "$image_count" -eq 0 ]; then
    echo -e "${RED}错误: 检测到配置了 Assets/，但展开后没有任何 Assets/images 资源。${NC}"
    echo -e "${RED}为防止发布包缺少美术素材，已中止构建。${NC}"
    exit 1
  fi

  head -n "$assets_start_line" "$GAME_PUBSPEC_BACKUP_FILE" > "$temp_pubspec"
  while IFS= read -r asset_file; do
    [ -n "$asset_file" ] || continue
    echo "    - $asset_file" >> "$temp_pubspec"
  done < "$unique_assets_file"
  tail -n "+$((assets_end_line + 1))" "$GAME_PUBSPEC_BACKUP_FILE" >> "$temp_pubspec"

  mv -f "$temp_pubspec" "$GAME_PUBSPEC_FILE"
  echo -e "${YELLOW}已更新发布资源清单：总计 ${expanded_count} 项，图片/视频 ${image_count} 项，排除 GameScript*.sks${NC}"
}

restore_game_pubspec() {
  if [ -f "$GAME_PUBSPEC_BACKUP_FILE" ]; then
    mv -f "$GAME_PUBSPEC_BACKUP_FILE" "$GAME_PUBSPEC_FILE"
  fi
}

cleanup_on_exit() {
  restore_engine_compiled_loader
  restore_game_pubspec
}

trap cleanup_on_exit EXIT

echo -e "${GREEN}游戏项目: $GAME_NAME${NC}"
echo -e "${GREEN}目标平台: $(platform_display_name "$PLATFORM")${NC}"
echo -e "${BLUE}Engine目录: $ENGINE_DIR${NC}"

sync_app_identity

cd "$PROJECT_DIR"

echo -e "${YELLOW}准备脚本编译环境（首次依赖解析）...${NC}"
flutter pub get

echo -e "${YELLOW}正在预编译 .sks 脚本为 Dart...${NC}"
mkdir -p "$GAME_SKS_CACHE_DIR"
flutter pub run "$ENGINE_DIR/tool/sks_compiler.dart" \
  --game-dir "$PROJECT_DIR" \
  --output "$GAME_SKS_BUNDLE_FILE" \
  --game-name "$GAME_NAME"

if [ ! -f "$GAME_SKS_BUNDLE_FILE" ]; then
  echo -e "${RED}错误: 预编译产物不存在: $GAME_SKS_BUNDLE_FILE${NC}"
  exit 1
fi

cp -f "$GAME_SKS_BUNDLE_FILE" "$ENGINE_COMPILED_LOADER"

echo -e "${YELLOW}正在生成发布资源清单...${NC}"
prepare_release_pubspec_assets

echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get

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
