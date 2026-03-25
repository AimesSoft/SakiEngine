@echo off
setlocal EnableExtensions

chcp 65001 >nul

for %%I in ("%~dp0.") do set "REPO_ROOT=%%~fI"

call "%REPO_ROOT%\tool\ensure_node.bat"
if errorlevel 1 exit /b 1

"%SAKI_NODE_BIN%" "%REPO_ROOT%\tool\saki_cli.js" saki %*
exit /b %errorlevel%
