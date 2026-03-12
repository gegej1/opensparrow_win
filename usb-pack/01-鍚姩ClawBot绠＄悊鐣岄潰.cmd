@echo off
setlocal
call "%~dp0one-click-deploy.cmd"
set "CODE=%ERRORLEVEL%"
exit /b %CODE%
