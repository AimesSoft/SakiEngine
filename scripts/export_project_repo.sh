#!/bin/bash

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "用法: ./scripts/export_project_repo.sh <ProjectName> <TargetDir>"
  exit 1
fi

PROJECT_NAME="$1"
TARGET_DIR="$2"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/Game/$PROJECT_NAME"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "错误: 未找到项目目录 $SOURCE_DIR"
  exit 1
fi

mkdir -p "$TARGET_DIR"
rsync -a --delete "$SOURCE_DIR/" "$TARGET_DIR/"

if [ -x "$ROOT_DIR/scripts/install_project_ci.sh" ]; then
  "$ROOT_DIR/scripts/install_project_ci.sh" "$TARGET_DIR" "$ROOT_DIR"
fi

if [ ! -d "$TARGET_DIR/.git" ]; then
  (
    cd "$TARGET_DIR"
    git init >/dev/null 2>&1 || true
  )
fi

echo "已导出项目: $PROJECT_NAME"
echo "来源目录: $SOURCE_DIR"
echo "目标目录: $TARGET_DIR"
echo "说明: 本操作只复制，不会删除主仓库中的任何文件。"
