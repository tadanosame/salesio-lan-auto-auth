# 学内ネットワーク自動認証スクリプト
# 初回: check-login-form.ps1 を実行してフィールド名を確認し、下記を修正してください
#
# 使い方:
#   campus-login.ps1            オフラインなら（ログアウト→）ログイン。一定時間経過していれば先回りして再ログイン
#   campus-login.ps1 -Relogin   状態に関係なくログアウト→ログインを実行
#   campus-login.ps1 -Logout    ログアウトのみ

param(
    [switch]$Relogin,
    [switch]$Logout
)

$LoginUrl = "http://172.30.0.1/login.html"
$UserField = "uid"
$PassField = "pwd"

# ログアウト先（ポータルの HTML 上は /cgibin/Logout.cgi。表記揺れに備えて /cgi-bin も試す）
$LogoutPaths = @("/cgibin/Logout.cgi", "/cgi-bin/Logout.cgi")

# インターネット疎通判定用 URL（Windows の NCSI と同じもの）
$ProbeUrl     = "http://www.msftconnecttest.com/connecttest.txt"
$ProbeContent = "Microsoft Connect Test"

# 先回り再ログインまでの時間（時間）。.env の RELOGIN_HOURS で上書き可。0 で無効
$RELOGIN_HOURS = 11

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
$ReloginHours = 0.0
if (-not [double]::TryParse("$RELOGIN_HOURS", [ref]$ReloginHours)) { $ReloginHours = 11 }

$PortalBase = ([Uri]$LoginUrl).GetLeftPart([UriPartial]::Authority)

# ログ・状態ファイル（タスクスケジューラからは非表示で動くため、ファイルにも残す）
$LogDir        = Join-Path $env:LOCALAPPDATA "campus-login"
$LogFile       = Join-Path $LogDir "campus-login.log"
$LastLoginFile = Join-Path $LogDir "last-login.txt"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log([string]$Message, [string]$Color = "White") {
    Write-Host $Message -ForegroundColor $Color
    try {
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

function Test-Portal {
    try {
        Invoke-WebRequest -Uri $LoginUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# 最後にこのスクリプトでログインした時刻（記録がなければ $null）
function Get-LastLogin {
    try {
        if (Test-Path $LastLoginFile) {
            return [datetime]::Parse((Get-Content $LastLoginFile -Raw).Trim())
        }
    } catch {}
    return $null
}

function Invoke-PortalLogout {
    foreach ($path in $LogoutPaths) {
        try {
            $r = Invoke-WebRequest -Uri "$PortalBase$path" -Method POST -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Log "ログアウト送信: $path（HTTP $($r.StatusCode)）" "Cyan"
            return $true
        } catch {
            Write-Log "ログアウト失敗: $path（$($_.Exception.Message)）" "Gray"
        }
    }
    return $false
}

function Invoke-PortalLogin {
    $session = $null
    $page = Invoke-WebRequest -Uri $LoginUrl -SessionVariable session -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop

    # Regex でフォームの action を取得
    $actionMatch = [regex]::Match($page.Content, '<form[^>]+action="([^"]*)"', 'IgnoreCase')
    $actionPath = if ($actionMatch.Success) { $actionMatch.Groups[1].Value } else { "" }

    # フォームの Action URL を解決
    if ($actionPath -and $actionPath -notmatch "^http") {
        $postUrl = "$PortalBase$actionPath"
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
        -WebSession $session -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5 -ErrorAction Stop

    # レスポンスボディでログインページが返ってきたか確認
    if ($result.Content -match 'action="[^"]*(loginprocess|Login\.cgi)|type="password"') {
        Write-Log "認証失敗: ログインページが返されました（HTTP $($result.StatusCode)）" "Red"
        return $false
    }

    Write-Log "認証成功（HTTP $($result.StatusCode)）" "Green"
    (Get-Date).ToString("o") | Out-File $LastLoginFile -Encoding ASCII
    return $true
}

function Wait-Online {
    Write-Host "疎通確認中..." -ForegroundColor Cyan
    for ($i = 1; $i -le 9; $i++) {
        if (Test-Online) { return $true }
        Write-Host "  待機中... ($($i * 10)秒)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
    return $false
}

# ===== メイン =====
try {
    if ($Logout) {
        Invoke-PortalLogout | Out-Null
        Remove-Item $LastLoginFile -ErrorAction SilentlyContinue
        exit 0
    }

    $online = Test-Online

    # 先回り再ログイン判定（このスクリプトでログインしてから一定時間経過）
    $due = $false
    $last = Get-LastLogin
    if ($ReloginHours -gt 0 -and $last -and ((Get-Date) - $last).TotalHours -ge $ReloginHours) {
        $due = $true
    }

    if ($online -and -not $due -and -not $Relogin) { exit 0 }

    # 認証サーバーに届かなければ学内LAN外なので静かに終了
    if (-not (Test-Portal)) {
        Write-Host "認証サーバーに接続できません（学内LAN外）。終了します。" -ForegroundColor Gray
        exit 0
    }

    if ($Relogin) {
        Write-Log "手動指定により再ログインします。" "Cyan"
    } elseif ($due) {
        Write-Log "前回ログインから $ReloginHours 時間経過。先回りして再ログインします。" "Cyan"
    } else {
        Write-Log "オフラインを検知。ログアウト→再ログインします。" "Cyan"
    }

    # セッションが残ったままだと再ログインできないため、先にログアウトする
    Invoke-PortalLogout | Out-Null
    Start-Sleep -Seconds 3

    $ok = Invoke-PortalLogin
    if (-not $ok) {
        # ログアウト直後で弾かれた可能性に備えて1回だけリトライ
        Start-Sleep -Seconds 5
        $ok = Invoke-PortalLogin
    }
    if (-not $ok) { exit 1 }

    if (Wait-Online) {
        Write-Log "インターネット接続OK" "Green"
    } else {
        Write-Log "90秒待っても疎通なし。手動で確認してください。" "Yellow"
        exit 1
    }

} catch {
    Write-Log "エラー: $_" "Red"
    exit 1
}
