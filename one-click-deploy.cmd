@echo off
setlocal
call "%~dp0usb-pack\one-click-deploy.cmd"
set "CODE=%ERRORLEVEL%"
exit /b %CODE%
