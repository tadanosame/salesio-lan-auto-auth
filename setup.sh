#!/usr/bin/env bash
# 学内ネットワーク自動認証 セットアップスクリプト（Mac / Linux）
#
# これ1つ実行するだけで設定が完了します:
#   1. ユーザーID・パスワードを入力して .env を作成
#   2. 自動実行を登録（Mac: launchd / Linux: systemd ユーザータイマー、なければ cron）
#   3. その場で1回実行して動作確認
#
# 使い方:
#   ./setup.sh               セットアップ
#   ./setup.sh --uninstall   自動実行の解除（./uninstall.sh と同じ）
#
# ※ macOS 標準の bash 3.2 でも動くように書いています

set -u

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$ROOT_DIR/mac/campus-login.sh"
ENV_FILE="$ROOT_DIR/.env"
LABEL="com.campus.login"
INTERVAL_MIN=5
OS="$(uname -s)"

PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CRON_MARK="# campus-login (salesio-lan-auto-auth)"

if [ "$OS" = "Darwin" ]; then
    LOG_DIR="$HOME/Library/Logs/campus-login"
else
    LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/campus-login"
fi

step() { echo ""; echo "■ $*"; }
ok()   { echo "  $*"; }

has_systemd_user() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

# ===== 解除 =====
uninstall() {
    step "自動実行を解除します"
    local removed=0
    if [ "$OS" = "Darwin" ]; then
        if [ -f "$PLIST_PATH" ]; then
            launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null
            rm -f "$PLIST_PATH"
            ok "launchd エージェント（$LABEL）を削除しました。"
            removed=1
        fi
    else
        if [ -f "$SYSTEMD_DIR/campus-login.timer" ] || [ -f "$SYSTEMD_DIR/campus-login.service" ]; then
            if has_systemd_user; then
                systemctl --user disable --now campus-login.timer 2>/dev/null
            fi
            rm -f "$SYSTEMD_DIR/campus-login.timer" "$SYSTEMD_DIR/campus-login.service"
            has_systemd_user && systemctl --user daemon-reload 2>/dev/null
            ok "systemd ユーザータイマー（campus-login.timer）を削除しました。"
            removed=1
        fi
        if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -qF "$CRON_MARK"; then
            crontab -l 2>/dev/null | grep -vF "$CRON_MARK" | crontab -
            ok "cron の登録を削除しました。"
            removed=1
        fi
    fi
    [ "$removed" -eq 1 ] || ok "自動実行は登録されていません。"
    ok "（.env とログ $LOG_DIR は残しています。不要なら手動で削除してください）"
}

if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
    uninstall
    exit 0
fi

if [ "$OS" != "Darwin" ] && [ "$OS" != "Linux" ]; then
    echo "未対応の OS です: $OS（Windows は setup.bat を使ってください）" >&2
    exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "curl が見つかりません。インストールしてから再実行してください。" >&2
    exit 1
fi

echo "========================================"
echo " 学内ネットワーク自動認証 セットアップ"
echo "========================================"

# ===== 1. 認証情報（.env） =====
step "1/3 ユーザーID・パスワードの設定"

get_env() {
    [ -f "$ENV_FILE" ] || return 0
    grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -1 | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

cur_id="$(get_env STUDENT_ID)"
cur_pw="$(get_env PASSWORD)"
cur_hours="$(get_env RELOGIN_HOURS)"

use_existing=0
if [ -n "$cur_id" ] && [ -n "$cur_pw" ] && [ "$cur_id" != "your_student_id" ]; then
    ok "既存の設定があります（ユーザーID: $cur_id）"
    printf "  この設定を使いますか？ [Y/n] "
    read -r ans
    case "$ans" in ""|[Yy]*) use_existing=1 ;; esac
fi

if [ "$use_existing" -eq 0 ]; then
    student_id=""
    while [ -z "$student_id" ]; do
        printf "  ユーザーID（学籍番号）: "
        read -r student_id
    done
    password=""
    while [ -z "$password" ]; do
        printf "  パスワード（入力は表示されません）: "
        read -r -s password
        echo ""
    done
    hours="${cur_hours:-11}"
    umask 077
    {
        echo "STUDENT_ID=$student_id"
        echo "PASSWORD=$password"
        echo "# 前回ログインから何時間で先回り再ログインするか（0 で無効、既定 11）"
        echo "RELOGIN_HOURS=$hours"
    } > "$ENV_FILE"
    umask 022
    ok "保存しました: $ENV_FILE"
fi
chmod 600 "$ENV_FILE"
chmod +x "$SCRIPT_PATH" "$ROOT_DIR/mac/check-login-form.sh" 2>/dev/null

# ===== 2. 自動実行の登録 =====
step "2/3 自動実行の登録"
mkdir -p "$LOG_DIR"

