# 学内ネットワーク自動認証スクリプト
# 初回: check-login-form.ps1 を実行してフィールド名を確認し、下記を修正してください

$LoginUrl = "http://172.30.0.1/EWA/index.html"
$UserField = "user"
$PassField = "pass"

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

try {
    # セッション取得
    $session = $null
    $page = Invoke-WebRequest -Uri $LoginUrl -SessionVariable session -UseBasicParsing -TimeoutSec 10

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
        Write-Host "認証失敗: ユーザーIDまたはパスワードが違います（HTTP $($result.StatusCode)）" -ForegroundColor Red
        exit 1
    }

    Write-Host "認証成功（HTTP $($result.StatusCode)）" -ForegroundColor Green

    # インターネット疎通確認（最大90秒リトライ）
    Write-Host "疎通確認中..." -ForegroundColor Cyan
    $connected = $false
    for ($i = 1; $i -le 9; $i++) {
        if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet) {
            $connected = $true
            break
        }
        Write-Host "  待機中... ($($i * 10)秒)" -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
    if ($connected) {
        Write-Host "インターネット接続OK" -ForegroundColor Green
    } else {
        Write-Host "90秒待っても疎通なし。手動で確認してください。" -ForegroundColor Yellow
    }

} catch {
    Write-Host "エラー: $_" -ForegroundColor Red
    exit 1
}
