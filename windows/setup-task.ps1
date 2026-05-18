# タスクスケジューラへの登録スクリプト（管理者として実行してください）

$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "windows\campus-login.ps1"
$scriptPath = (Resolve-Path $scriptPath).Path

$action = New-ScheduledTaskAction `
    -Execute "powershell" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

Register-ScheduledTask -TaskName "campus-login" -Action $action -Trigger $trigger -RunLevel Limited -Force

Write-Host "タスク登録完了: ログオン時に自動でキャンパス認証が実行されます" -ForegroundColor Green
Write-Host "スクリプトパス: $scriptPath" -ForegroundColor Cyan
