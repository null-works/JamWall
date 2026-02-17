#!/bin/sh
set -e

# Ensure data directory exists and is writable
mkdir -p /var/www/data /var/www/data/audio
chown -R www-data:www-data /var/www/data

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
