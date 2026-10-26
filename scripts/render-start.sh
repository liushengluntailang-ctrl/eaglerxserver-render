#!/usr/bin/env bash
set -u

# --- render.yaml の全設定をここに完全注入！ ---
: "${PORT:=10000}"
export SERVER_PORT="${PORT}"
export EULA="TRUE"
export TYPE="PAPER"
export VERSION="1.12.2"
export PAPER_BUILD="1620"
export PAPER_CHANNEL="default"
export MEMORY="256M"
export INIT_MEMORY="128M"
export MAX_MEMORY="256M"
export JVM_OPTS="-XX:+UseSerialGC -XX:ActiveProcessorCount=1 -Xss192k -XX:MaxMetaspaceSize=96M -XX:MaxDirectMemorySize=48M -XX:ReservedCodeCacheSize=12M"
export MALLOC_ARENA_MAX="1"
export CLEAN_SERVER_LIBRARIES="false"
export ONLINE_MODE="false"
export ENABLE_RCON="false"
export ENABLE_AUTOPAUSE="false"
export ENABLE_AUTOSTOP="false"
export USE_AIKAR_FLAGS="false"
export MODE="survival"
export DIFFICULTY="normal"
export PVP="true"
export MAX_PLAYERS="8"
export VIEW_DISTANCE="4"
export SPAWN_PROTECTION="0"
export ALLOW_FLIGHT="true"
export ENABLE_COMMAND_BLOCK="true"
export MOTD="Eaglercraft Survival"

# EaglerXServer + ログインセキュリティ + Web画面配信プラグインを完全自動ダウンロード！
export PLUGINS="https://github.com/lax1dude/eaglerxserver/releases/download/v1.1.1/EaglerXServer.jar
https://github.com/lenis0012/LoginSecurity/releases/download/v3.3.1/LoginSecurity-Spigot-3.3.1.jar
https://github.com/lax1dude/eaglerxserver/releases/download/v1.1.1/EaglerWeb.jar"

# マイクラのデータフォルダに移動
cd /data 2>/dev/null || true

# --- RenderのURLで開くマイクラ画面（HTML）を作成 ---
mkdir -p /data/plugins/EaglerWeb/www 2>/dev/null || true
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
                    name: "サバイバル生活サーバー"
                }
            ]
        };
    </script>
    <iframe id="game_frame" src="https://g.deev.is/eaglercraftX/1.8/" style="border:none;width:100%;height:100%;"></iframe>
</body>
</html>
EOF
cp /data/plugins/EaglerWeb/index.html /data/plugins/EaglerWeb/www/index.html 2>/dev/null || true

# --- Supabaseから前回のデータを復元 ---
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

# --- 5分ごとの定期自動バックアップ（裏で実行） ---
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

# --- マイクラサーバーを起動！ ---
exec /image/scripts/start "$@"
