FROM php:8.3-fpm-alpine

# Install nginx, SQLite, ffmpeg, python3 (for yt-dlp)
RUN apk add --no-cache nginx sqlite sqlite-dev ffmpeg python3 curl \
    && docker-php-ext-install pdo_sqlite \
    && curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod +x /usr/local/bin/yt-dlp

# Nginx config
COPY docker/nginx.conf /etc/nginx/http.d/default.conf

# PHP config
COPY docker/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker/www.conf /usr/local/etc/php-fpm.d/zz-docker.conf

# App files
COPY public/ /var/www/html/
COPY api/ /var/www/html/api/
COPY db/ /var/www/data/

# Data directory (persistent volume mount point)
RUN mkdir -p /var/www/data /var/www/data/audio \
    && chown -R www-data:www-data /var/www/data /var/www/html

# Entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
