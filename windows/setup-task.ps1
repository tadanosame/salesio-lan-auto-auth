# タスクスケジューラへの登録スクリプト

$scriptPath = Join-Path $PSScriptRoot "campus-login.ps1"
$scriptPath = (Resolve-Path $scriptPath).Path

# ウィンドウを出さずに起動するためのランチャー（wscript.exe 経由）
$launcherPath = (Resolve-Path (Join-Path $PSScriptRoot "run-hidden.js")).Path

# 認証切れチェックの間隔（分）
$IntervalMinutes = 5
$startBoundary = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$env:USERDOMAIN\$env:USERNAME</UserId>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"&gt;&lt;Select Path="Microsoft-Windows-NetworkProfile/Operational"&gt;*[System[EventID=10000]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
      <Delay>PT10S</Delay>
    </EventTrigger>
    <TimeTrigger>
      <Enabled>true</Enabled>
      <StartBoundary>$startBoundary</StartBoundary>
      <Repetition>
        <Interval>PT$($IntervalMinutes)M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$env:USERDOMAIN\$env:USERNAME</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions>
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>//B //Nologo //E:JScript "$launcherPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$xmlPath = "$env:TEMP\campus-login-task.xml"
$xml | Out-File $xmlPath -Encoding Unicode
Register-ScheduledTask -TaskName "campus-login" -Xml (Get-Content $xmlPath -Raw) -Force
Remove-Item $xmlPath

Write-Host "タスク登録完了" -ForegroundColor Green
Write-Host "  - ログオン時に自動認証" -ForegroundColor Cyan
Write-Host "  - ネットワーク再接続時（10秒後）に自動認証" -ForegroundColor Cyan
Write-Host "  - $IntervalMinutes 分ごとに認証切れをチェックして再認証" -ForegroundColor Cyan
Write-Host "ログ: $env:LOCALAPPDATA\campus-login\campus-login.log" -ForegroundColor Cyan
Write-Host "スクリプトパス: $scriptPath" -ForegroundColor Cyan
