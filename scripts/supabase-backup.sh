#!/bin/bash

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ] || [ -z "$SUPABASE_BUCKET" ]; then
    echo "[Backup] Supabase environment variables are missing."
    exit 1
fi

PIPE_PATH="/tmp/minecraft_console"
BACKUP_ARCHIVE="/tmp/world-latest.tar.gz"

if [ -p "$PIPE_PATH" ]; then
    echo "say §e[Backup] §fワールドデータをSupabaseへ保存中..." > "$PIPE_PATH"
    echo "save-off" > "$PIPE_PATH"
    echo "save-all flush" > "$PIPE_PATH"
    sleep 3
fi

echo "[Backup] Compressing world files..."
tar -czf "$BACKUP_ARCHIVE" \
    world \
    world_nether \
    world_the_end \
    plugins/LoginSecurity/*.db \
    2>/dev/null

if [ -p "$PIPE_PATH" ]; then
    echo "save-on" > "$PIPE_PATH"
fi

echo "[Backup] Uploading to Supabase Storage..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "${SUPABASE_URL}/storage/v1/object/${SUPABASE_BUCKET}/world-latest.tar.gz" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "x-upsert: true" \
  -H "Content-Type: application/gzip" \
  --data-binary @"$BACKUP_ARCHIVE")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 201 ]; then
    echo "[Backup] Backup succeeded!"
    if [ -p "$PIPE_PATH" ]; then
        echo "say §a[Backup] §f正常にクラウド保存が完了しました！" > "$PIPE_PATH"
    fi
else
    echo "[Backup] Upload failed with HTTP status: $HTTP_STATUS"
    if [ -p "$PIPE_PATH" ]; then
        echo "say §c[Backup] §f保存に失敗しました (Status: $HTTP_STATUS)" > "$PIPE_PATH"
    fi
fi

rm -f "$BACKUP_ARCHIVE"
