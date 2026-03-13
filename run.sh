#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$(dirname "$0")"

PROJECT_ROOT=$(pwd)
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
DEFAULT_GAME_FILE="$PROJECT_ROOT/default_game.txt"

source "$SCRIPTS_DIR/platform_utils.sh"
source "$SCRIPTS_DIR/asset_utils.sh"

echo -e "${BLUE}=== SakiEngine 项目启动器（项目级 Flutter App） ===${NC}"
echo ""

PLATFORM=$(detect_platform)
PLATFORM_NAME=$(get_platform_display_name "$PLATFORM")

echo -e "${GREEN}检测到操作系统: ${PLATFORM_NAME}${NC}"

if ! check_platform_support "$PLATFORM"; then
    echo -e "${RED}错误: 当前平台 ${PLATFORM_NAME} 不支持或缺少 Flutter${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Flutter 环境检测通过${NC}"
echo ""

# 游戏项目选择逻辑
if [ -f "$DEFAULT_GAME_FILE" ]; then
    current_game=$(read_default_game "$PROJECT_ROOT")
    if [ -n "$current_game" ]; then
        echo -e "${BLUE}当前默认游戏: ${GREEN}$current_game${NC}"
        echo ""
        echo -e "${YELLOW}请选择操作:${NC}"
        echo -e "${BLUE}  1. 继续使用当前游戏${NC}"
        echo -e "${BLUE}  2. 选择其他游戏${NC}"
        echo -e "${BLUE}  3. 创建新游戏项目${NC}"
        echo ""
        echo -e -n "${YELLOW}请选择 (1-3, 默认为1): ${NC}"
        read -r action_choice

        case "$action_choice" in
            "2")
                "$SCRIPTS_DIR/select_game.sh"
                ;;
            "3")
                "$SCRIPTS_DIR/create_new_project.sh"
                ;;
            *)
                ;;
        esac
    else
        echo -e "${YELLOW}default_game.txt 文件为空。${NC}"
        "$SCRIPTS_DIR/select_game.sh"
    fi
else
    echo -e "${YELLOW}未找到默认游戏配置。${NC}"
    "$SCRIPTS_DIR/select_game.sh"
fi

GAME_NAME=$(read_default_game "$PROJECT_ROOT")
if [ -z "$GAME_NAME" ]; then
    echo -e "${RED}错误: 无法读取游戏项目名称${NC}"
    exit 1
fi

GAME_DIR=$(validate_game_dir "$PROJECT_ROOT" "$GAME_NAME")
if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 游戏目录不存在: $PROJECT_ROOT/Game/$GAME_NAME${NC}"
    exit 1
fi

if [ ! -f "$GAME_DIR/pubspec.yaml" ]; then
    echo -e "${RED}错误: $GAME_DIR 不是 Flutter 项目（缺少 pubspec.yaml）${NC}"
    echo -e "${YELLOW}请先通过 create_new_project.sh 创建，或手动迁移该项目。${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}启动游戏项目: $GAME_NAME${NC}"
echo -e "${BLUE}项目路径: $GAME_DIR${NC}"
echo ""

# 同步应用身份信息与图标（项目级）
echo -e "${YELLOW}正在读取游戏配置...${NC}"
GAME_CONFIG=$(read_game_config "$GAME_DIR" || true)
if [ -n "$GAME_CONFIG" ]; then
    APP_NAME=$(echo "$GAME_CONFIG" | cut -d'|' -f1)
    BUNDLE_ID=$(echo "$GAME_CONFIG" | cut -d'|' -f2)
    set_app_identity "$GAME_DIR" "$APP_NAME" "$BUNDLE_ID"
else
    echo -e "${YELLOW}未找到有效 game_config.txt，跳过应用身份同步${NC}"
fi
ensure_project_icon "$GAME_DIR" "$PROJECT_ROOT" || true

# 平台选择逻辑
echo -e "${YELLOW}请选择运行平台:${NC}"
echo -e "${BLUE}  1. ${PLATFORM_NAME} (当前系统平台)${NC}"
echo -e "${BLUE}  2. Chrome (Web调试模式)${NC}"
echo ""
echo -e -n "${YELLOW}请选择 (1-2, 默认为1): ${NC}"
read -r platform_choice

case "$platform_choice" in
    "2")
        RUN_PLATFORM="web"
        PLATFORM_DISPLAY="Chrome (Web调试模式)"
        ;;
    *)
        RUN_PLATFORM="$PLATFORM"
        PLATFORM_DISPLAY="$PLATFORM_NAME"
        ;;
esac

echo -e "${GREEN}选择的平台: $PLATFORM_DISPLAY${NC}"
echo ""

cd "$GAME_DIR"

echo -e "${YELLOW}正在获取依赖...${NC}"
flutter pub get
generate_app_icons "$GAME_DIR" || true

echo ""
if [ "$RUN_PLATFORM" = "web" ]; then
    echo -e "${GREEN}在 Chrome 上启动项目...${NC}"
    flutter run -d chrome --dart-define=SAKI_GAME_PATH="$GAME_DIR"
else
    case "$RUN_PLATFORM" in
        "macos")
            flutter run -d macos --dart-define=SAKI_GAME_PATH="$GAME_DIR"
            ;;
        "linux")
            flutter run -d linux --dart-define=SAKI_GAME_PATH="$GAME_DIR"
            ;;
        "windows")
            flutter run -d windows --dart-define=SAKI_GAME_PATH="$GAME_DIR"
            ;;
        *)
            echo -e "${RED}错误: 不支持的平台 $RUN_PLATFORM${NC}"
            exit 1
            ;;
    esac
fi
