-- Music League Clone - SQLite Schema

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Default password is 'jamwall' - change via admin
INSERT OR IGNORE INTO settings (key, value) VALUES ('password', 'jamwall');
INSERT OR IGNORE INTO settings (key, value) VALUES ('league_name', 'JamWall');

CREATE TABLE IF NOT EXISTS rounds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    submission_deadline TEXT NOT NULL,  -- ISO 8601 datetime
    voting_deadline TEXT NOT NULL,      -- ISO 8601 datetime
    max_submissions INTEGER DEFAULT 1, -- songs per player per round
    vote_points INTEGER DEFAULT 10,    -- total points each voter can distribute
    created_at TEXT DEFAULT (datetime('now')),
    created_by TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    round_id INTEGER NOT NULL,
    player_name TEXT NOT NULL,
    youtube_url TEXT NOT NULL,
    youtube_id TEXT NOT NULL,          -- extracted video ID
    video_title TEXT DEFAULT '',
    video_thumbnail TEXT DEFAULT '',
    comment TEXT DEFAULT '',           -- submitter's optional comment
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (round_id) REFERENCES rounds(id) ON DELETE CASCADE,
    UNIQUE(round_id, player_name)     -- one submission per player per round
);

CREATE TABLE IF NOT EXISTS votes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    submission_id INTEGER NOT NULL,
    voter_name TEXT NOT NULL,
    points INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (submission_id) REFERENCES submissions(id) ON DELETE CASCADE,
    UNIQUE(submission_id, voter_name)  -- one vote per voter per submission
);

CREATE TABLE IF NOT EXISTS comments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    submission_id INTEGER NOT NULL,
    player_name TEXT NOT NULL,
    comment TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (submission_id) REFERENCES submissions(id) ON DELETE CASCADE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_submissions_round ON submissions(round_id);
CREATE INDEX IF NOT EXISTS idx_votes_submission ON votes(submission_id);
CREATE INDEX IF NOT EXISTS idx_comments_submission ON comments(submission_id);
