# CLAUDE.md - JamWall

## What This Is
JamWall is a Music League clone that uses YouTube instead of Spotify. Small group (~10 players) music discovery and competition app. Everyone shares one password, picks a display name per session, and plays rounds of submit → vote → results.

## Architecture

### Stack
- **Frontend:** Single-file vanilla JS PWA (`public/index.html`) — no build step, no framework
- **Backend:** PHP 8.3 + SQLite — zero external dependencies
- **Deploy:** Docker (PHP-FPM + Nginx in one Alpine container)

### Directory Structure
```
├── api/                 # PHP API endpoints (one file per resource)
│   ├── db.php           # Shared DB connection, helpers, auth middleware
│   ├── auth.php         # POST - password verification
│   ├── rounds.php       # GET/POST/DELETE - round CRUD
│   ├── submissions.php  # GET/POST - song submissions per round
│   ├── votes.php        # POST - point distribution
│   ├── comments.php     # POST - comments on submissions
│   └── leaderboard.php  # GET - overall standings + per-round results
├── db/
│   └── schema.sql       # SQLite schema, auto-applied on first boot
├── docker/
│   ├── entrypoint.sh    # Starts PHP-FPM + Nginx, inits DB, applies env vars
│   ├── nginx.conf       # Serves static from /var/www/html, proxies /api/*.php to PHP-FPM
│   ├── php.ini          # PHP overrides
│   └── www.conf         # FPM pool config
├── public/
│   ├── index.html       # THE ENTIRE FRONTEND (JS, CSS, HTML in one file)
│   ├── manifest.json    # PWA manifest
│   ├── sw.js            # Service worker (cache-first static, network-first API)
│   └── .htaccess        # Apache fallback (not used in Docker, kept for flexibility)
├── Dockerfile
├── docker-compose.yml
└── .dockerignore
```

### Data Flow
- Auth: `X-Password` and `X-Player` headers on every API request (except auth.php)
- Session: Password + player name stored in `sessionStorage` (browser tab lifetime)
- DB: Single SQLite file at `/var/www/data/jamwall.sqlite` inside the container
- Volume: `jw-data` Docker volume persists the DB across rebuilds

### Round Lifecycle (important — drives all UI logic)
1. **Submitting** — `now < submission_deadline`: Players submit YouTube URLs. Submissions hidden from others.
2. **Voting** — `submission_deadline < now < voting_deadline`: All submissions revealed. Players distribute N points. Can't vote for own submission. Votes hidden from others until results.
3. **Results** — `now > voting_deadline`: Everything visible. Submissions sorted by points. Comments open.

Phase is computed dynamically by `getRoundPhase()` in `api/db.php` and also client-side.

## Key Conventions

### API
- All endpoints return JSON via `jsonResponse()` / `jsonError()` helpers in `db.php`
- Auth check: `requireAuth()` — compares `X-Password` header against DB settings table
- Player name: `getPlayerName()` — reads `X-Player` header
- YouTube ID extraction: `extractYouTubeId()` — regex supports youtube.com, youtu.be, music.youtube.com, shorts
- CORS headers are set in `jsonResponse()` — supports `OPTIONS` preflight

### Frontend
- Everything is in `public/index.html` — styles in `<style>`, logic in `<script>`, no external JS deps
- State object: `state = { password, player, currentRound, votes, screen, history }`
- API wrapper: `api(endpoint, method, body)` — auto-attaches auth headers
- Navigation: `switchTab()` for bottom nav, `openRound(id)` pushes to detail view, `goBack()` returns
- Modals: `openModal(id)` / `closeModal(id)` — bottom-sheet style
- Toasts: `toast(msg, type)` — auto-dismiss after 3s
- HTML escaping: `esc()` function — use it for ALL user-generated content
- Session persistence: `sessionStorage` with keys `jw_password` and `jw_player`

### Database
- SQLite with WAL mode and foreign keys enabled
- `settings` table for key/value config (password, league_name)
- `UNIQUE(round_id, player_name)` on submissions — one song per player per round, upsert on resubmit
- `UNIQUE(submission_id, voter_name)` on votes — votes are replaced wholesale per round via transaction
- Indexes on round_id, submission_id foreign keys

## Docker / Deployment

### Build & Run
```bash
docker compose up -d --build
```
Container exposes port 80 internally, mapped to 8069 on host. Uses external `web` network for reverse proxy.

### Environment Variables
- `LEAGUE_PASSWORD` — applied to DB on container start
- `LEAGUE_NAME` — applied to DB on container start

### Container Internals
- Entrypoint runs `sqlite3` to init DB from schema.sql if DB doesn't exist
- PHP-FPM runs as daemon, Nginx runs in foreground (PID 1)
- Static files: `/var/www/html/`
- DB + schema: `/var/www/data/` (volume mount)

### Target Deployment
- Host: inklit.ch (Kyle's server)
- Reverse proxy in front of the container
- Domain TBD (likely a subdomain of inklit.ch)

## Known Limitations / TODOs

### Needed
- [ ] PWA icons (192x192 and 512x512 PNGs) — manifest references them but they don't exist yet
- [ ] YouTube oEmbed/Data API integration to auto-fetch video titles and thumbnails
- [ ] Admin UI: delete rounds, change password, edit deadlines from the app
- [ ] Push notifications for round deadline reminders
- [ ] Mobile responsiveness audit — built mobile-first but untested on real devices

### Nice to Have
- [ ] Reveal animation for results (currently just renders sorted list)
- [ ] Playlist export (compile all round submissions into a YouTube playlist link)
- [ ] Round history / archive view
- [ ] Dark/light theme toggle
- [ ] Sound effects or confetti on results reveal
- [ ] "Who voted for what" breakdown in results view
- [ ] Duplicate song detection across rounds (not just within a round)

### Known Issues
- Voting shuffle uses a simple `Math.sin` seeded random — not cryptographically fair, but fine for 10 people
- No rate limiting on API endpoints — acceptable for private use, would need hardening if exposed publicly
- No CSRF protection — mitigated by custom header auth pattern
- Service worker caching is basic — may serve stale index.html after updates (bump `jw-v1` cache name to bust)
- The `web` Docker network must exist before `docker compose up` — create with `docker network create web` if missing

## Style Notes
- Dark theme, music-forward aesthetic
- Fonts: Outfit (display/body) + Space Mono (monospace/data)
- Accent: `#6c5ce7` purple with `#e84393` pink secondary
- Bottom sheet modals, toast notifications, phase badges with color coding
- No emojis in UI chrome except functional ones (🎵 submissions, 🗳️ votes, 🏆 winner)

## Testing
No test suite yet. To manually test the full loop:
1. `docker compose up -d --build`
2. Open app, enter password, pick a name
3. Create a round with submission deadline ~2 min from now, voting deadline ~5 min
4. Submit a YouTube URL
5. Open in another browser/incognito with a different name, submit another song
6. Wait for submission phase to end, vote from both sessions
7. Wait for voting to end, verify results and leaderboard
