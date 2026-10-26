#!/usr/bin/env bash
set -u

: "${PORT:=10000}"
export SERVER_PORT="${PORT}"
export ENABLE_AUTOPAUSE="false"
export ENABLE_AUTOSTOP="false"

# スクリプトに実行権限をつける
chmod +x scripts/*.sh 2>/dev/null || true

# --- 1. 起動時にSupabaseからデータを自動復元 ---
echo "[Restore] 前回のセーブデータを復元中..."
./scripts/supabase-restore.sh || true

# --- 2. サーバー停止時の自動バックアップ ---
cleanup() {
    echo "[AutoSave] サーバー停止を検知。最後のバックアップを実行中..."
    ./scripts/supabase-backup.sh || true
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# --- 3. マイクラサーバーを起動 ---
/image/scripts/start "$@" &
SERVER_PID=$!

# --- 4. 【完全自動】プレイヤー退出 & !save チャットを監視 ---
(
    sleep 15
    touch logs/latest.log 2>/dev/null || true
    tail -n 0 -F logs/latest.log 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q -E "(lost connection|left the game|!save|/world save)"; then
            echo "[AutoSave] 退出またはセーブ指示を検知しました。"
            ./scripts/supabase-backup.sh || true
        fi
    done
) &

# --- 5. 【完全自動】5分ごとの定期自動セーブ ---
(
    while true; do
        sleep 300
        ./scripts/supabase-backup.sh || true
    done
) &

# サーバーの終了を待つ
wait "$SERVER_PID"
