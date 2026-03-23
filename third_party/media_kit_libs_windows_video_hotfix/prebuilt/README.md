# Windows Prebuilt Cache For media_kit

This directory is used by `media_kit_libs_windows_video` hotfix to avoid
runtime download during CMake configure/build on new machines.

Put these 2 archives here:

- `mpv-dev-x86_64-20230924-git-652a1dd.7z`
- `ANGLE.7z`

Expected MD5:

- `mpv-dev-x86_64-20230924-git-652a1dd.7z` -> `a832ef24b3a6ff97cd2560b5b9d04cd8`
- `ANGLE.7z` -> `e866f13e8d552348058afaafe869b1ed`

Download URLs:

- https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z
- https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z

Optional override:

- CMake variable:
  `-DSAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR=<dir>`
- Environment variable:
  `SAKI_MEDIA_KIT_WINDOWS_PREBUILT_DIR=<dir>`

If local file checksum does not match, the build falls back to online download.
