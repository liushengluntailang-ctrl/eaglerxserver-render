#!/usr/bin/env bash
set -u

# --- マイクラ本体の設定（Paper 1.12.2 を自動指定） ---
: "${PORT:=10000}"
export SERVER_PORT="${PORT}"
export TYPE="PAPER"
export VERSION="1.12.2"
export PAPER_BUILD="1620"
export MEMORY="224M"
export INIT_MEMORY="96M"
export MAX_MEMORY="224M"
export USE_AIKAR_FLAGS="false"
export EULA="TRUE"
export ENABLE_AUTOPAUSE="false"
export ENABLE_AUTOSTOP="false"

# マイクラのデータフォルダに移動
cd /data 2>/dev/null || true

# --- 【関数】Supabaseからデータを自動復元 ---
restore_world() {
    if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_KEY:-}" ] || [ -z "${SUPABASE_BUCKET:-}" ]; then
        echo "[Restore] Supabase環境変数が見つかりません。新規ワールドで起動します。"
        return
    fi
    echo "[Restore] Supabaseから前回のセーブデータを復元中..."
    BACKUP_FILE="/tmp/world-latest.tar.gz"
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$BACKUP_FILE" -X GET \
      "${SUPABASE_URL}/storage/v1/object/authenticated/${SUPABASE_BUCKET}/world-latest.tar.gz" \
      -H "Authorization: Bearer ${SUPABASE_KEY}" \
      -H "apikey: ${SUPABASE_KEY}")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "[Restore] セーブデータを発見！復元しています..."
        tar -xzf "$BACKUP_FILE" -C /data
        rm -f "$BACKUP_FILE"
        echo "[Restore] 復元が完了しました！"
    else
        echo "[Restore] 前回のセーブデータはありません (HTTP $HTTP_STATUS)。新しいワールドで開始します。"
        rm -f "$BACKUP_FILE"
    fi
}

# --- 【関数】Supabaseへデータを保存 ---
backup_world() {
    if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_KEY:-}" ] || [ -z "${SUPABASE_BUCKET:-}" ]; then
        return
    fi
    echo "[AutoSave] Supabaseへセーブデータを保存中..."
    BACKUP_FILE="/tmp/world-latest.tar.gz"
    tar -czf "$BACKUP_FILE" -C /data world world_nether world_the_end 2>/dev/null || true

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "${SUPABASE_URL}/storage/v1/object/${SUPABASE_BUCKET}/world-latest.tar.gz" \
      -H "Authorization: Bearer ${SUPABASE_KEY}" \
      -H "apikey: ${SUPABASE_KEY}" \
      -H "x-upsert: true" \
      -H "Content-Type: application/gzip" \
      --data-binary @"$BACKUP_FILE")

    HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
    if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ]; then
        echo "[AutoSave] クラウド保存に成功しました！"
    else
        echo "[AutoSave] 保存に失敗しました (Status: $HTTP_STATUS)"
    fi
    rm -f "$BACKUP_FILE"
}

# 1. 起動時に前回のワールドを復元
restore_world

# 2. サーバー停止時の自動バックアップ
cleanup() {
    echo "[AutoSave] 停止シグナル検知。最後のバックアップ中..."
    backup_world
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# 3. マイクラサーバー起動
/image/scripts/start "$@" &
SERVER_PID=$!

# 4. 退出検知 & !save 監視
(
    sleep 20
    touch /data/logs/latest.log 2>/dev/null || true
    tail -n 0 -F /data/logs/latest.log 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q -E "(lost connection|left the game|!save|/world save)"; then
            backup_world
        fi
    done
) &

# 5. 5分ごとの定期保存
(
    while true; do
        sleep 300
        backup_world
    done
) &

wait "$SERVER_PID"
