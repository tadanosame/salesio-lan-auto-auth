# 学内ネットワーク自動認証スクリプト

サレジオ高専のネットワーク認証ポータル（`http://172.30.0.1/`）に自動ログインするスクリプトです。  
Windows（PowerShell）と Mac / Linux（bash）に対応しています。

## かんたんセットアップ（Windows）

**`setup.bat` をダブルクリックするだけで設定が完了します。**

1. このリポジトリを好きな場所に置く（`git clone` または ZIP を展開）
2. `setup.bat` をダブルクリック
3. 聞かれたら **ユーザーID（学籍番号）** と **パスワード** を入力

これだけで、以下がすべて自動で行われます。

- 認証情報ファイル `.env` の作成
- 自動実行タスクの登録（ログオン時・Wi-Fi 再接続時・5分ごと）
- その場で1回実行して動作確認

以降は何もしなくても、バックグラウンドで自動ログイン・再ログインします（ウィンドウは表示されません）。

| やりたいこと | 方法 |
|---|---|
| パスワードを変えた | `setup.bat` をもう一度実行（「この設定を使いますか？」で `n`） |
| フォルダを移動した・スクリプトを更新した | `setup.bat` をもう一度実行（`Enter` で既存の設定を使用） |
| 自動ログインをやめる | `uninstall.bat` をダブルクリック |
| ログを見る | `%LOCALAPPDATA%\campus-login\campus-login.log` |

