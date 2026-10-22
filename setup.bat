@echo off
rem Campus LAN auto-login: one-click setup
rem (enter ID/password, register scheduled task, test once)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\setup-task.ps1"
echo.
pause
