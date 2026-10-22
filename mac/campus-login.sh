#!/usr/bin/env bash
# 学内ネットワーク自動認証スクリプト（Mac / Linux 用）
# 初回: check-login-form.sh を実行してフィールド名を確認し、下記を修正してください
#
# 使い方:
#   campus-login.sh             オフラインなら（ログアウト→）ログイン。一定時間経過していれば先回りして再ログイン
#   campus-login.sh --relogin   状態に関係なくログアウト→ログインを実行
#   campus-login.sh --logout    ログアウトのみ
#
# ※ macOS 標準の bash 3.2 でも動くように書いています

LOGIN_URL="${LOGIN_URL:-http://172.30.0.1/login.html}"

# フィールド名（check-login-form.sh の出力に合わせて変更してください）
USER_FIELD="uid"
PASS_FIELD="pwd"

# ログアウト先（ポータルの HTML 上は /cgibin/Logout.cgi。表記揺れに備えて /cgi-bin も試す）
LOGOUT_PATHS="/cgibin/Logout.cgi /cgi-bin/Logout.cgi"

# インターネット疎通判定用 URL（Windows 版と同じもの）
PROBE_URL="http://www.msftconnecttest.com/connecttest.txt"
PROBE_CONTENT="Microsoft Connect Test"

# 先回り再ログインまでの時間（時間）。.env の RELOGIN_HOURS で上書き可。0 で無効
RELOGIN_HOURS=11

# ===== 引数 =====
MODE="auto"
for arg in "$@"; do
    case "$arg" in
        --relogin|-relogin|-Relogin) MODE="relogin" ;;
        --logout|-logout|-Logout)    MODE="logout" ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "不明な引数: $arg" >&2; exit 2 ;;
    esac
done

# ===== .env 読み込み（スクリプトと同階層 → 親ディレクトリの順で探す） =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"                       # Windows で作った .env（CRLF）にも対応
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"; val="${line#*=}"
        key="${key//[[:space:]]/}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        # 前後の空白を除去
        val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
        export "$key=$val"
    done < "$ENV_FILE"
fi
[[ "$RELOGIN_HOURS" =~ ^[0-9]+$ ]] || RELOGIN_HOURS=11

PORTAL_BASE=$(echo "$LOGIN_URL" | grep -oi 'https\?://[^/]*')

# ===== ログ・状態ファイル =====
if [ "$(uname -s)" = "Darwin" ]; then
    LOG_DIR="$HOME/Library/Logs/campus-login"
else
    LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/campus-login"
fi
LOG_FILE="$LOG_DIR/campus-login.log"
LAST_LOGIN_FILE="$LOG_DIR/last-login"
mkdir -p "$LOG_DIR"

log() {
    echo "$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
    # 1MB を超えたら .old に退避
    if [ "$(wc -c < "$LOG_FILE")" -gt 1048576 ]; then mv -f "$LOG_FILE" "$LOG_FILE.old"; fi
}

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/campus-login.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

# 認証ポータルに横取りされずにインターネットへ出られるかを HTTP で判定
# （ping は認証切れでも通ることがあるため使わない。リダイレクトは追わない）
test_online() {
    local body
    body=$(curl -s --max-time 5 "$PROBE_URL" 2>/dev/null | tr -d '\r\n')
    [ "$body" = "$PROBE_CONTENT" ]
}

# 認証サーバーに届くか（届かなければ学内LAN外）
test_portal() {
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$LOGIN_URL" 2>/dev/null)
    [ -n "$code" ] && [ "$code" != "000" ]
}

portal_logout() {
    local path code
    for path in $LOGOUT_PATHS; do
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -d '' "$PORTAL_BASE$path" 2>/dev/null)
        if [[ "$code" =~ ^[23] ]]; then
            log "ログアウト送信: $path（HTTP $code）"
            return 0
        fi
        log "ログアウト失敗: $path（HTTP ${code:-000}）"
    done
    return 1
}

