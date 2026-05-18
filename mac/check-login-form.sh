#!/usr/bin/env bash
# 学内ネットワーク認証フォームのフィールド名確認スクリプト（Mac / Linux 用）

URL="http://172.30.0.1/EWA/index.html"

echo "=== Form Info ==="

HTML=$(curl -s --max-time 10 "$URL")
if [ $? -ne 0 ] || [ -z "$HTML" ]; then
    echo "Error: サーバーに接続できませんでした"
    exit 1
fi

# <form> タグの action / method を抽出
ACTION=$(echo "$HTML" | grep -oi '<form[^>]*>' | grep -oi 'action="[^"]*"' | head -1 | sed 's/action="//;s/"//')
METHOD=$(echo "$HTML" | grep -oi '<form[^>]*>' | grep -oi 'method="[^"]*"' | head -1 | sed 's/method="//;s/"//')

echo ""
echo "[Form 0]"
echo "  Action : ${ACTION:-(なし)}"
echo "  Method : ${METHOD:-(なし)}"
echo "  Fields :"

# <input> タグの name / value を抽出して表示
echo "$HTML" | grep -oi '<input[^>]*>' | while read -r tag; do
    name=$(echo "$tag"  | grep -oi 'name="[^"]*"'  | sed 's/name="//;s/"//')
    value=$(echo "$tag" | grep -oi 'value="[^"]*"' | sed 's/value="//;s/"//')
    [ -n "$name" ] && echo "    '$name' = '$value'"
done
