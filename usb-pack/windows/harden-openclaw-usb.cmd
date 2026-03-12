@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0harden-local-feishu.ps1"
endlocal
