@echo off

if "%SAKI_TOOLCHAIN_READY%"=="1" exit /b 0

for %%I in ("%~dp0..") do set "REPO_ROOT=%%~fI"

call "%REPO_ROOT%\tool\ensure_node.bat"
if errorlevel 1 exit /b 1

for /f "usebackq delims=" %%L in (`"%SAKI_NODE_BIN%" "%REPO_ROOT%\tool\bootstrap_env.js" --repo-root "%REPO_ROOT%" --format bat`) do (
  call %%L
)

set "SAKI_TOOLCHAIN_READY=1"
exit /b 0
