#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_BASE_DIR="${1:-$REPO_ROOT/dist}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
PACKAGE_NAME="SakiEngine-distribution-${TIMESTAMP}"
WORK_DIR="$OUT_BASE_DIR/$PACKAGE_NAME"
ENGINE_DIR="$WORK_DIR/SakiEngine"
FLUTTER_CACHE_DIR="$ENGINE_DIR/tool/toolchain_cache/flutter"
NODE_CACHE_DIR="$ENGINE_DIR/tool/toolchain_cache/node"
MEDIAKIT_PREBUILT_DIR="$ENGINE_DIR/third_party/media_kit_libs_windows_video_hotfix/prebuilt"
MANIFEST_FILE="$WORK_DIR/distribution_manifest.txt"

find_python() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "python3"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    printf '%s\n' "python"
    return 0
  fi
  return 1
}

PYTHON_BIN="$(find_python || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "错误: 未检测到 python3/python。"
  exit 1
fi

download_file() {
  local url="$1"
  local out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -o "$out" "$url"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -O "$out" "$url"
    return $?
  fi
  echo "错误: 未检测到 curl/wget，无法下载: $url"
  return 1
}

sha256_file() {
  "$PYTHON_BIN" - "$1" <<'PY'
import hashlib
import pathlib
import sys

file = pathlib.Path(sys.argv[1])
h = hashlib.sha256()
with file.open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

md5_file() {
  "$PYTHON_BIN" - "$1" <<'PY'
import hashlib
import pathlib
import sys

file = pathlib.Path(sys.argv[1])
h = hashlib.md5()
with file.open("rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        h.update(chunk)
print(h.hexdigest())
PY
}

ensure_download_sha256() {
  local url="$1"
  local out="$2"
  local expected="$3"

  mkdir -p "$(dirname "$out")"
  if [ -f "$out" ]; then
    local got
    got="$(sha256_file "$out")"
    if [ "$got" = "$expected" ]; then
      return 0
    fi
    rm -f "$out"
  fi

  echo "下载: $url"
  download_file "$url" "$out"
  local got
  got="$(sha256_file "$out")"
  if [ "$got" != "$expected" ]; then
    echo "错误: SHA256 校验失败: $out"
    echo "期望: $expected"
    echo "实际: $got"
    return 1
  fi
}

ensure_download_md5() {
  local url="$1"
  local out="$2"
  local expected="$3"

  mkdir -p "$(dirname "$out")"
  if [ -f "$out" ]; then
    local got
    got="$(md5_file "$out")"
    if [ "$got" = "$expected" ]; then
      return 0
    fi
    rm -f "$out"
  fi

  echo "下载: $url"
  download_file "$url" "$out"
  local got
  got="$(md5_file "$out")"
  if [ "$got" != "$expected" ]; then
    echo "错误: MD5 校验失败: $out"
    echo "期望: $expected"
    echo "实际: $got"
    return 1
  fi
}

collect_flutter_targets() {
  local os_name="$1"
  local metadata_url=""
  case "$os_name" in
    windows) metadata_url="https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json" ;;
    linux) metadata_url="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" ;;
    macos) metadata_url="https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json" ;;
    *)
      echo "错误: 未知 Flutter 平台: $os_name" >&2
      return 1
      ;;
  esac

  local metadata_file
  metadata_file="$(mktemp "${TMPDIR:-/tmp}/saki_flutter_meta.XXXXXX.json")"
  download_file "$metadata_url" "$metadata_file"

  "$PYTHON_BIN" - "$metadata_file" "$os_name" <<'PY'
import json
import pathlib
import sys

metadata_file = pathlib.Path(sys.argv[1])
os_name = sys.argv[2]

data = json.loads(metadata_file.read_text(encoding="utf-8"))
base_url = data["base_url"].rstrip("/")
stable_hash = data["current_release"]["stable"]
releases = data["releases"]
stable_release = next((r for r in releases if r.get("hash") == stable_hash), None)
if stable_release is None:
    raise SystemExit("failed to resolve flutter stable release")

targets = []
if os_name != "macos":
    targets.append((os_name, stable_release))
else:
    version = stable_release.get("version")
    stable_releases = [
        r for r in releases
        if r.get("channel") == "stable" and r.get("version") == version
    ]
    arm = next((r for r in stable_releases if "arm64" in r.get("archive", "")), None)
    x64 = next((r for r in stable_releases if "x64" in r.get("archive", "")), None)
    if arm is not None:
        targets.append(("macos-arm64", arm))
    if x64 is not None:
        targets.append(("macos-x64", x64))
    if not targets:
        targets.append(("macos", stable_release))

for platform, release in targets:
    archive = release["archive"]
    sha256 = release.get("sha256", "")
    version = release.get("version", "unknown")
    print(f"{platform}|{version}|{archive}|{sha256}|{base_url}/{archive}")
PY

  rm -f "$metadata_file"
}

