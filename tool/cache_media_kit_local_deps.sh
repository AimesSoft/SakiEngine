#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

download() {
  local url="$1"
  local output="$2"
  local checksum="$3"
  local mode="$4"

  mkdir -p "$(dirname "$output")"
  curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -o "$output" "$url"

  local actual
  if [ "$mode" = "md5" ]; then
    actual="$(md5 -q "$output")"
  else
    actual="$(shasum -a 256 "$output" | awk '{print $1}')"
  fi

  if [ "$actual" != "$checksum" ]; then
    echo "checksum mismatch: $output"
    echo "expected: $checksum"
    echo "actual:   $actual"
    exit 1
  fi
}

download \
  "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z" \
  "$REPO_ROOT/third_party/media_kit_libs_windows_video_hotfix/prebuilt/mpv-dev-x86_64-20230924-git-652a1dd.7z" \
  "a832ef24b3a6ff97cd2560b5b9d04cd8" \
  "md5"

download \
  "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z" \
  "$REPO_ROOT/third_party/media_kit_libs_windows_video_hotfix/prebuilt/ANGLE.7z" \
  "e866f13e8d552348058afaafe869b1ed" \
  "md5"

download \
  "https://github.com/media-kit/libmpv-darwin-build/releases/download/v0.6.0/libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz" \
  "$REPO_ROOT/third_party/media_kit_libs_macos_video_hotfix/prebuilt/libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz" \
  "84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6" \
  "sha256"

download \
  "https://github.com/media-kit/libmpv-darwin-build/releases/download/v0.6.0/libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz" \
  "$REPO_ROOT/third_party/media_kit_libs_ios_video_hotfix/prebuilt/libmpv-xcframeworks_v0.6.0_ios-universal-video-default.tar.gz" \
  "a95bc18508af26136b8a408341c05b5585d644ec013f00ac07db09d2e28d36ae" \
  "sha256"

download \
  "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.5/default-arm64-v8a.jar" \
  "$REPO_ROOT/third_party/media_kit_libs_android_video_hotfix/prebuilt/default-arm64-v8a.jar" \
  "5f521b08692d7fef73c5df9bcc00ca4d" \
  "md5"

download \
  "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.5/default-armeabi-v7a.jar" \
  "$REPO_ROOT/third_party/media_kit_libs_android_video_hotfix/prebuilt/default-armeabi-v7a.jar" \
  "08d500ca1116c13e9c1296cc6f2207b0" \
  "md5"

download \
  "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.5/default-x86_64.jar" \
  "$REPO_ROOT/third_party/media_kit_libs_android_video_hotfix/prebuilt/default-x86_64.jar" \
  "0880d5fbc3ff0053409704617f54cb55" \
  "md5"

download \
  "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.5/default-x86.jar" \
  "$REPO_ROOT/third_party/media_kit_libs_android_video_hotfix/prebuilt/default-x86.jar" \
  "f6f51aa42b30d747099506cdc3277352" \
  "md5"

download \
  "https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.2.tar.gz" \
  "$REPO_ROOT/third_party/media_kit_libs_linux_hotfix/prebuilt/mimalloc-2.1.2.tar.gz" \
  "5179c8f5cf1237d2300e2d8559a7bc55" \
  "md5"

echo "media_kit local prebuilt dependencies are ready."