portal_login() {
    local cookie="$TMP_DIR/cookie" response="$TMP_DIR/response" html action post_url status
    local tag type name value
    rm -f "$cookie" "$response"

    # ページ取得（Cookie・hidden フィールド収集）
    html=$(curl -s --max-time 10 -c "$cookie" "$LOGIN_URL")
    if [ $? -ne 0 ] || [ -z "$html" ]; then
        log "エラー: 認証サーバーに接続できませんでした"
        return 1
    fi

    # フォームの Action URL を解決
    action=$(echo "$html" | grep -oi '<form[^>]*>' | grep -oi 'action="[^"]*"' | head -1 | sed 's/[Aa][Cc][Tt][Ii][Oo][Nn]="//;s/"//')
    if [ -z "$action" ]; then
        post_url="$LOGIN_URL"
    elif [[ "$action" == http* ]]; then
        post_url="$action"
    else
        post_url="${PORTAL_BASE}${action}"
    fi

    # hidden フィールドのみ body に追加（user/pass の空値重複を防ぐ）
    BODY_ARGS=()
    while IFS= read -r tag; do
        [ -z "$tag" ] && continue
        type=$(echo "$tag"  | grep -oi 'type="[^"]*"'  | sed 's/^[^"]*"//;s/"$//')
        name=$(echo "$tag"  | grep -oi 'name="[^"]*"'  | sed 's/^[^"]*"//;s/"$//')
        value=$(echo "$tag" | grep -oi 'value="[^"]*"' | sed 's/^[^"]*"//;s/"$//')
        if [ -n "$name" ] && [ "$(echo "$type" | tr '[:upper:]' '[:lower:]')" = "hidden" ]; then
            BODY_ARGS+=("--data-urlencode" "${name}=${value}")
        fi
    done <<EOF
$(echo "$html" | grep -oi '<input[^>]*>')
EOF

    # 認証情報をセット
    BODY_ARGS+=("--data-urlencode" "${USER_FIELD}=${STUDENT_ID}")
    BODY_ARGS+=("--data-urlencode" "${PASS_FIELD}=${PASSWORD}")

    # POST 送信（リダイレクト追跡、レスポンスボディも取得）
    status=$(curl -s -L --max-time 10 -b "$cookie" -c "$cookie" \
        -o "$response" -w "%{http_code}" \
        "${BODY_ARGS[@]}" "$post_url")

    # ログインページが返ってきたら失敗
    if grep -Eqi 'action="[^"]*(loginprocess|login\.cgi)|type="password"' "$response" 2>/dev/null; then
        log "認証失敗: ログインページが返されました（HTTP ${status}）"
        return 1
    fi
    if ! [[ "$status" =~ ^(200|302|303)$ ]]; then
        log "認証失敗: 予期しないステータス（HTTP ${status}）"
        return 1
    fi

    log "認証成功（HTTP ${status}）"
    date +%s > "$LAST_LOGIN_FILE"
    return 0
}

wait_online() {
    local i
    echo "疎通確認中..."
    for i in 1 2 3 4 5 6 7 8 9; do
        test_online && return 0
        echo "  待機中... $((i * 10))秒"
        sleep 10
    done
    return 1
}

# ===== メイン =====
if [ "$MODE" = "logout" ]; then
    portal_logout
    rm -f "$LAST_LOGIN_FILE"
    exit 0
fi

online=0
test_online && online=1

# 先回り再ログイン判定（このスクリプトでログインしてから一定時間経過）
due=0
last=""
[ -f "$LAST_LOGIN_FILE" ] && last=$(tr -dc '0-9' < "$LAST_LOGIN_FILE")
now=$(date +%s)
if [ -n "$last" ] && [ "$RELOGIN_HOURS" -gt 0 ] && [ $((now - last)) -ge $((RELOGIN_HOURS * 3600)) ]; then
    due=1
fi

if [ "$online" -eq 1 ] && [ "$due" -eq 0 ] && [ "$MODE" != "relogin" ]; then
    exit 0
fi

# 認証サーバーに届かなければ学内LAN外なので静かに終了
if ! test_portal; then
    echo "認証サーバーに接続できません（学内LAN外）。終了します。"
    exit 0
fi

if [ "$MODE" = "relogin" ]; then
    log "手動指定により再ログインします。"
elif [ "$due" -eq 1 ]; then
    log "前回ログインから ${RELOGIN_HOURS} 時間経過。先回りして再ログインします。"
elif [ -n "$last" ]; then
    elapsed=$((now - last))
    log "オフラインを検知（前回ログインから $((elapsed / 3600))時間$(((elapsed % 3600) / 60))分）。ログアウト→再ログインします。"
else
    log "オフラインを検知。ログアウト→再ログインします。"
fi

# セッションが残ったままだと再ログインできないため、先にログアウトする
portal_logout
sleep 3

if ! portal_login; then
    # ログアウト直後で弾かれた可能性に備えて1回だけリトライ
    sleep 5
    portal_login || exit 1
fi

if wait_online; then
    log "インターネット接続OK"
else
    log "90秒待っても疎通なし。手動で確認してください。"
    exit 1
fi
