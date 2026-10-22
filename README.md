# 学内ネットワーク自動認証スクリプト

サレジオ高専のネットワーク認証ポータル（`http://172.30.0.1/`）に自動ログインするスクリプトです。  
Windows・Mac・Linux に対応しています。

## かんたんセットアップ

**セットアップ用のファイルを1つ実行して、ユーザーID とパスワードを入力するだけで設定が完了します。**

### Windows

1. このリポジトリを好きな場所に置く（`git clone` または ZIP を展開）
2. **`setup.bat` をダブルクリック**
3. 聞かれたら **ユーザーID（学籍番号）** と **パスワード** を入力

### Mac / Linux

1. このリポジトリを好きな場所に置く（`git clone` または ZIP を展開）
2. ターミナルでフォルダに移動して **`./setup.sh` を実行**
3. 聞かれたら **ユーザーID（学籍番号）** と **パスワード** を入力

```bash
cd salesio-lan-auto-auth
./setup.sh
```

> Mac では、`書類`・`デスクトップ`・`ダウンロード` フォルダの中に置くと、macOS のプライバシー保護で自動実行が失敗することがあります。`~/salesio-lan-auto-auth` などホーム直下に置くのがおすすめです。

### セットアップで行われること

- 認証情報ファイル `.env` の作成
- 自動実行の登録（Windows: タスクスケジューラ / Mac: launchd / Linux: systemd ユーザータイマー、なければ cron）
- その場で1回実行して動作確認

以降は何もしなくても、バックグラウンドで自動ログイン・再ログインします（ウィンドウは表示されません）。管理者権限（sudo）は不要です。

