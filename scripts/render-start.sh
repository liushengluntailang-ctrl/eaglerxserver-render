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

# --- 1. Web画面配信プラグイン(EaglerWeb)のセットアップ ---
mkdir -p /data/plugins/EaglerWeb/www 2>/dev/null || true
if [ ! -f /data/plugins/EaglerWeb.jar ]; then
    echo "[Setup] EaglerWebプラグインをダウンロード中..."
    curl -sLo /data/plugins/EaglerWeb.jar "https://github.com/lax1dude/eaglerxserver/releases/download/v1.1.1/EaglerWeb.jar" || true
fi

# RenderのURLを開いたときに表示するHTMLを作成
cat << 'EOF' > /data/plugins/EaglerWeb/index.html
<!DOCTYPE html>
<html style="width:100%;height:100%;margin:0;padding:0;overflow:hidden;background-color:#000;">
<head>
    <meta charset="UTF-8">
    <title>Minecraft</title>
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

# --- 2. Supabaseから前回のセーブデータを復元 ---
if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_KEY:-}" ] && [ -n "${SUPABASE_BUCKET:-}" ]; then
    echo "[Restore] Supabaseから前回のセーブデータを復元中..."
    BACKUP_FILE="/tmp/world-latest.tar.gz"
    HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$BACKUP_FILE" -X GET \
      "${SUPABASE_URL}/storage/v1/object/authenticated/${SUPABASE_BUCKET}/world-latest.tar.gz" \
      -H "Authorization: Bearer ${SUPABASE_KEY}" \
      -H "apikey: ${SUPABASE_KEY}")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo "[Restore] セーブデータを復元しました！"
        tar -xzf "$BACKUP_FILE" -C /data
        rm -f "$BACKUP_FILE"
    else
        echo "[Restore] 前回のセーブデータはありません。新規開始します。"
        rm -f "$BACKUP_FILE"
    fi
fi

# --- 3. 定期バックアップ & 退出監視ループ（裏で実行） ---
(
    while true; do
        sleep 300
        if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_KEY:-}" ] && [ -n "${SUPABASE_BUCKET:-}" ]; then
            BACKUP_FILE="/tmp/world-latest.tar.gz"
            tar -czf "$BACKUP_FILE" -C /data world world_nether world_the_end plugins/LoginSecurity 2>/dev/null || true
            curl -s -X POST \
              "${SUPABASE_URL}/storage/v1/object/${SUPABASE_BUCKET}/world-latest.tar.gz" \
              -H "Authorization: Bearer ${SUPABASE_KEY}" \
              -H "apikey: ${SUPABASE_KEY}" \
              -H "x-upsert: true" \
              -H "Content-Type: application/gzip" \
              --data-binary @"$BACKUP_FILE" >/dev/null 2>&1 || true
            rm -f "$BACKUP_FILE"
        fi
    done
) &

# --- 4. マイクラサーバーを表（フォアグラウンド）で起動 ---
# ここで詰まっていたのを exec で直通にしました！
exec /image/scripts/start "$@"
