#!/usr/bin/env bash
# 学内ネットワーク自動認証: 自動実行の解除（Mac / Linux）
exec /bin/bash "$(cd "$(dirname "$0")" && pwd)/setup.sh" --uninstall
