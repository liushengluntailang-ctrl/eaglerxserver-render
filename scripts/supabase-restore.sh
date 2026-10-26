#!/bin/bash

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_KEY" ] || [ -z "$SUPABASE_BUCKET" ]; then
    echo "[Restore] Supabase environment variables not set. Skipping restore."
    exit 0
fi

BACKUP_ARCHIVE="/tmp/world-latest.tar.gz"

echo "[Restore] Checking for existing backup on Supabase Storage..."

HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$BACKUP_ARCHIVE" -X GET \
  "${SUPABASE_URL}/storage/v1/object/authenticated/${SUPABASE_BUCKET}/world-latest.tar.gz" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" \
  -H "apikey: ${SUPABASE_KEY}")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "[Restore] Backup found. Restoring world data..."
    tar -xzf "$BACKUP_ARCHIVE" -C .
    rm -f "$BACKUP_ARCHIVE"
    echo "[Restore] Restoration complete!"
else
    echo "[Restore] No previous backup found (HTTP $HTTP_STATUS). Starting fresh world."
    rm -f "$BACKUP_ARCHIVE"
fi
