#!/bin/sh
set -e

# Ensure data directory exists and is writable
mkdir -p /var/www/data
chown -R www-data:www-data /var/www/data

# Initialize DB if schema exists and DB doesn't
if [ ! -f /var/www/data/jamwall.sqlite ] && [ -f /var/www/data/schema.sql ]; then
    sqlite3 /var/www/data/jamwall.sqlite < /var/www/data/schema.sql
    chown www-data:www-data /var/www/data/jamwall.sqlite
    echo "Database initialized."
fi

# Set password from env if provided
if [ -n "$LEAGUE_PASSWORD" ]; then
    sqlite3 /var/www/data/jamwall.sqlite "UPDATE settings SET value='$LEAGUE_PASSWORD' WHERE key='password';"
    echo "Password set from environment."
fi

# Set league name from env if provided
if [ -n "$LEAGUE_NAME" ]; then
    sqlite3 /var/www/data/jamwall.sqlite "UPDATE settings SET value='$LEAGUE_NAME' WHERE key='league_name';"
fi

# Start PHP-FPM in background
php-fpm -D

# Start Nginx in foreground
nginx -g 'daemon off;'
