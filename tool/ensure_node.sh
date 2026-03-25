#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

if command -v node >/dev/null 2>&1; then
  command -v node
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo "错误: 未检测到 node，也未检测到 python3/python，无法自动下载 Node.js。" >&2
  exit 1
fi

PYTHON_BIN="$(command -v python3 || command -v python)"

host_os=""
case "$(uname -s)" in
  Darwin) host_os="macos" ;;
  Linux) host_os="linux" ;;
  *)
    echo "错误: 当前 shell 平台不支持自动下载 Node.js: $(uname -s)" >&2
    exit 1
    ;;
esac

host_arch=""
case "$(uname -m)" in
  x86_64|amd64) host_arch="x64" ;;
  arm64|aarch64) host_arch="arm64" ;;
  *)
    echo "错误: 不支持的 CPU 架构: $(uname -m)" >&2
    exit 1
    ;;
esac

CACHE_DIR="$REPO_ROOT/tool/toolchain_cache/node"
INSTALL_ROOT="$REPO_ROOT/.saki_toolchain/node"
MARKER_FILE="$INSTALL_ROOT/.current_path"
mkdir -p "$CACHE_DIR" "$INSTALL_ROOT"

if [ -f "$MARKER_FILE" ]; then
  NODE_HOME="$(head -n 1 "$MARKER_FILE" | tr -d '\r\n')"
  if [ -x "$NODE_HOME/bin/node" ]; then
    echo "$NODE_HOME/bin/node"
    exit 0
  fi
fi

META_FILE="$(mktemp "${TMPDIR:-/tmp}/saki_node_meta.XXXXXX.txt")"

"$PYTHON_BIN" - "$host_os" "$host_arch" >"$META_FILE" <<'PY'
import json
import sys
import urllib.request

host_os = sys.argv[1]
host_arch = sys.argv[2]

suffix_map = {
    ("linux", "x64"): "linux-x64.tar.xz",
    ("linux", "arm64"): "linux-arm64.tar.xz",
    ("macos", "x64"): "darwin-x64.tar.gz",
    ("macos", "arm64"): "darwin-arm64.tar.gz",
}

suffix = suffix_map.get((host_os, host_arch))
if not suffix:
    raise SystemExit(f"unsupported target {host_os}-{host_arch}")

index = json.loads(urllib.request.urlopen("https://nodejs.org/dist/index.json").read().decode("utf-8"))
release = next((r for r in index if r.get("lts")), None)
if not release:
    raise SystemExit("failed to resolve node lts release")

version = release["version"]
archive = f"node-{version}-{suffix}"
url = f"https://nodejs.org/dist/{version}/{archive}"
sum_url = f"https://nodejs.org/dist/{version}/SHASUMS256.txt"
sum_text = urllib.request.urlopen(sum_url).read().decode("utf-8")
sha = ""
for line in sum_text.splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) >= 2 and parts[1] == archive:
        sha = parts[0]
        break
if not sha:
    raise SystemExit(f"missing checksum for {archive}")

print(f"NODE_VERSION={version}")
print(f"NODE_ARCHIVE={archive}")
print(f"NODE_URL={url}")
print(f"NODE_SHA256={sha}")
PY

# shellcheck disable=SC1090
source "$META_FILE"
rm -f "$META_FILE"

ARCHIVE_PATH="$CACHE_DIR/$NODE_ARCHIVE"

sha256_file() {
  "$PYTHON_BIN" - "$1" <<'PY'
import hashlib
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
h = hashlib.sha256()
with p.open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

if [ -f "$ARCHIVE_PATH" ]; then
  GOT_SHA="$(sha256_file "$ARCHIVE_PATH")"
  if [ "$GOT_SHA" != "$NODE_SHA256" ]; then
    rm -f "$ARCHIVE_PATH"
  fi
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "正在下载 Node.js: $NODE_VERSION" >&2
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -o "$ARCHIVE_PATH" "$NODE_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$ARCHIVE_PATH" "$NODE_URL"
  else
    echo "错误: 未检测到 curl/wget，无法下载 Node.js。" >&2
    exit 1
  fi
fi

GOT_SHA="$(sha256_file "$ARCHIVE_PATH")"
if [ "$GOT_SHA" != "$NODE_SHA256" ]; then
  echo "错误: Node.js 校验失败。期望: $NODE_SHA256 实际: $GOT_SHA" >&2
  exit 1
fi

CLEAN_VERSION="${NODE_VERSION#v}"
INSTALL_DIR="$INSTALL_ROOT/node-${CLEAN_VERSION}-${host_os}-${host_arch}"
if [ ! -x "$INSTALL_DIR/bin/node" ]; then
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  tar -xf "$ARCHIVE_PATH" -C "$INSTALL_DIR"
fi

NODE_HOME="$INSTALL_DIR"
if [ ! -x "$NODE_HOME/bin/node" ]; then
  FIRST_DIR="$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
  if [ -n "$FIRST_DIR" ]; then
    NODE_HOME="$FIRST_DIR"
  fi
fi

if [ ! -x "$NODE_HOME/bin/node" ]; then
  echo "错误: Node.js 解压后未找到 node 可执行文件。" >&2
  exit 1
fi

printf '%s\n' "$NODE_HOME" > "$MARKER_FILE"
echo "$NODE_HOME/bin/node"
