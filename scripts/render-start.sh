#!/usr/bin/env bash
set -u

# --- マイクラ本体の設定 ---
: "${PORT:=10000}"
export SERVER_PORT="${PORT}"
export TYPE="PAPER"
export VERSION="1.12.2"
export PAPER_BUILD="1620"
export MEMORY="384M"
export INIT_MEMORY="128M"
export MAX_MEMORY="384M"
export USE_AIKAR_FLAGS="false"
export EULA="TRUE"
export ENABLE_AUTOPAUSE="false"
export ENABLE_AUTOSTOP="false"

# マイクラのデータフォルダに移動
cd /data 2>/dev/null || true

# --- 【新機能】RenderのURLで直接マイクラ画面を配信する設定 ---
mkdir -p /data/plugins/EaglerWeb/www 2>/dev/null || true
if [ ! -f /data/plugins/EaglerWeb.jar ]; then
    echo "[Setup] Web画面配信プラグイン(EaglerWeb)を導入中..."
    curl -sLo /data/plugins/EaglerWeb.jar "https://github.com/lax1dude/eaglerxserver/releases/download/v1.1.1/EaglerWeb.jar" || true
fi

# RenderのURLを開いた時に表示するHTML画面を自動生成
cat << 'EOF' > /data/plugins/EaglerWeb/index.html
<!DOCTYPE html>
<html style="width:100%;height:100%;margin:0;padding:0;overflow:hidden;background-color:#000;">
<head>
    <meta charset="UTF-8">
    <title>Portal</title>
</head>
<body style="width:100%;height:100%;margin:0;padding:0;overflow:hidden;">
    <script type="text/javascript">
        window.eaglercraftXOpts = {
            container: "game_frame",
            assetsURI: "https://r2.eaglercraft.com/assets.epk",
            localesURI: "https://r2.eaglercraft.com/lang/",
            servers: [
                {
                    addr: (location.protocol === "https:" ? "wss://" : "ws://") + location.host,
                    name: "サバイバルサーバー"
                }
            ]
        };
    </script>
    <iframe id="game_frame" src="https://g.deev.is/eaglercraftX/1.8/" style="border:none;width:100%;height:100%;"></iframe>
</body>
</html>
EOF
cp /data/plugins/EaglerWeb/index.html /data/plugins/EaglerWeb/www/index.html 2>/dev/null || true

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
    tar -czf "$BACKUP_FILE" -C /data world world_nether world_the_end plugins/LoginSecurity 2>/dev/null || true

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
    sleep 25
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
