#!/bin/sh
set -e

# Ensure data directory exists and is writable
mkdir -p /var/www/data /var/www/data/audio /var/www/data/audio/logs
chown -R www-data:www-data /var/www/data

# Clean up broken/truncated MP3 files on startup (from failed conversions)
for mp3 in /var/www/data/audio/*.mp3; do
    [ -f "$mp3" ] || continue
    size=$(stat -c%s "$mp3" 2>/dev/null || echo 0)
    if [ "$size" -lt 102400 ]; then
        id=$(basename "$mp3" .mp3)
        echo "Removing broken MP3: $id ($size bytes)"
        rm -f "$mp3" "/var/www/data/audio/$id.err" "/var/www/data/audio/$id.lock"
    fi
done

# Initialize DB if schema exists and DB doesn't
if [ ! -f /var/www/data/jamwall.sqlite ] && [ -f /var/www/data/schema.sql ]; then
    sqlite3 /var/www/data/jamwall.sqlite < /var/www/data/schema.sql
    chown www-data:www-data /var/www/data/jamwall.sqlite
    echo "Database initialized."
fi

# Set password from env if provided (use PHP parameterized query to avoid SQL injection)
if [ -n "$LEAGUE_PASSWORD" ]; then
    php -r '
        $db = new SQLite3("/var/www/data/jamwall.sqlite");
        $stmt = $db->prepare("UPDATE settings SET value = ? WHERE key = ?");
        $stmt->bindValue(1, $argv[1]);
        $stmt->bindValue(2, "password");
        $stmt->execute();
    ' -- "$LEAGUE_PASSWORD"
    echo "Password set from environment."
fi

# Set league name from env if provided
if [ -n "$LEAGUE_NAME" ]; then
    php -r '
        $db = new SQLite3("/var/www/data/jamwall.sqlite");
        $stmt = $db->prepare("UPDATE settings SET value = ? WHERE key = ?");
        $stmt->bindValue(1, $argv[1]);
        $stmt->bindValue(2, "league_name");
        $stmt->execute();
    ' -- "$LEAGUE_NAME"
fi

# Start PHP-FPM in background
php-fpm -D

# Start Nginx in foreground
nginx -g 'daemon off;'
