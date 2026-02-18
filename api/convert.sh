#!/bin/sh
# Background audio conversion: YouTube -> MP3
# Usage: convert.sh <youtube_id>
#
# Ported from jcink_audio: downloads to temp dir first to avoid
# leftover intermediate files (.webm, .part) in the audio dir.

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
    # Check for stale lock (older than 10 minutes)
    if [ -f "$LOCK" ]; then
        LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
        if [ "$LOCK_AGE" -gt 600 ]; then
            log "WARN: Removing stale lock (${LOCK_AGE}s old)"
            rm -f "$LOCK"
        else
            log "SKIP: Lock file exists, conversion already in progress (${LOCK_AGE}s)"
            exit 0
        fi
    fi
fi

# Start
log "=== START conversion for $YTID ==="
touch "$LOCK"

# Create a temp directory for the download (like jcink_audio does)
# This prevents intermediate .webm/.part files from polluting the audio dir
TEMP_DIR=$(mktemp -d)
log "Temp dir: $TEMP_DIR"

# Log versions
log "yt-dlp version: $(/usr/local/bin/yt-dlp --version 2>&1)"
log "ffmpeg version: $(ffmpeg -version 2>&1 | head -1)"

# Download to temp dir first, then move to final location
log "Running: yt-dlp -x --audio-format mp3 --audio-quality 128k --no-playlist"

/usr/local/bin/yt-dlp \
    -x \
    --audio-format mp3 \
    --audio-quality 128k \
    --no-playlist \
    --no-warnings \
    -o "$TEMP_DIR/$YTID.%(ext)s" \
    "https://www.youtube.com/watch?v=$YTID" \
    >> "$LOG" 2>&1

EXIT_CODE=$?
log "yt-dlp exit code: $EXIT_CODE"

TEMP_MP3="$TEMP_DIR/$YTID.mp3"

# Validate and move to final location
if [ $EXIT_CODE -eq 0 ] && [ -f "$TEMP_MP3" ]; then
    SIZE=$(du -h "$TEMP_MP3" | cut -f1)
    BYTES=$(wc -c < "$TEMP_MP3")

    # Sanity check: file should be > 100KB for any real audio
    if [ "$BYTES" -lt 102400 ]; then
        log "FAILED: MP3 too small (${SIZE}, ${BYTES} bytes) — likely corrupt"
        rm -rf "$TEMP_DIR"
        rm -f "$LOCK"
        echo "conversion_failed (file too small: ${BYTES} bytes)" > "$AUDIO_DIR/$YTID.err"
        exit 1
    fi

    # Get duration via ffprobe
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TEMP_MP3" 2>/dev/null)
    log "SUCCESS: MP3 created — size=$SIZE duration=${DURATION}s"

    # Move to final location
    mv "$TEMP_MP3" "$MP3"
    chown www-data:www-data "$MP3" 2>/dev/null
    rm -f "$LOCK"
else
    log "FAILED: exit_code=$EXIT_CODE mp3_exists=$([ -f "$TEMP_MP3" ] && echo yes || echo no)"
    log "Files in temp dir:"
    ls -la "$TEMP_DIR/" >> "$LOG" 2>&1
    rm -f "$LOCK"
    echo "conversion_failed (exit $EXIT_CODE)" > "$AUDIO_DIR/$YTID.err"
fi

# Always clean up temp dir
rm -rf "$TEMP_DIR"

log "=== END conversion for $YTID ==="
