@echo off
chcp 65001 >nul
setlocal
set "ROOT=%~dp0"
title OpenClaw One-Click Deploy
echo [deploy] Launching one-click deploy...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%one-click-deploy.ps1"
set "CODE=%ERRORLEVEL%"
exit /b %CODE%