> 管理者権限は不要です。Mac の場合は [Mac：自動実行の設定](#mac自動実行の設定) を参照してください。

## 機能

| 機能 | Windows | Mac / Linux |
|---|:---:|:---:|
| 自動ログイン（ログオン時・ネットワーク接続時） | ✅ | ✅ |
| 認証切れの定期チェック（5分ごと）→ 自動で再ログイン | ✅ | — |
| 再ログイン前のログアウト（セッションが残って弾かれるのを防ぐ） | ✅ | — |
| 一定時間ごとの先回り再ログイン（既定 11 時間） | ✅ | — |
| ウィンドウを出さずにバックグラウンド実行 | ✅ | ✅ |
| ログファイル出力 | ✅ | ✅ |

## ファイル構成

```
.
├── setup.bat                    # Windows：ワンクリックセットアップ
├── uninstall.bat                # Windows：自動実行の解除
├── windows/
│   ├── campus-login.ps1         # 自動ログイン本体
│   ├── check-login-form.ps1     # フォームフィールド確認
│   ├── setup-task.ps1           # セットアップ本体（setup.bat / uninstall.bat から呼ばれる）
│   └── run-hidden.js            # ウィンドウを出さずに起動するランチャー（タスクから使用）
├── mac/
│   ├── campus-login.sh          # 自動ログイン
│   ├── check-login-form.sh      # フォームフィールド確認
│   └── com.campus.login.plist   # 自動実行用 LaunchAgent サンプル
├── .env.example                 # 設定ファイルのサンプル
└── .env                         # 設定ファイル（非公開・gitignore 済み）
```

## 設定ファイル `.env`

Windows では `setup.bat` が自動で作成します。手動で作る場合（Mac など）は `.env.example` をコピーして編集します。

```bash
cp .env.example .env
```

```
STUDENT_ID=your_student_id
PASSWORD=your_password
# 前回ログインから何時間で先回り再ログインするか（0 で無効、既定 11）
RELOGIN_HOURS=11
```

| キー | 必須 | 説明 |
|---|:---:|---|
| `STUDENT_ID` | ✅ | ユーザーID（学籍番号） |
| `PASSWORD` | ✅ | パスワード |
| `RELOGIN_HOURS` | — | 先回り再ログインまでの時間（時間単位）。`0` で無効。既定 `11`。Windows のみ |

`.env` はリポジトリのルートに置けば、Windows・Mac どちらのスクリプトからも読み込まれます。

---

## Windows：自動実行の詳細

通常は [かんたんセットアップ](#かんたんセットアップwindows) の `setup.bat` だけで十分です。ここでは仕組みを説明します。

### 登録・解除（コマンドで行う場合）

```powershell
# セットアップ（setup.bat と同じ）
powershell -ExecutionPolicy Bypass -File .\windows\setup-task.ps1
# 解除（uninstall.bat と同じ）
powershell -ExecutionPolicy Bypass -File .\windows\setup-task.ps1 -Uninstall
```

タスク名 `campus-login` でタスクスケジューラに登録されます（再実行すると上書き）。

### 実行タイミング

| トリガー | タイミング |
|---|---|
| ログオン時 | Windows にサインインしたとき |
| ネットワーク接続時 | Wi-Fi が切れて再接続したとき（10秒後） |
| 定期チェック | 5分ごと（Wi-Fi はつながったまま認証だけ切れた場合に対応） |

タスクは `wscript.exe` で `run-hidden.js` を起動し、そこから PowerShell を非表示で実行します。  
（`powershell.exe` を直接起動すると、実行のたびに一瞬ウィンドウが表示されるため）

### 動作の流れ

```
起動
 ├─ インターネットに出られる？（msftconnecttest.com に HTTP で確認）
 │    ├─ はい ─┬─ 前回ログインから RELOGIN_HOURS 経過していない → 何もせず終了
 │    │        └─ 経過している → 先回り再ログインへ
 │    └─ いいえ → 再ログインへ
 ├─ 認証サーバー（172.30.0.1）に届く？
 │    └─ いいえ → 学内LAN外なので何もせず終了
 └─ 再ログイン
      1. ログアウト（セッションが残っていると再ログインできないため）
      2. ログイン（失敗したら 5 秒後に 1 回だけリトライ）
      3. インターネット疎通を最大 90 秒確認
```

- 疎通確認は ping ではなく HTTP で行います（認証が切れていても ping は通ることがあるため）。
- 先回り再ログインの経過時間は、**このスクリプトでログインした時刻**から数えます。ブラウザで手動ログインした分は含まれません。

### ログ

| ファイル | 内容 |
|---|---|
| `%LOCALAPPDATA%\campus-login\campus-login.log` | 実行ログ（1MB を超えると `.old` に退避） |
| `%LOCALAPPDATA%\campus-login\last-login.txt` | 最後にログインした時刻 |

オンラインで何もしなかった回はログに残りません。主なメッセージ:

| メッセージ | 意味 |
|---|---|
| `オフラインを検知（前回ログインから ○時間○分）` | 認証切れを検知。**経過時間でセッションの有効時間がわかる** |
| `前回ログインから N 時間経過。先回りして再ログインします。` | `RELOGIN_HOURS` による先回り再ログイン |
| `ログアウト送信: /cgibin/Logout.cgi（HTTP 200）` | ログアウト成功 |
| `認証成功` / `インターネット接続OK` | 再ログイン完了 |
| `認証失敗: ログインページが返されました` | ID・パスワードの誤り、またはフォームの変更 |

```powershell
# ログを確認
Get-Content "$env:LOCALAPPDATA\campus-login\campus-login.log" -Tail 20
```

> **セッションの有効時間について**  
> 何時間で認証が切れるかは確認できていません（約12時間と想定）。わからなくても、5分ごとのチェックで切れたことを検知して自動で再ログインします。  
> ログの「前回ログインから ○時間○分」で実際の時間がわかったら、`RELOGIN_HOURS` をそれより少し短くすると、通信が止まる時間をほぼなくせます。

### 手動実行

```powershell
# 通常（オフラインなら再ログイン）
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1
# 状態に関係なくログアウト → 再ログイン
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1 -Relogin
# ログアウトのみ
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1 -Logout
```

### 登録確認

```powershell
# 登録内容の確認
schtasks /Query /TN "campus-login" /FO LIST
# どのフォルダのスクリプトを実行しているか確認
(Get-ScheduledTask -TaskName "campus-login").Actions | Format-List Execute, Arguments
```

---

## Mac：自動実行の設定

ネットワーク設定が切り替わるタイミング（キャンパス Wi-Fi 接続時など）とログイン時に自動実行します。  
※ Windows 版にある「5分ごとの定期チェック」「ログアウト → 再ログイン」「先回り再ログイン」は未対応です。

**1. 実行権限を付与する**

```bash
chmod +x mac/campus-login.sh mac/check-login-form.sh
```

**2. plist ファイルを編集する**

`mac/com.campus.login.plist` を開き、スクリプトの絶対パスを書き換えます。

```xml
<string>/Users/YOUR_USERNAME/path/to/mac/campus-login.sh</string>
```

**3. LaunchAgents にコピーして登録する**

```bash
cp mac/com.campus.login.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.campus.login.plist
```

**4. 動作確認**

```bash
tail -f /tmp/campus-login.log
```

**手動実行**

```bash
./mac/campus-login.sh
```

**解除する場合**

```bash
launchctl unload ~/Library/LaunchAgents/com.campus.login.plist
rm ~/Library/LaunchAgents/com.campus.login.plist
```

---

## トラブルシューティング

### 認証ポータルの仕様

| 項目 | 値 |
|---|---|
| ログインページ | `http://172.30.0.1/login.html` |
| ログイン | `POST /cgi-bin/Login.cgi`（フィールド `uid` / `pwd`） |
| ログアウト | `POST /cgibin/Logout.cgi` |
| ログイン成功時の表示 | 「ログインに成功しました」 |

- ログアウト先はポータルの HTML 上で `cgibin`（ハイフンなし）と書かれています。表記揺れに備えて `/cgi-bin/Logout.cgi` も試すようにしています。

### フォームが変わったとき

認証サーバーのフォーム構造を確認し、スクリプト冒頭のフィールド名（`uid` / `pwd`）や URL を修正します。

```bash
# Windows（PowerShell）
powershell -ExecutionPolicy Bypass -File .\windows\check-login-form.ps1
# Mac
./mac/check-login-form.sh
```

### うまく動かないとき

- `認証失敗` がログに出る → `setup.bat` を再実行して ID・パスワードを入れ直す
- ログに何も出ない → オンラインのままなら正常です。タスクが登録されているかは「登録確認」のコマンドで確認する
- フォルダを移動した → `setup.bat` を再実行する（タスクは登録時のパスを指しているため）
- `setup.bat` の画面がすぐ閉じる・文字化けする → PowerShell から `powershell -ExecutionPolicy Bypass -File .\windows\setup-task.ps1` を直接実行する

## 注意事項

- `.env` ファイルは絶対にコミットしないでください（`.gitignore` で除外済み）
- このスクリプトはサレジオ高専の学内LANに接続しているときだけ動作します
- ログイン情報の取り扱いは各自の責任で行ってください
