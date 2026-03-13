#!/bin/bash

#================================================
# 资源处理工具脚本（项目级）
#================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_project_root() {
    echo "$(dirname "$(dirname "$(realpath "$0")")")"
}

read_default_game() {
    local project_root="$1"
    local default_game_file="$project_root/default_game.txt"

    if [ -f "$default_game_file" ]; then
        cat "$default_game_file" | tr -d '\n\r'
    else
        echo ""
    fi
}

validate_game_dir() {
    local project_root="$1"
    local game_name="$2"
    local game_dir="$project_root/Game/$game_name"

    if [ -d "$game_dir" ]; then
        echo "$game_dir"
        return 0
    else
        return 1
    fi
}

read_game_config() {
    local game_dir="$1"
    local config_file="$game_dir/game_config.txt"

    if [ -f "$config_file" ]; then
        local app_name
        local bundle_id
        app_name=$(sed -n '1p' "$config_file" | tr -d '\r')
        bundle_id=$(sed -n '2p' "$config_file" | tr -d '\r')

        if [ -n "$app_name" ] && [ -n "$bundle_id" ]; then
            echo "$app_name|$bundle_id"
            return 0
        fi
    fi

    return 1
}

_escape_sed() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

_sanitize_binary_name() {
    local name="$1"
    name=$(printf '%s' "$name" | sed -E 's/[^A-Za-z0-9]+/_/g; s/^_+|_+$//g')
    if [ -z "$name" ]; then
        name="saki_game"
    fi
    printf '%s' "$name"
}

set_app_identity() {
    local project_dir="$1"
    local app_name="$2"
    local bundle_id="$3"
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

    if [ -f "$project_dir/android/app/src/main/AndroidManifest.xml" ]; then
        sed -i.bak -E "s/android:label=\"[^\"]*\"/android:label=\"$app_name_escaped\"/" \
            "$project_dir/android/app/src/main/AndroidManifest.xml"
        rm -f "$project_dir/android/app/src/main/AndroidManifest.xml.bak"
    fi

    if [ -f "$project_dir/android/app/build.gradle.kts" ]; then
        sed -i.bak -E "s/applicationId = \"[^\"]*\"/applicationId = \"$bundle_id_escaped\"/" \
            "$project_dir/android/app/build.gradle.kts"
        rm -f "$project_dir/android/app/build.gradle.kts.bak"
    fi

    if [ -f "$project_dir/ios/Runner/Info.plist" ]; then
        APP_NAME="$app_name" perl -0777 -i.bak -pe \
            's#(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)#$1$ENV{APP_NAME}$2#s; s#(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)#$1$ENV{APP_NAME}$2#s' \
            "$project_dir/ios/Runner/Info.plist"
        rm -f "$project_dir/ios/Runner/Info.plist.bak"
    fi

    if [ -f "$project_dir/ios/Runner.xcodeproj/project.pbxproj" ]; then
        BUNDLE_ID="$bundle_id" perl -i.bak -pe \
            'if(/PRODUCT_BUNDLE_IDENTIFIER = /){ if(/\.RunnerTests;/){ s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{BUNDLE_ID}.RunnerTests;/; } else { s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $ENV{BUNDLE_ID};/; } }' \
            "$project_dir/ios/Runner.xcodeproj/project.pbxproj"
        rm -f "$project_dir/ios/Runner.xcodeproj/project.pbxproj.bak"
    fi

    if [ -f "$project_dir/macos/Runner/Configs/AppInfo.xcconfig" ]; then
        sed -i.bak -E \
            -e "s/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = $bundle_id_escaped/" \
            -e "s/^PRODUCT_NAME = .*/PRODUCT_NAME = $binary_name_escaped/" \
            "$project_dir/macos/Runner/Configs/AppInfo.xcconfig"
        rm -f "$project_dir/macos/Runner/Configs/AppInfo.xcconfig.bak"
    fi

    if [ -f "$project_dir/linux/CMakeLists.txt" ]; then
        sed -i.bak -E \
            -e "s/set\(APPLICATION_ID \"[^\"]*\"\)/set(APPLICATION_ID \"$bundle_id_escaped\")/" \
            -e "s/set\(BINARY_NAME \"[^\"]*\"\)/set(BINARY_NAME \"$binary_name_escaped\")/" \
            "$project_dir/linux/CMakeLists.txt"
        rm -f "$project_dir/linux/CMakeLists.txt.bak"
    fi

    if [ -f "$project_dir/linux/runner/my_application.cc" ]; then
        sed -i.bak -E \
            -e "s/gtk_header_bar_set_title\(header_bar, \"[^\"]*\"\);/gtk_header_bar_set_title(header_bar, \"$app_name_escaped\");/" \
            -e "s/gtk_window_set_title\(window, \"[^\"]*\"\);/gtk_window_set_title(window, \"$app_name_escaped\");/" \
            "$project_dir/linux/runner/my_application.cc"
        rm -f "$project_dir/linux/runner/my_application.cc.bak"
    fi

    if [ -f "$project_dir/windows/CMakeLists.txt" ]; then
        sed -i.bak -E \
            -e "s/^project\([^)]+ LANGUAGES CXX\)/project($binary_name_escaped LANGUAGES CXX)/" \
            -e "s/^set\(BINARY_NAME \"[^\"]*\"\)/set(BINARY_NAME \"$binary_name_escaped\")/" \
            "$project_dir/windows/CMakeLists.txt"
        rm -f "$project_dir/windows/CMakeLists.txt.bak"
    fi

    if [ -f "$project_dir/windows/runner/main.cpp" ]; then
        sed -i.bak -E \
            -e "s/window\.Create\(L\"[^\"]*\"/window.Create(L\"$app_name_escaped\"/" \
            "$project_dir/windows/runner/main.cpp"
        rm -f "$project_dir/windows/runner/main.cpp.bak"
    fi

    if [ -f "$project_dir/windows/runner/Runner.rc" ]; then
        sed -i.bak -E \
            -e "s/VALUE \"CompanyName\", \"[^\"]*\"/VALUE \"CompanyName\", \"$company_name_escaped\"/" \
            -e "s/VALUE \"FileDescription\", \"[^\"]*\"/VALUE \"FileDescription\", \"$app_name_escaped\"/" \
            -e "s/VALUE \"ProductName\", \"[^\"]*\"/VALUE \"ProductName\", \"$app_name_escaped\"/" \
            -e "s/VALUE \"InternalName\", \"[^\"]*\"[[:space:]]+\"\\\\0\"/VALUE \"InternalName\", \"$binary_name_escaped\" \"\\\\0\"/" \
            -e "s/VALUE \"OriginalFilename\", \"[^\"]*\"[[:space:]]+\"\\\\0\"/VALUE \"OriginalFilename\", \"$binary_name_escaped.exe\" \"\\\\0\"/" \
            "$project_dir/windows/runner/Runner.rc"
        rm -f "$project_dir/windows/runner/Runner.rc.bak"
    fi

    return 0
}

