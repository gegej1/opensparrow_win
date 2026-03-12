@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-local-feishu.ps1"
endlocal