xml_escape() { echo "$1" | sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g'; }

if [ "$OS" = "Darwin" ]; then
    # macOS のプライバシー保護により、launchd から書類・デスクトップ・ダウンロード内のスクリプトは実行できないことがある
    case "$ROOT_DIR" in
        "$HOME/Documents"*|"$HOME/Desktop"*|"$HOME/Downloads"*)
            echo "  ⚠ このフォルダ（$ROOT_DIR）は macOS の保護対象のため、自動実行が失敗することがあります。"
            echo "    うまく動かない場合は ~/campus-login などに移動して、もう一度 ./setup.sh を実行してください。"
            ;;
    esac

    mkdir -p "$(dirname "$PLIST_PATH")"
    script_xml="$(xml_escape "$SCRIPT_PATH")"
    log_xml="$(xml_escape "$LOG_DIR/launchd.log")"
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$script_xml</string>
    </array>
    <!-- ログイン時に実行 -->
    <key>RunAtLoad</key>
    <true/>
    <!-- ${INTERVAL_MIN} 分ごとに認証切れをチェック -->
    <key>StartInterval</key>
    <integer>$((INTERVAL_MIN * 60))</integer>
    <!-- ネットワーク切替時（DNS 設定の変化）に実行 -->
    <key>WatchPaths</key>
    <array>
        <string>/etc/resolv.conf</string>
    </array>
    <key>StandardOutPath</key>
    <string>$log_xml</string>
    <key>StandardErrorPath</key>
    <string>$log_xml</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl unload "$PLIST_PATH" 2>/dev/null
    if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || launchctl load -w "$PLIST_PATH" 2>/dev/null; then
        ok "launchd に登録しました（$PLIST_PATH）"
    else
        echo "  launchd への登録に失敗しました。" >&2
        exit 1
    fi
    ok "  - ログイン時に自動認証"
    ok "  - ネットワーク切替時に自動認証"
    ok "  - ${INTERVAL_MIN} 分ごとに認証切れをチェックして再認証"

elif has_systemd_user; then
    mkdir -p "$SYSTEMD_DIR"
    cat > "$SYSTEMD_DIR/campus-login.service" <<EOF
[Unit]
Description=Salesio campus LAN auto login
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash "$SCRIPT_PATH"
TimeoutStartSec=5min
EOF
    cat > "$SYSTEMD_DIR/campus-login.timer" <<EOF
[Unit]
Description=Salesio campus LAN auto login (every ${INTERVAL_MIN} min)

[Timer]
OnStartupSec=30s
OnUnitActiveSec=${INTERVAL_MIN}min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now campus-login.timer >/dev/null 2>&1 || {
        echo "  systemd タイマーの有効化に失敗しました。" >&2
        exit 1
    }
    ok "systemd ユーザータイマーに登録しました（campus-login.timer）"
    ok "  - ログイン後 30 秒で自動認証"
    ok "  - ${INTERVAL_MIN} 分ごとに認証切れをチェックして再認証"
    ok "  ※ ログアウト中も動かしたい場合: loginctl enable-linger ${USER:-$(id -un)}"

elif command -v crontab >/dev/null 2>&1; then
    {
        crontab -l 2>/dev/null | grep -vF "$CRON_MARK"
        echo "*/${INTERVAL_MIN} * * * * /bin/bash \"$SCRIPT_PATH\" >/dev/null 2>&1 $CRON_MARK"
        echo "@reboot sleep 30 && /bin/bash \"$SCRIPT_PATH\" >/dev/null 2>&1 $CRON_MARK"
    } | crontab -
    ok "cron に登録しました（systemd ユーザーセッションが使えないため）"
    ok "  - 起動時に自動認証"
    ok "  - ${INTERVAL_MIN} 分ごとに認証切れをチェックして再認証"

else
    echo "  systemd も cron も見つからないため、自動実行を登録できませんでした。" >&2
    echo "  手動で $SCRIPT_PATH を定期実行するよう設定してください。" >&2
    exit 1
fi

# ===== 3. 動作確認 =====
step "3/3 動作確認"
if /bin/bash "$SCRIPT_PATH"; then
    ok "OK（接続済み、またはログイン成功。学内LAN外では何もしません）"
else
    echo "  ログインに失敗しました。ユーザーID・パスワードを確認して、もう一度 ./setup.sh を実行してください。"
fi

echo ""
echo "========================================"
echo " セットアップ完了"
echo "========================================"
echo "  以降は何もしなくても、バックグラウンドで自動ログインします。"
echo "  ログ:   $LOG_DIR/campus-login.log"
echo "  解除:   ./uninstall.sh"
echo "  ※ フォルダを移動したら、もう一度 ./setup.sh を実行してください。"
