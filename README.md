# 🎵 JamWall Clone

A source-agnostic JamWall clone using YouTube instead of Spotify. PWA-ready, PHP + SQLite backend in Docker, designed for small groups (~10 players).

## How It Works

1. **Everyone enters with a shared password** and picks a display name
2. **Someone creates a round** with a theme and deadlines
3. **Players submit YouTube links** during the submission phase
4. **When submissions close**, everyone listens and distributes vote points
5. **When voting closes**, results and leaderboard are revealed

## Stack

- **Frontend:** Vanilla JS PWA (single HTML file, no build step)
- **Backend:** PHP 8.3 + SQLite (zero external dependencies)
- **Music:** YouTube embeds (youtube.com, youtu.be, music.youtube.com)
- **Deploy:** Docker (PHP-FPM + Nginx in one container)

## Quick Start

```bash
git clone https://github.com/YOU/jamwall.git
cd jamwall

# Edit docker-compose.yml to set password/name, then:
docker compose up -d --build
```

App available on port `8069`. Reverse proxy to it from your domain.

## Configuration

Environment variables in `docker-compose.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `LEAGUE_PASSWORD` | `changeme` | Shared password to enter the league |
| `LEAGUE_NAME` | `JamWall` | Display name for the league |

## Data Persistence

SQLite database lives in a Docker volume (`jw-data`). Survives container rebuilds.

```bash
# Backup
docker cp jamwall:/var/www/data/jamwall.sqlite ./backup.sqlite

# Change password after deploy
docker exec jamwall sqlite3 /var/www/data/jamwall.sqlite \
  "UPDATE settings SET value='newpass' WHERE key='password';"
```

## Reverse Proxy

```nginx
server {
    server_name jamwall.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## API Endpoints

All endpoints (except auth) require `X-Password` and `X-Player` headers.

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth.php` | Verify password |
| GET/POST/DELETE | `/api/rounds.php` | CRUD rounds |
| GET/POST | `/api/submissions.php` | Get/submit songs |
| POST | `/api/votes.php` | Submit votes |
| POST | `/api/comments.php` | Add comments |
| GET | `/api/leaderboard.php` | Standings |

## License

MIT
