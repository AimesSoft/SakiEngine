#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "用法: ./scripts/install_project_ci.sh <ProjectDir> [RootDir]"
  exit 1
fi

PROJECT_DIR="$1"
ROOT_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)}"

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

WORKFLOW_SRC_DIR="$ROOT_DIR/.github/workflows"
WORKFLOW_DST_DIR="$PROJECT_DIR/.github/workflows"

if [ ! -d "$WORKFLOW_SRC_DIR" ]; then
  echo "错误: 未找到工作流模板目录: $WORKFLOW_SRC_DIR"
  exit 1
fi

WORKFLOW_FILES=(
  main.yml
  android-build.yml
  ios-build.yml
  macos-build.yml
  windows-build.yml
  linux-build.yml
  publish.yml
  version-update.yml
)

mkdir -p "$WORKFLOW_DST_DIR"

for file in "${WORKFLOW_FILES[@]}"; do
  if [ -f "$WORKFLOW_SRC_DIR/$file" ]; then
    cp -f "$WORKFLOW_SRC_DIR/$file" "$WORKFLOW_DST_DIR/$file"
  else
    echo "警告: 未找到工作流模板文件: $file"
  fi
done

if [ -f "$PROJECT_DIR/.gitignore" ] && ! grep -q "^/.saki_cache/$" "$PROJECT_DIR/.gitignore"; then
  echo "/.saki_cache/" >> "$PROJECT_DIR/.gitignore"
fi

cat > "$PROJECT_DIR/build.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
GAME_NAME="$(cat "$PROJECT_DIR/default_game.txt" 2>/dev/null | tr -d '\r\n' | xargs || true)"
if [ -z "$GAME_NAME" ]; then
  GAME_NAME="$(basename "$PROJECT_DIR")"
fi

if [ ! -x "$ROOT_DIR/tool/ensure_node.sh" ] || [ ! -f "$ROOT_DIR/tool/saki_cli.js" ]; then
  echo "错误: 未找到 SakiEngine 根目录工具脚本。"
  echo "需要: $ROOT_DIR/tool/ensure_node.sh 与 $ROOT_DIR/tool/saki_cli.js"
  exit 1
fi

NODE_BIN="$("$ROOT_DIR/tool/ensure_node.sh" "$ROOT_DIR")"
exec "$NODE_BIN" "$ROOT_DIR/tool/saki_cli.js" build "$GAME_NAME" "$@"
EOF

chmod +x "$PROJECT_DIR/build.sh"

echo "已为项目生成 CI 文件与构建脚本"
echo "- 工作流目录: $WORKFLOW_DST_DIR"
echo "- 构建脚本: $PROJECT_DIR/build.sh"
