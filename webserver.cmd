@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0webserver.ps1" %*
exit /b %ERRORLEVEL%
