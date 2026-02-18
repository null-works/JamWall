#!/bin/sh
# Background audio conversion: YouTube -> MP3
# Usage: convert.sh <youtube_id>

YTID="$1"
AUDIO_DIR="/var/www/data/audio"
LOG_DIR="$AUDIO_DIR/logs"
LOCK="$AUDIO_DIR/$YTID.lock"
MP3="$AUDIO_DIR/$YTID.mp3"
LOG="$LOG_DIR/$YTID.log"

mkdir -p "$AUDIO_DIR" "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# Skip if already converted
if [ -f "$MP3" ]; then
    log "SKIP: MP3 already exists ($(du -h "$MP3" | cut -f1))"
    exit 0
fi

# Skip if already converting
if [ -f "$LOCK" ]; then
    log "SKIP: Lock file exists, conversion already in progress"
    exit 0
fi

# Start
log "=== START conversion for $YTID ==="
touch "$LOCK"

# Log yt-dlp version
log "yt-dlp version: $(/usr/local/bin/yt-dlp --version 2>&1)"
log "ffmpeg version: $(ffmpeg -version 2>&1 | head -1)"

# Run yt-dlp with verbose output captured to log
log "Running: yt-dlp -x --audio-format mp3 --audio-quality 128k --no-playlist -o '$AUDIO_DIR/$YTID.%(ext)s' 'https://www.youtube.com/watch?v=$YTID'"

/usr/local/bin/yt-dlp \
    -x --audio-format mp3 --audio-quality 128k \
    --no-playlist \
    --verbose \
    -o "$AUDIO_DIR/$YTID.%(ext)s" \
    "https://www.youtube.com/watch?v=$YTID" \
    >> "$LOG" 2>&1

EXIT_CODE=$?
log "yt-dlp exit code: $EXIT_CODE"

# Check results
if [ $EXIT_CODE -eq 0 ] && [ -f "$MP3" ]; then
    SIZE=$(du -h "$MP3" | cut -f1)
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$MP3" 2>/dev/null)
    log "SUCCESS: MP3 created — size=$SIZE duration=${DURATION}s"
    chown www-data:www-data "$MP3" 2>/dev/null
    rm -f "$LOCK"
else
    log "FAILED: exit_code=$EXIT_CODE mp3_exists=$([ -f "$MP3" ] && echo yes || echo no)"
    # List any files that were created
    log "Files in audio dir for this ID:"
    ls -la "$AUDIO_DIR/$YTID"* >> "$LOG" 2>&1
    rm -f "$LOCK"
    echo "conversion_failed (exit $EXIT_CODE)" > "$AUDIO_DIR/$YTID.err"
fi

log "=== END conversion for $YTID ==="
