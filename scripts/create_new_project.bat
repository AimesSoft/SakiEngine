@echo off
setlocal

cd /d "%~dp0"

node "%~dp0create-new-project.js"
set EXIT_CODE=%ERRORLEVEL%

endlocal & exit /b %EXIT_CODE%
