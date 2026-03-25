@echo off
setlocal EnableExtensions

chcp 65001 >nul

for %%I in ("%~dp0..") do set "REPO_ROOT=%%~fI"
set "DEST_DIR=%REPO_ROOT%\third_party\media_kit_libs_windows_video_hotfix\prebuilt"

if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

call :download_and_verify ^
  "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z" ^
  "mpv-dev-x86_64-20230924-git-652a1dd.7z" ^
  "a832ef24b3a6ff97cd2560b5b9d04cd8"
if errorlevel 1 exit /b 1

call :download_and_verify ^
  "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z" ^
  "ANGLE.7z" ^
  "e866f13e8d552348058afaafe869b1ed"
if errorlevel 1 exit /b 1

echo.
echo 已完成 media_kit Windows 依赖缓存。
echo 目录: %DEST_DIR%
exit /b 0

:download_and_verify
set "URL=%~1"
set "FILE_NAME=%~2"
set "EXPECTED_MD5=%~3"
set "OUT_FILE=%DEST_DIR%\%FILE_NAME%"

if exist "%OUT_FILE%" (
  call :compute_md5 "%OUT_FILE%"
  if /I "%ACTUAL_MD5%"=="%EXPECTED_MD5%" (
    echo 已存在并校验通过: %FILE_NAME%
    exit /b 0
  )
  echo 本地缓存校验失败，重新下载: %FILE_NAME%
  del /f /q "%OUT_FILE%" >nul 2>&1
)

echo 下载: %FILE_NAME%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%URL%' -OutFile '%OUT_FILE%'"
if errorlevel 1 (
  echo 下载失败: %FILE_NAME%
  exit /b 1
)

call :compute_md5 "%OUT_FILE%"
if /I not "%ACTUAL_MD5%"=="%EXPECTED_MD5%" (
  echo MD5 校验失败: %FILE_NAME%
  echo 期望: %EXPECTED_MD5%
  echo 实际: %ACTUAL_MD5%
  exit /b 1
)

echo 校验通过: %FILE_NAME%
exit /b 0

:compute_md5
set "TARGET_FILE=%~1"
set "ACTUAL_MD5="
for /f %%H in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -Algorithm MD5 '%TARGET_FILE%').Hash.ToLower()"') do (
  set "ACTUAL_MD5=%%H"
)
exit /b 0
