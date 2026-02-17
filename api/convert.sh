#!/bin/sh
# Background audio conversion: YouTube -> MP3
# Usage: convert.sh <youtube_id>

YTID="$1"
AUDIO_DIR="/var/www/data/audio"
LOCK="$AUDIO_DIR/$YTID.lock"
MP3="$AUDIO_DIR/$YTID.mp3"

# Skip if already converted or already converting
[ -f "$MP3" ] && exit 0
[ -f "$LOCK" ] && exit 0

mkdir -p "$AUDIO_DIR"
touch "$LOCK"

/usr/local/bin/yt-dlp \
    -x --audio-format mp3 --audio-quality 5 \
    --no-playlist --no-warnings \
    -o "$AUDIO_DIR/$YTID.%(ext)s" \
    "https://www.youtube.com/watch?v=$YTID" \
    > /dev/null 2>&1

if [ $? -eq 0 ] && [ -f "$MP3" ]; then
    chown www-data:www-data "$MP3" 2>/dev/null
    rm -f "$LOCK"
else
    rm -f "$LOCK"
    # Leave a marker so we know it failed
    echo "conversion_failed" > "$AUDIO_DIR/$YTID.err"
fi
