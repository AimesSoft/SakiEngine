@echo off

for %%I in ("%~dp0..") do set "REPO_ROOT=%%~fI"
set "CACHE_DIR=%REPO_ROOT%\tool\toolchain_cache\node"
set "INSTALL_ROOT=%REPO_ROOT%\.saki_toolchain\node"
set "MARKER_FILE=%INSTALL_ROOT%\.current_path"

if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
if not exist "%INSTALL_ROOT%" mkdir "%INSTALL_ROOT%"

for /f "delims=" %%N in ('where node 2^>nul') do (
  set "SAKI_NODE_BIN=%%N"
  exit /b 0
)

if exist "%MARKER_FILE%" (
  set /p NODE_HOME=<"%MARKER_FILE%"
  if exist "%NODE_HOME%\node.exe" (
    set "SAKI_NODE_BIN=%NODE_HOME%\node.exe"
    exit /b 0
  )
)

set "META_FILE=%TEMP%\saki_node_meta_%RANDOM%%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$index=Invoke-RestMethod 'https://nodejs.org/dist/index.json';" ^
  "$release=$index | Where-Object { $_.lts } | Select-Object -First 1;" ^
  "if(-not $release){ throw 'failed to resolve node lts release'; }" ^
  "$version=$release.version;" ^
  "$archive=('node-' + $version + '-win-x64.zip');" ^
  "$sumUrl=('https://nodejs.org/dist/' + $version + '/SHASUMS256.txt');" ^
  "$sumText=(Invoke-WebRequest -Uri $sumUrl).Content;" ^
  "$sha='';" ^
  "foreach($line in ($sumText -split \"`n\")){ $trim=$line.Trim(); if($trim.EndsWith($archive)){ $sha=($trim -split '\s+')[0]; break } }" ^
  "if(-not $sha){ throw ('missing checksum for ' + $archive); }" ^
  "Write-Output ('NODE_VERSION=' + $version);" ^
  "Write-Output ('NODE_ARCHIVE=' + $archive);" ^
  "Write-Output ('NODE_SHA256=' + $sha)" > "%META_FILE%"
if errorlevel 1 (
  echo 错误: 获取 Node.js 版本信息失败
  exit /b 1
)

for /f "usebackq tokens=1,* delims==" %%A in ("%META_FILE%") do set "%%A=%%B"
del /f /q "%META_FILE%" >nul 2>&1

set "NODE_URL=https://nodejs.org/dist/%NODE_VERSION%/%NODE_ARCHIVE%"
set "ARCHIVE_PATH=%CACHE_DIR%\%NODE_ARCHIVE%"

if exist "%ARCHIVE_PATH%" (
  call :sha256 "%ARCHIVE_PATH%" NODE_FILE_SHA
  if /I not "%NODE_FILE_SHA%"=="%NODE_SHA256%" del /f /q "%ARCHIVE_PATH%" >nul 2>&1
)

if not exist "%ARCHIVE_PATH%" (
  echo 正在下载 Node.js: %NODE_VERSION%
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%NODE_URL%' -OutFile '%ARCHIVE_PATH%'"
  if errorlevel 1 (
    echo 错误: 下载 Node.js 失败
    exit /b 1
  )
)

call :sha256 "%ARCHIVE_PATH%" NODE_FILE_SHA
if /I not "%NODE_FILE_SHA%"=="%NODE_SHA256%" (
  echo 错误: Node.js 校验失败
  echo 期望: %NODE_SHA256%
  echo 实际: %NODE_FILE_SHA%
  exit /b 1
)

set "CLEAN_VERSION=%NODE_VERSION:v=%"
set "INSTALL_DIR=%INSTALL_ROOT%\node-%CLEAN_VERSION%-windows"
set "NODE_HOME=%INSTALL_DIR%\node-%NODE_VERSION%-win-x64"
if not exist "%NODE_HOME%\node.exe" (
  if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%"
  mkdir "%INSTALL_DIR%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Expand-Archive -Path '%ARCHIVE_PATH%' -DestinationPath '%INSTALL_DIR%' -Force"
  if errorlevel 1 (
    echo 错误: 解压 Node.js 失败
    exit /b 1
  )
)

if not exist "%NODE_HOME%\node.exe" (
  for /d %%D in ("%INSTALL_DIR%\*") do (
    if exist "%%~fD\node.exe" set "NODE_HOME=%%~fD"
  )
)

if not exist "%NODE_HOME%\node.exe" (
  echo 错误: Node.js 解压后未找到 node.exe
  exit /b 1
)

> "%MARKER_FILE%" echo %NODE_HOME%
set "SAKI_NODE_BIN=%NODE_HOME%\node.exe"
exit /b 0

:sha256
set "%~2="
for /f %%H in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -Algorithm SHA256 '%~1').Hash.ToLower()"') do (
  set "%~2=%%H"
)
exit /b 0