collect_node_targets() {
  local index_file
  index_file="$(mktemp "${TMPDIR:-/tmp}/saki_node_index.XXXXXX.json")"
  download_file "https://nodejs.org/dist/index.json" "$index_file"

  "$PYTHON_BIN" - "$index_file" <<'PY'
import json
import pathlib
import sys
import urllib.request

index_file = pathlib.Path(sys.argv[1])
index_data = json.loads(index_file.read_text(encoding="utf-8"))
release = next((r for r in index_data if r.get("lts")), None)
if release is None:
    raise SystemExit("failed to resolve node lts release")

version = release["version"]
targets = [
    ("windows-x64", f"node-{version}-win-x64.zip"),
    ("linux-x64", f"node-{version}-linux-x64.tar.xz"),
    ("macos-arm64", f"node-{version}-darwin-arm64.tar.gz"),
    ("macos-x64", f"node-{version}-darwin-x64.tar.gz"),
]

sum_url = f"https://nodejs.org/dist/{version}/SHASUMS256.txt"
sum_text = urllib.request.urlopen(sum_url).read().decode("utf-8")
sum_map = {}
for raw in sum_text.splitlines():
    line = raw.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) >= 2:
        sum_map[parts[1]] = parts[0]

for platform, archive in targets:
    sha256 = sum_map.get(archive)
    if not sha256:
        continue
    url = f"https://nodejs.org/dist/{version}/{archive}"
    print(f"{platform}|{version}|{archive}|{sha256}|{url}")
PY

  rm -f "$index_file"
}

prepare_workspace() {
  mkdir -p "$WORK_DIR"
  rm -rf "$ENGINE_DIR"
  mkdir -p "$ENGINE_DIR"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='.git/' \
      --exclude='.saki_toolchain/' \
      --exclude='dist/' \
      --exclude='tool/toolchain_cache/' \
      --exclude='**/.dart_tool/' \
      --exclude='**/.idea/' \
      --exclude='**/.DS_Store' \
      --exclude='**/build/' \
      --exclude='**/.flutter-plugins-dependencies' \
      "$REPO_ROOT/" "$ENGINE_DIR/"
  else
    cp -R "$REPO_ROOT/." "$ENGINE_DIR/"
    rm -rf "$ENGINE_DIR/.git" "$ENGINE_DIR/.saki_toolchain" "$ENGINE_DIR/dist" "$ENGINE_DIR/tool/toolchain_cache"
  fi

  mkdir -p "$FLUTTER_CACHE_DIR" "$NODE_CACHE_DIR" "$MEDIAKIT_PREBUILT_DIR"
}

write_manifest_header() {
  cat > "$MANIFEST_FILE" <<EOF
SakiEngine Distribution Manifest
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Package: $PACKAGE_NAME

[Flutter]
EOF
}

append_manifest() {
  printf '%s\n' "$1" >> "$MANIFEST_FILE"
}

download_flutter_archives() {
  local os_name
  for os_name in windows linux macos; do
    while IFS='|' read -r platform version archive sha256 url; do
      [ -z "$archive" ] && continue
      ensure_download_sha256 "$url" "$FLUTTER_CACHE_DIR/$archive" "$sha256"
      append_manifest "$platform $version $archive $sha256"
    done < <(collect_flutter_targets "$os_name")
  done
}

download_node_archives() {
  append_manifest ""
  append_manifest "[Node.js]"
  while IFS='|' read -r platform version archive sha256 url; do
    [ -z "$archive" ] && continue
    ensure_download_sha256 "$url" "$NODE_CACHE_DIR/$archive" "$sha256"
    append_manifest "$platform $version $archive $sha256"
  done < <(collect_node_targets)
}

download_media_kit_archives() {
  append_manifest ""
  append_manifest "[media_kit windows prebuilt]"

  local mpv_name="mpv-dev-x86_64-20230924-git-652a1dd.7z"
  local mpv_url="https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${mpv_name}"
  local mpv_md5="a832ef24b3a6ff97cd2560b5b9d04cd8"

  local angle_name="ANGLE.7z"
  local angle_url="https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/${angle_name}"
  local angle_md5="e866f13e8d552348058afaafe869b1ed"

  ensure_download_md5 "$mpv_url" "$MEDIAKIT_PREBUILT_DIR/$mpv_name" "$mpv_md5"
  ensure_download_md5 "$angle_url" "$MEDIAKIT_PREBUILT_DIR/$angle_name" "$angle_md5"

  append_manifest "windows ${mpv_name} md5=${mpv_md5}"
  append_manifest "windows ${angle_name} md5=${angle_md5}"
}

create_zip_package() {
  if ! command -v zip >/dev/null 2>&1; then
    echo "错误: 未检测到 zip 命令。"
    return 1
  fi
  (
    cd "$WORK_DIR"
    zip -qr "${PACKAGE_NAME}.zip" "SakiEngine"
  )
}

main() {
  echo "准备分发目录: $WORK_DIR"
  prepare_workspace
  write_manifest_header
  download_flutter_archives
  download_node_archives
  download_media_kit_archives
  create_zip_package

  echo ""
  echo "分发目录: $WORK_DIR/SakiEngine"
  echo "分发压缩包: $WORK_DIR/${PACKAGE_NAME}.zip"
  echo "清单文件: $MANIFEST_FILE"
}

main "$@"
