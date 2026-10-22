# 学内ネットワーク自動認証 セットアップスクリプト
#
# これ1つ実行するだけで設定が完了します:
#   1. ユーザーID・パスワードを入力して .env を作成
#   2. タスクスケジューラに自動実行タスクを登録
#   3. その場で1回実行して動作確認
#
# 使い方:
#   setup.bat をダブルクリック
#   または: powershell -ExecutionPolicy Bypass -File .\windows\setup-task.ps1
#   解除:   uninstall.bat をダブルクリック（または -Uninstall を付けて実行）

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$TaskName = "campus-login"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "■ $Message" -ForegroundColor Cyan
}

# ===== 解除 =====
if ($Uninstall) {
    Write-Step "自動実行タスクを解除します"
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  タスク「$TaskName」を削除しました。" -ForegroundColor Green
    } else {
        Write-Host "  タスク「$TaskName」は登録されていません。" -ForegroundColor Gray
    }
    Write-Host "  （.env とログ %LOCALAPPDATA%\campus-login は残しています。不要なら手動で削除してください）" -ForegroundColor Gray
    exit 0
}

$RootDir      = Split-Path $PSScriptRoot -Parent
$EnvFile      = Join-Path $RootDir ".env"
$scriptPath   = (Resolve-Path (Join-Path $PSScriptRoot "campus-login.ps1")).Path
# ウィンドウを出さずに起動するためのランチャー（wscript.exe 経由）
$launcherPath = (Resolve-Path (Join-Path $PSScriptRoot "run-hidden.js")).Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 学内ネットワーク自動認証 セットアップ" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ===== 1. 認証情報（.env） =====
Write-Step "1/3 ユーザーID・パスワードの設定"

$current = @{}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | Where-Object { $_ -match "^\s*\w+=.+" } | ForEach-Object {
        $key, $val = $_ -split "=", 2
        $current[$key.Trim()] = $val.Trim()
    }
}

$hasCredential = $current["STUDENT_ID"] -and $current["PASSWORD"] -and $current["STUDENT_ID"] -ne "your_student_id"
$useExisting = $false
if ($hasCredential) {
    Write-Host "  既存の設定があります（ユーザーID: $($current["STUDENT_ID"])）"
    $ans = Read-Host "  この設定を使いますか？ [Y/n]"
    $useExisting = ($ans -eq "" -or $ans -match "^[Yy]")
}

if (-not $useExisting) {
    do {
        $studentId = (Read-Host "  ユーザーID（学籍番号）").Trim()
    } while (-not $studentId)

    do {
        $secure = Read-Host "  パスワード（入力は表示されません）" -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    } while (-not $password)

    $reloginHours = if ($current["RELOGIN_HOURS"]) { $current["RELOGIN_HOURS"] } else { "11" }

    $lines = @(
        "STUDENT_ID=$studentId",
        "PASSWORD=$password",
        "# 前回ログインから何時間で先回り再ログインするか（0 で無効、既定 11）",
        "RELOGIN_HOURS=$reloginHours"
    )
    # BOM なし UTF-8 で保存（BOM があると1行目が読み込めないため）
    [IO.File]::WriteAllText($EnvFile, ($lines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))
    Write-Host "  保存しました: $EnvFile" -ForegroundColor Green
}

# ===== 2. タスク登録 =====
Write-Step "2/3 自動実行タスクの登録"

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

Register-ScheduledTask -TaskName $TaskName -Xml $xml -Force | Out-Null
Write-Host "  タスク「$TaskName」を登録しました。" -ForegroundColor Green
Write-Host "    - ログオン時に自動認証"
Write-Host "    - ネットワーク再接続時（10秒後）に自動認証"
Write-Host "    - $IntervalMinutes 分ごとに認証切れをチェックして再認証"

# ===== 3. 動作確認 =====
Write-Step "3/3 動作確認"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath
$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Host "  OK（接続済み、またはログイン成功。学内LAN外では何もしません）" -ForegroundColor Green
} else {
    Write-Host "  ログインに失敗しました。ユーザーID・パスワードを確認して、もう一度 setup.bat を実行してください。" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " セットアップ完了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  以降は何もしなくても、バックグラウンドで自動ログインします。"
Write-Host "  ログ:   $env:LOCALAPPDATA\campus-login\campus-login.log"
Write-Host "  解除:   uninstall.bat を実行"
Write-Host "  ※ フォルダを移動したら、もう一度 setup.bat を実行してください。"
