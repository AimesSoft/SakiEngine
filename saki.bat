@echo off
setlocal EnableExtensions

rem Force UTF-8 console session to avoid garbled Chinese logs/windows.
chcp 65001 >nul

cd /d "%~dp0Launcher"
for %%I in ("%~dp0.") do set "REPO_ROOT=%%~fI"

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

call flutter pub get
if errorlevel 1 exit /b 1
flutter run -d %DEVICE% "--dart-define=SAKI_REPO_ROOT=%REPO_ROOT%"
