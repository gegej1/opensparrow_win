@echo off
setlocal
set "ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%one-click-stop.ps1"
set "CODE=%ERRORLEVEL%"
exit /b %CODE%
