@echo off
setlocal
call "%~dp0usb-pack\one-click-stop.cmd"
set "CODE=%ERRORLEVEL%"
exit /b %CODE%