ensure_project_icon() {
    local project_dir="$1"
    local project_root="$2"
    local root_icon="$project_root/icon.png"
    local engine_icon="$project_root/Engine/icon.png"

    if [ -f "$project_dir/icon.png" ]; then
        echo -e "${GREEN}使用项目图标: $project_dir/icon.png${NC}"
        return 0
    fi

    if [ -f "$root_icon" ]; then
        cp "$root_icon" "$project_dir/icon.png"
        echo -e "${YELLOW}项目无 icon.png，已复制根目录图标${NC}"
        return 0
    fi

    if [ -f "$engine_icon" ]; then
        cp "$engine_icon" "$project_dir/icon.png"
        echo -e "${YELLOW}项目无 icon.png，已复制 Engine/icon.png${NC}"
        return 0
    fi

    echo -e "${YELLOW}警告: 未找到 icon.png，跳过图标同步${NC}"
    return 1
}

generate_app_icons() {
    local project_dir="$1"

    if [ ! -f "$project_dir/icon.png" ]; then
        echo -e "${YELLOW}跳过图标生成: 未找到 $project_dir/icon.png${NC}"
        return 0
    fi

    if [ ! -f "$project_dir/pubspec.yaml" ] || ! grep -q "flutter_launcher_icons:" "$project_dir/pubspec.yaml"; then
        echo -e "${YELLOW}跳过图标生成: pubspec 未配置 flutter_launcher_icons${NC}"
        return 0
    fi

    echo -e "${YELLOW}正在生成应用图标...${NC}"
    (
        cd "$project_dir" || exit 1
        flutter pub run flutter_launcher_icons:main
    )
}