| やりたいこと | Windows | Mac / Linux |
|---|---|---|
| パスワードを変えた | `setup.bat` を再実行（「この設定を使いますか？」で `n`） | `./setup.sh` を再実行（同じく `n`） |
| フォルダを移動した・更新した | `setup.bat` を再実行（`Enter` で既存の設定を使用） | `./setup.sh` を再実行（同じく `Enter`） |
| 自動ログインをやめる | `uninstall.bat` をダブルクリック | `./uninstall.sh` |
| ログを見る | `%LOCALAPPDATA%\campus-login\campus-login.log` | [ログ](#ログ) を参照 |

## 機能

- **自動ログイン:** ログイン時・ネットワーク接続時・5分ごとにチェックし、オフラインなら自動でログイン
- **認証切れからの自動復帰:** Wi-Fi はつながったまま認証だけ切れた場合も、5分以内に検知して再ログイン
- **ログアウト → 再ログイン:** セッションが残って再ログインが弾かれるのを防ぐため、先にログアウトする
- **先回り再ログイン:** 前回ログインから一定時間（既定 11 時間）たったら、切れる前にログインし直す
- **バックグラウンド実行:** ウィンドウを出さずに動く
- **ログ出力:** 認証切れまでの経過時間も記録する

## ファイル構成

```
.
├── setup.bat                    # Windows：ワンクリックセットアップ
├── uninstall.bat                # Windows：自動実行の解除
├── setup.sh                     # Mac / Linux：セットアップ（--uninstall で解除）
├── uninstall.sh                 # Mac / Linux：自動実行の解除
├── windows/
│   ├── campus-login.ps1         # 自動ログイン本体
│   ├── check-login-form.ps1     # フォームフィールド確認
│   ├── setup-task.ps1           # セットアップ本体（setup.bat / uninstall.bat から呼ばれる）
│   └── run-hidden.js            # ウィンドウを出さずに起動するランチャー（タスクから使用）
├── mac/                         # Mac / Linux 共通
│   ├── campus-login.sh          # 自動ログイン本体
│   └── check-login-form.sh      # フォームフィールド確認
├── .env.example                 # 設定ファイルのサンプル
└── .env                         # 設定ファイル（setup で自動作成・gitignore 済み）
```

## 設定ファイル `.env`

`setup.bat` / `setup.sh` が自動で作成します。手動で作る場合は `.env.example` をコピーして編集します。

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
| `RELOGIN_HOURS` | — | 先回り再ログインまでの時間（時間単位）。`0` で無効。既定 `11` |

`.env` はリポジトリのルートに置けば、Windows・Mac・Linux どのスクリプトからも読み込まれます。

---

## 仕組み

### 実行タイミング

| タイミング | Windows（タスクスケジューラ） | Mac（launchd） | Linux（systemd） | Linux（cron） |
|---|:---:|:---:|:---:|:---:|
| ログイン時 | ✅ | ✅ | ✅（30秒後） | ✅（起動時） |
| ネットワーク接続・切替時 | ✅（10秒後） | ✅ | — | — |
| 5分ごとの定期チェック | ✅ | ✅ | ✅ | ✅ |

- **Windows:** タスク名 `campus-login`。`wscript.exe` で `run-hidden.js` を起動し、そこから PowerShell を非表示で実行します（`powershell.exe` を直接起動すると、一瞬ウィンドウが表示されるため）。
- **Mac:** `~/Library/LaunchAgents/com.campus.login.plist` に登録されます。
- **Linux:** systemd のユーザーセッションが使えれば `~/.config/systemd/user/campus-login.timer` に、使えなければ crontab に登録されます。systemd の場合、ログアウト中も動かすには `loginctl enable-linger $USER` が必要です。

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

| OS | ログファイル |
|---|---|
| Windows | `%LOCALAPPDATA%\campus-login\campus-login.log` |
| Mac | `~/Library/Logs/campus-login/campus-login.log` |
| Linux | `~/.local/state/campus-login/campus-login.log` |

同じフォルダに、最後にログインした時刻（`last-login.txt` / `last-login`）も保存されます。ログは 1MB を超えると `.old` に退避されます。

```powershell
# Windows
Get-Content "$env:LOCALAPPDATA\campus-login\campus-login.log" -Tail 20
```

```bash
# Mac
tail -n 20 ~/Library/Logs/campus-login/campus-login.log
# Linux
tail -n 20 ~/.local/state/campus-login/campus-login.log
```

オンラインで何もしなかった回はログに残りません。主なメッセージ:

| メッセージ | 意味 |
|---|---|
| `オフラインを検知（前回ログインから ○時間○分）` | 認証切れを検知。**経過時間でセッションの有効時間がわかる** |
| `前回ログインから N 時間経過。先回りして再ログインします。` | `RELOGIN_HOURS` による先回り再ログイン |
| `ログアウト送信: /cgibin/Logout.cgi（HTTP 200）` | ログアウト成功 |
| `認証成功` / `インターネット接続OK` | 再ログイン完了 |
| `認証失敗: ログインページが返されました` | ID・パスワードの誤り、またはフォームの変更 |

> **セッションの有効時間について**  
> 何時間で認証が切れるかは確認できていません（約12時間と想定）。わからなくても、5分ごとのチェックで切れたことを検知して自動で再ログインします。  
> ログの「前回ログインから ○時間○分」で実際の時間がわかったら、`RELOGIN_HOURS` をそれより少し短くすると、通信が止まる時間をほぼなくせます。

### 手動実行

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1            # 通常（オフラインなら再ログイン）
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1 -Relogin   # 状態に関係なくログアウト → 再ログイン
powershell -ExecutionPolicy Bypass -File .\windows\campus-login.ps1 -Logout    # ログアウトのみ
```

```bash
# Mac / Linux
./mac/campus-login.sh             # 通常（オフラインなら再ログイン）
./mac/campus-login.sh --relogin   # 状態に関係なくログアウト → 再ログイン
./mac/campus-login.sh --logout    # ログアウトのみ
```

### 登録確認

```powershell
# Windows：どのフォルダのスクリプトを実行しているか
(Get-ScheduledTask -TaskName "campus-login").Actions | Format-List Execute, Arguments
```

```bash
# Mac
launchctl list | grep com.campus.login
# Linux（systemd）
systemctl --user list-timers campus-login.timer
# Linux（cron）
crontab -l | grep campus-login
```

---

## トラブルシューティング

### うまく動かないとき

- `認証失敗` がログに出る → セットアップを再実行して ID・パスワードを入れ直す
- ログに何も出ない → オンラインのままなら正常です。登録されているかは [登録確認](#登録確認) のコマンドで確認する
- フォルダを移動した → セットアップを再実行する（自動実行は登録時のパスを指しているため）
- `setup.bat` の画面がすぐ閉じる・文字化けする → PowerShell から `powershell -ExecutionPolicy Bypass -File .\windows\setup-task.ps1` を直接実行する
- `./setup.sh` で `Permission denied` → `bash setup.sh` で実行する
- Mac で自動実行だけ動かない → フォルダを `書類`・`デスクトップ`・`ダウンロード` の外に移動してセットアップを再実行する。`~/Library/Logs/campus-login/launchd.log` にエラーが出ていないかも確認する

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
# Mac / Linux
./mac/check-login-form.sh
```

## 注意事項

- `.env` ファイルは絶対にコミットしないでください（`.gitignore` で除外済み。Mac / Linux では権限 600 で作成）
- このスクリプトはサレジオ高専の学内LANに接続しているときだけ動作します
- ログイン情報の取り扱いは各自の責任で行ってください
