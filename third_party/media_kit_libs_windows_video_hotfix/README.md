# media_kit_libs_windows_video hotfix

Local override for Windows CMake stability in SakiEngine.

Changes from upstream `1.0.11`:

- Bundle `windows/ANGLE.7z` in-repo and prefer it by default for offline builds.
- Add download timeout & inactivity timeout.
- Add retry for unstable network downloads.
- Fail fast on download error instead of hanging forever.
- Remove partial archive on failure to avoid poisoned cache.
- Support URL override via environment variables:
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_URL`
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_URL`
- Support local archive override via environment variables:
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_LIBMPV_ARCHIVE`
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_ANGLE_ARCHIVE`
- Support timeout override via environment variables:
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_TIMEOUT_SECONDS`
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_INACTIVITY_TIMEOUT_SECONDS`
- Support retry count override:
  - `MEDIA_KIT_LIBS_WINDOWS_VIDEO_DOWNLOAD_RETRY_COUNT`
- Add explicit `POST_BUILD` in `add_custom_command` to silence CMP0175 warning.
