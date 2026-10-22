@echo off
rem Campus LAN auto-login: remove scheduled task
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\setup-task.ps1" -Uninstall
echo.
pause
