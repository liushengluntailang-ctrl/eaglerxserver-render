#!/usr/bin/env bash
set -u

: "${PORT:=10000}"
export SERVER_PORT="${PORT}"
export ENABLE_AUTOPAUSE="false"
export ENABLE_AUTOSTOP="false"

# 作業場所をマイクラのデータフォルダに移動
cd /data || true

# --- 【関数】金庫(Supabase)からデータを復元 ---
restore_world() {
    if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_KEY:-}" ] || [ -z "${SUPABASE_BUCKET:-}" ]; then
        echo "[Restore] Supabaseの環境変数が設定されていません。スキップします。"
        return
    fi
    echo "[Restore] Supabaseから前回のセーブデータをダウンロード中..."
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
        echo "[Restore] 前回のセーブデータはありません (Status: $HTTP_STATUS)。新しいワールドで開始します。"
        rm -f "$BACKUP_FILE"
    fi
}

# --- 【関数】金庫(Supabase)へデータを保存 ---
backup_world() {
    if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_KEY:-}" ] || [ -z "${SUPABASE_BUCKET:-}" ]; then
        return
    fi
    echo "[AutoSave] Supabaseへワールドデータを保存中..."
    BACKUP_FILE="/tmp/world-latest.tar.gz"
    
    # データを圧縮（ワールドとログイン情報）
    tar -czf "$BACKUP_FILE" -C /data world world_nether world_the_end 2>/dev/null || true

    # Supabaseへアップロード
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
        echo "[AutoSave] クラウド保存に失敗しました (Status: $HTTP_STATUS)"
    fi
    rm -f "$BACKUP_FILE"
}

# --- 1. 起動時に前回のワールドを復元 ---
restore_world

# --- 2. サーバー停止時の自動バックアップ ---
cleanup() {
    echo "[AutoSave] サーバー停止シグナルを検知。最後のバックアップを実行します..."
    backup_world
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT

# --- 3. マイクラサーバー起動 ---
/image/scripts/start "$@" &
SERVER_PID=$!

# --- 4. 【完全自動】プレイヤー退出 & !save コマンドの監視 ---
(
    sleep 20
    touch /data/logs/latest.log 2>/dev/null || true
    tail -n 0 -F /data/logs/latest.log 2>/dev/null | while read -r line; do
        if echo "$line" | grep -q -E "(lost connection|left the game|!save|/world save)"; then
            echo "[AutoSave] プレイヤーの退出またはセーブ指示を検知しました。"
            backup_world
        fi
    done
) &

# --- 5. 【完全自動】5分ごとの定期保存 ---
(
    while true; do
        sleep 300
        backup_world
    done
) &

# サーバー終了待機
wait "$SERVER_PID"
