# 学内ネットワーク自動認証スクリプト
# 初回: check-login-form.ps1 を実行してフィールド名を確認し、下記を修正してください

$LoginUrl = "http://172.30.0.1/login.html"
$UserField = "uid"
$PassField = "pwd"

# インターネット疎通判定用 URL（Windows の NCSI と同じもの）
$ProbeUrl     = "http://www.msftconnecttest.com/connecttest.txt"
$ProbeContent = "Microsoft Connect Test"

# .env ファイルから認証情報を読み込む（スクリプトと同階層 → 親ディレクトリの順で探す）
$EnvFile = Join-Path $PSScriptRoot ".env"
if (-not (Test-Path $EnvFile)) {
    $EnvFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | Where-Object { $_ -match "^\s*\w+=.+" } | ForEach-Object {
        $key, $val = $_ -split "=", 2
        Set-Variable -Name $key.Trim() -Value $val.Trim()
    }
}

# ログ（タスクスケジューラからは非表示で動くため、ファイルにも残す）
$LogDir  = Join-Path $env:LOCALAPPDATA "campus-login"
$LogFile = Join-Path $LogDir "campus-login.log"
function Write-Log([string]$Message, [string]$Color = "White") {
    Write-Host $Message -ForegroundColor $Color
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File $LogFile -Append -Encoding UTF8
        if ((Get-Item $LogFile).Length -gt 1MB) { Move-Item $LogFile "$LogFile.old" -Force }
    } catch {}
}

# 認証ポータルに横取りされずにインターネットへ出られるかを HTTP で判定
# （ping は認証切れでも通ることがあるため使わない）
function Test-Online {
    try {
        $r = Invoke-WebRequest -Uri $ProbeUrl -UseBasicParsing -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
        $content = $r.Content
        if ($content -is [byte[]]) { $content = [Text.Encoding]::ASCII.GetString($content) }
        return ($r.StatusCode -eq 200 -and "$content".Trim() -eq $ProbeContent)
    } catch {
        return $false
    }
}

# 既にオンラインなら何もしない（定期実行のたびにログインしないため）
if (Test-Online) { exit 0 }

# 認証ページ取得。届かなければ学内LANではないので静かに終了
try {
    $session = $null
    $page = Invoke-WebRequest -Uri $LoginUrl -SessionVariable session -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
} catch {
    Write-Host "認証サーバーに接続できません（学内LAN外）。終了します。" -ForegroundColor Gray
    exit 0
}

Write-Log "オフラインを検知。再認証します。" "Cyan"

try {
    # Regex でフォームの action を取得
    $actionMatch = [regex]::Match($page.Content, '<form[^>]+action="([^"]*)"', 'IgnoreCase')
    $actionPath = if ($actionMatch.Success) { $actionMatch.Groups[1].Value } else { "" }

    # フォームの Action URL を解決
    if ($actionPath -and $actionPath -notmatch "^http") {
        $base = [Uri]$LoginUrl
        $postUrl = "$($base.Scheme)://$($base.Host)$actionPath"
    } elseif ($actionPath) {
        $postUrl = $actionPath
    } else {
        $postUrl = $LoginUrl
    }

    # hidden フィールドのみ収集（user/pass の空値重複を防ぐ）
    $body = @{}
    $hiddenMatches = [regex]::Matches($page.Content, '<input[^>]+type="hidden"[^>]*>', 'IgnoreCase')
    foreach ($match in $hiddenMatches) {
        $nameMatch  = [regex]::Match($match.Value, 'name="([^"]*)"',  'IgnoreCase')
        $valueMatch = [regex]::Match($match.Value, 'value="([^"]*)"', 'IgnoreCase')
        if ($nameMatch.Success) {
            $body[$nameMatch.Groups[1].Value] = if ($valueMatch.Success) { $valueMatch.Groups[1].Value } else { "" }
        }
    }

    # 認証情報をセット
    $body[$UserField] = $STUDENT_ID
    $body[$PassField] = $PASSWORD

    # POST 送信
    $result = Invoke-WebRequest -Uri $postUrl -Method POST -Body $body `
        -WebSession $session -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5

    # レスポンスボディでログインページが返ってきたか確認
    if ($result.Content -match 'action="[^"]*loginprocess|type="password"') {
        Write-Log "認証失敗: ユーザーIDまたはパスワードが違います（HTTP $($result.StatusCode)）" "Red"
        exit 1
    }

    Write-Log "認証成功（HTTP $($result.StatusCode)）" "Green"

    # インターネット疎通確認（最大90秒リトライ）
    Write-Host "疎通確認中..." -ForegroundColor Cyan
    $connected = $false
    for ($i = 1; $i -le 9; $i++) {
        if (Test-Online) {
            $connected = $true
            break
        }
        Write-Host "  待機中... ($($i * 10)秒)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
    if ($connected) {
        Write-Log "インターネット接続OK" "Green"
    } else {
        Write-Log "90秒待っても疎通なし。手動で確認してください。" "Yellow"
    }

} catch {
    Write-Log "エラー: $_" "Red"
    exit 1
}
