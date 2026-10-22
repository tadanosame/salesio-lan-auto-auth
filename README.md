# 学内ネットワーク自動認証スクリプト

サレジオ高専のネットワーク認証ポータルに自動ログインするスクリプトです。  
Mac / Linux（bash）と Windows（PowerShell）に対応しています。

## ファイル構成

```
.
├── mac/
│   ├── campus-login.sh          # 自動ログイン
│   ├── check-login-form.sh      # フォームフィールド確認
│   └── com.campus.login.plist   # 自動実行用 LaunchAgent サンプル
├── windows/
│   ├── campus-login.ps1         # 自動ログイン
│   ├── check-login-form.ps1     # フォームフィールド確認
│   ├── run-hidden.js            # ウィンドウを出さずに起動するランチャー
│   └── setup-task.ps1           # タスクスケジューラ登録スクリプト
├── .env.example                 # 認証情報のサンプル
└── .env                         # 認証情報（非公開・gitignore済み）
```

## セットアップ

**1. 認証情報ファイルを作成する**

```bash
cp .env.example .env
```

`.env` を開いて自分の学籍番号とパスワードを記入します。

```
STUDENT_ID=your_student_id
PASSWORD=your_password
```

`.env` はルートに置けば Mac・Windows どちらのスクリプトからも読み込まれます。

**2. 実行権限を付与する（Mac のみ）**

```bash
chmod +x mac/campus-login.sh mac/check-login-form.sh
```

## 使い方

### 手動ログイン

```bash
# Mac
./mac/campus-login.sh

# Windows（PowerShell）
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1
```

認証成功後、インターネット疎通を最大90秒確認します。

### フォームフィールドの確認（初回・トラブル時）

認証サーバーのフォーム構造を確認したいときに使います。

```bash
# Mac
./mac/check-login-form.sh

# Windows（PowerShell）
powershell -ExecutionPolicy Bypass -File .\windows\check-login-form.ps1
```

---

## 自動実行の設定

### Mac：ネットワーク接続時に自動ログイン（launchd）

ネットワーク設定が切り替わるタイミング（キャンパスWi-Fi接続時など）を検知して自動実行します。

**1. plist ファイルを編集する**

`mac/com.campus.login.plist` を開き、スクリプトの絶対パスを書き換えます。

```xml
<string>/Users/YOUR_USERNAME/path/to/mac/campus-login.sh</string>
```

**2. LaunchAgents にコピーして登録する**

```bash
cp mac/com.campus.login.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.campus.login.plist
```

**3. 動作確認**

```bash
# ログを確認
tail -f /tmp/campus-login.log
```

**解除する場合**

```bash
launchctl unload ~/Library/LaunchAgents/com.campus.login.plist
rm ~/Library/LaunchAgents/com.campus.login.plist
```

---

### Windows：ログオン時・ネットワーク再接続時に自動ログイン（タスクスケジューラ）

以下の2つのタイミングで自動認証が実行されます。

| トリガー | タイミング |
|---|---|
| ログオン時 | Windows にサインインしたとき |
| ネットワーク接続時 | Wi-Fi が切れて再接続したとき（10秒後） |
| 定期チェック（5分ごと） | Wi-Fi はつながったまま認証セッションだけ切れたとき |

定期チェックでは、まず `http://www.msftconnecttest.com/connecttest.txt` に HTTP でアクセスして、インターネットに出られるかを判定します。出られる場合は何もせず終了します。学内LAN外（認証サーバーに届かない）の場合も何もしません。

オフラインを検知したときは、**ログアウト → 再ログイン**の順で実行します（セッションが残ったままだと再ログインできないため）。

また、このスクリプトでログインしてから **11時間** たつと、通信が切れる前に先回りしてログアウト→再ログインします（約12時間でセッションが切れるため）。時間は `.env` の `RELOGIN_HOURS` で変えられます（`0` で無効）。

実行ログは `%LOCALAPPDATA%\campus-login\campus-login.log` に出力されます。

タスクは `windows/run-hidden.js` を `wscript.exe` で起動し、そこから PowerShell を非表示で実行します（`powershell.exe` を直接起動すると、実行のたびに一瞬ウィンドウが表示されるため）。

手動で実行する場合:

```powershell
# 状態に関係なくログアウト→再ログイン
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1 -Relogin
# ログアウトのみ
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1 -Logout
```

> 既にタスクを登録済みの場合も、`setup-task.ps1` を再実行すると定期チェック付きで上書き登録されます。

**PowerShell から登録する（管理者権限不要）**

`windows/setup-task.ps1` を PowerShell から実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup-task.ps1
```

**登録確認**

```powershell
schtasks /Query /TN "campus-login" /FO LIST
```

**解除する場合**

```powershell
Unregister-ScheduledTask -TaskName "campus-login" -Confirm:$false
```

## 注意事項

- `.env` ファイルは絶対にコミットしないでください（`.gitignore` で除外済み）
- このスクリプトはサレジオ高専の学内LANへの接続時のみ動作します
- ログイン情報の取り扱いは各自の責任で行ってください
