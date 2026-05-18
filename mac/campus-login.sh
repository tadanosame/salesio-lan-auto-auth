#!/usr/bin/env bash
# 学内ネットワーク自動認証スクリプト（Mac / Linux 用）
# 初回: check-login-form.sh を実行してフィールド名を確認し、下記を修正してください

LOGIN_URL="${LOGIN_URL:-http://172.30.0.1/EWA/index.html}"

# フィールド名（check-login-form.sh の出力に合わせて変更してください）
USER_FIELD="user"
PASS_FIELD="pass"

# .env ファイルから認証情報を読み込む（スクリプトと同階層 → 親ディレクトリの順で探す）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$SCRIPT_DIR/../.env"
if [ -f "$ENV_FILE" ]; then
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        export "${key// /}=${val}"
    done < "$ENV_FILE"
fi

# セッション用 Cookie ファイル（一時）
COOKIE_FILE=$(mktemp /tmp/campus_cookie.XXXXXX)
trap 'rm -f "$COOKIE_FILE"' EXIT

# ページ取得（Cookie・hidden フィールド収集）
HTML=$(curl -s --max-time 10 -c "$COOKIE_FILE" "$LOGIN_URL")
if [ $? -ne 0 ] || [ -z "$HTML" ]; then
    echo "エラー: サーバーに接続できませんでした" >&2
    exit 1
fi

# フォームの Action URL を解決
ACTION=$(echo "$HTML" | grep -oi '<form[^>]*>' | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"//')
if [ -z "$ACTION" ]; then
    POST_URL="$LOGIN_URL"
elif [[ "$ACTION" == http* ]]; then
    POST_URL="$ACTION"
else
    # 相対パス → 絶対パスに変換
    BASE=$(echo "$LOGIN_URL" | grep -oi 'https\?://[^/]*')
    POST_URL="${BASE}${ACTION}"
fi

# hidden フィールドのみ body に追加（user/pass の空値重複を防ぐ）
BODY_ARGS=()
while IFS= read -r tag; do
    type=$(echo "$tag"  | grep -oi 'type="[^"]*"'  | sed 's/type="//;s/"//')
    name=$(echo "$tag"  | grep -oi 'name="[^"]*"'  | sed 's/name="//;s/"//')
    value=$(echo "$tag" | grep -oi 'value="[^"]*"' | sed 's/value="//;s/"//')
    if [ -n "$name" ] && [[ "$(echo "$type" | tr '[:upper:]' '[:lower:]')" == "hidden" ]]; then
        BODY_ARGS+=("--data-urlencode" "${name}=${value}")
    fi
done < <(echo "$HTML" | grep -oi '<input[^>]*>')

# 認証情報をセット
BODY_ARGS+=("--data-urlencode" "${USER_FIELD}=${STUDENT_ID}")
BODY_ARGS+=("--data-urlencode" "${PASS_FIELD}=${PASSWORD}")

# POST 送信（リダイレクト追跡、レスポンスボディも取得）
RESPONSE_FILE=$(mktemp /tmp/campus_response.XXXXXX)
STATUS=$(curl -s -L --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -o "$RESPONSE_FILE" -w "%{http_code}" \
    "${BODY_ARGS[@]}" "$POST_URL")

# レスポンスボディで認証失敗を検出（ログインフォームが返ってきた場合）
if grep -qi 'action=.*loginprocess\|type="password"' "$RESPONSE_FILE" 2>/dev/null; then
    echo "認証失敗: ユーザーIDまたはパスワードが違います（HTTP ${STATUS}）" >&2
    rm -f "$RESPONSE_FILE"
    exit 1
fi
rm -f "$RESPONSE_FILE"

if [[ "$STATUS" =~ ^(200|302|303)$ ]]; then
    echo "認証成功（HTTP ${STATUS}）"

    # インターネット疎通確認（最大90秒リトライ）
    echo "疎通確認中..."
    connected=0
    for i in $(seq 1 9); do
        if ping -c 1 -t 3 8.8.8.8 &>/dev/null; then
            connected=1
            break
        fi
        echo "  待機中... $((i * 10))秒"
        sleep 10
    done
    if [ $connected -eq 1 ]; then
        echo "インターネット接続OK"
    else
        echo "90秒待っても疎通なし。手動で確認してください。"
    fi
else
    echo "予期しないステータス: $STATUS" >&2
    exit 1
fi
