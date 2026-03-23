@echo off
setlocal EnableExtensions

rem Force UTF-8 console session to avoid garbled Chinese logs/windows.
chcp 65001 >nul

for %%I in ("%~dp0.") do set "REPO_ROOT=%%~fI"
set "TARGET_GAME=%~1"
set "GAME_DIR=%REPO_ROOT%\Game\%TARGET_GAME%"
set "BRIDGE_SCRIPT=%REPO_ROOT%\scripts\launcher-bridge.js"

where flutter >nul 2>&1
if errorlevel 1 (
  echo 错误: 未检测到 flutter，请先安装并配置 Flutter SDK。
  exit /b 1
)

set "PREFERRED_DEVICE=windows"
set "DEVICE="

flutter devices --machine | findstr /R /C:"\"id\"[ ]*:[ ]*\"%PREFERRED_DEVICE%\"" >nul
if not errorlevel 1 set "DEVICE=%PREFERRED_DEVICE%"

if not defined DEVICE (
  flutter devices --machine | findstr /R /C:"\"id\"[ ]*:[ ]*\"chrome\"" >nul
  if not errorlevel 1 set "DEVICE=chrome"
)

if not defined DEVICE (
  echo 错误: 未检测到可用运行设备（%PREFERRED_DEVICE%/chrome）。
  flutter devices
  exit /b 1
)

echo 使用设备: %DEVICE%

if defined TARGET_GAME (
  if not exist "%GAME_DIR%\pubspec.yaml" (
    echo 错误: 指定项目不存在或不是 Flutter 项目: %TARGET_GAME%
    echo 可用项目:
    for /d %%D in ("%REPO_ROOT%\Game\*") do (
      if exist "%%~fD\pubspec.yaml" echo   - %%~nxD
    )
    exit /b 1
  )

  echo 直启游戏项目: %TARGET_GAME%

  where node >nul 2>&1
  if errorlevel 1 (
    echo 警告: 未检测到 node，跳过项目准备步骤（应用身份/图标同步）。
  ) else (
    call node "%BRIDGE_SCRIPT%" prepare-project --game "%TARGET_GAME%"
    if errorlevel 1 exit /b 1
  )

  cd /d "%GAME_DIR%"
  if errorlevel 1 exit /b 1

  call flutter pub get
  if errorlevel 1 exit /b 1

  where node >nul 2>&1
  if not errorlevel 1 (
    call node "%BRIDGE_SCRIPT%" prepare-project --game "%TARGET_GAME%" --generate-icons
    if errorlevel 1 exit /b 1
  )

  flutter run -d %DEVICE% "--dart-define=SAKI_GAME_PATH=%GAME_DIR%"
  exit /b %errorlevel%
)

cd /d "%REPO_ROOT%\Launcher"
if errorlevel 1 exit /b 1
call flutter pub get
if errorlevel 1 exit /b 1
flutter run -d %DEVICE% "--dart-define=SAKI_REPO_ROOT=%REPO_ROOT%"
exit /b %errorlevel%
