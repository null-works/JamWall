#!/usr/bin/env bash
#
# JamWall Integration Tests
#
# Spins up PHP built-in server, exercises the full API lifecycle:
#   auth → create round → submit songs → vote → results → leaderboard → comments
#
# Usage: bash tests/integration_test.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d)
DB_PATH="$TEST_DIR/jamwall.sqlite"
PORT=9876
BASE="http://127.0.0.1:$PORT/api"
SERVER_PID=""
PASS=0
FAIL=0
FAILURES=()

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# --- Helpers ---

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        FAIL=$((FAIL + 1))
        FAILURES+=("$desc")
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    Expected to contain: $needle"
        echo "    Got: $haystack"
        FAIL=$((FAIL + 1))
        FAILURES+=("$desc")
    fi
}

assert_http_code() {
    local desc="$1" expected="$2" actual="$3"
    assert_eq "$desc (HTTP $expected)" "$expected" "$actual"
}

# Run SQL against test DB via PHP (no sqlite3 CLI needed)
run_sql() {
    php -r "
        \$db = new SQLite3('$DB_PATH');
        \$db->enableExceptions(true);
        \$db->exec('PRAGMA foreign_keys=ON');
        \$r = \$db->query(\"$1\");
        if (\$r) { while (\$row = \$r->fetchArray(SQLITE3_NUM)) echo implode('|', \$row); }
    "
}

exec_sql() {
    php -r "
        \$db = new SQLite3('$DB_PATH');
        \$db->enableExceptions(true);
        \$db->exec('PRAGMA foreign_keys=ON');
        \$db->exec(\"$1\");
    "
}

# Curl wrapper: returns "HTTP_CODE|BODY"
apicall() {
    local method="$1" endpoint="$2"
    shift 2
    local extra_args=("$@")
    local result
    result=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE/$endpoint" \
        -H "Content-Type: application/json" \
        "${extra_args[@]}" 2>/dev/null)
    local body http_code
    http_code=$(echo "$result" | tail -1)
    body=$(echo "$result" | sed '$d')
    echo "${http_code}|${body}"
}

# --- Setup: Init DB + start PHP server ---

echo "=== Setting up test environment ==="

# Initialize DB from schema using PHP
php -r "
    \$db = new SQLite3('$DB_PATH');
    \$db->enableExceptions(true);
    \$db->exec('PRAGMA journal_mode=WAL');
    \$db->exec('PRAGMA foreign_keys=ON');
    \$schema = file_get_contents('$PROJECT_DIR/db/schema.sql');
    \$db->exec(\$schema);
    echo 'DB initialized';
"
echo " at $DB_PATH"

# Create a PHP router file that overrides DB_PATH for testing
cat > "$TEST_DIR/router.php" << ROUTER
<?php
// Test router: rewrites /api/*.php to actual API files with DB override
\$uri = parse_url(\$_SERVER['REQUEST_URI'], PHP_URL_PATH);

if (preg_match('#^/api/(\w+)\.php\$#', \$uri, \$m)) {
    // Override DB path before including actual API files
    define('DB_PATH', '$DB_PATH');
    define('SCHEMA_PATH', '$PROJECT_DIR/db/schema.sql');

    \$apiFile = '$PROJECT_DIR/api/' . \$m[1] . '.php';
    if (file_exists(\$apiFile)) {
        require \$apiFile;
        return true;
    }
}
http_response_code(404);
echo json_encode(['error' => 'Not found']);
return true;
ROUTER

# Start PHP built-in server
php -S 127.0.0.1:$PORT "$TEST_DIR/router.php" \
    > "$TEST_DIR/server.log" 2>&1 &
SERVER_PID=$!
echo "PHP server started (PID $SERVER_PID) on port $PORT"

# Wait for server to be ready
for i in $(seq 1 20); do
    if curl -s "http://127.0.0.1:$PORT/" > /dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

echo ""

# =============================================================
# Test Suite: Authentication
# =============================================================
echo "=== Authentication ==="

# Correct password
result=$(apicall POST "auth.php" -d '{"password":"jamwall"}')
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Auth with correct password" "200" "$code"
assert_contains "Auth returns success" '"success":true' "$body"
assert_contains "Auth returns league name" '"league_name"' "$body"

# Wrong password
result=$(apicall POST "auth.php" -d '{"password":"wrongpass"}')
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Auth with wrong password" "401" "$code"
assert_contains "Wrong password error message" '"error"' "$body"

# Empty password
result=$(apicall POST "auth.php" -d '{"password":""}')
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Auth with empty password" "401" "$code"

# GET method not allowed
result=$(apicall GET "auth.php")
code="${result%%|*}"
assert_http_code "Auth GET method rejected" "405" "$code"

echo ""

# =============================================================
# Test Suite: Rounds CRUD
# =============================================================
echo "=== Rounds ==="

AUTH_HEADERS=(-H "X-Password: jamwall" -H "X-Player: Alice")

# Create a round (submission phase: far future)
SUB_DEADLINE=$(date -u -d "+2 hours" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v+2H '+%Y-%m-%dT%H:%M:%S')
VOTE_DEADLINE=$(date -u -d "+4 hours" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v+4H '+%Y-%m-%dT%H:%M:%S')

result=$(apicall POST "rounds.php" "${AUTH_HEADERS[@]}" \
    -d "{\"title\":\"Test Round 1\",\"description\":\"Integration test round\",\"submission_deadline\":\"$SUB_DEADLINE\",\"voting_deadline\":\"$VOTE_DEADLINE\",\"vote_points\":10}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Create round" "201" "$code"
assert_contains "Round title in response" '"Test Round 1"' "$body"
ROUND_ID=$(echo "$body" | php -r 'echo json_decode(file_get_contents("php://stdin"))->id;')
assert_contains "Round has phase" '"phase"' "$body"

# List rounds
result=$(apicall GET "rounds.php" "${AUTH_HEADERS[@]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "List rounds" "200" "$code"
assert_contains "List contains our round" '"Test Round 1"' "$body"

# Create round with missing title
result=$(apicall POST "rounds.php" "${AUTH_HEADERS[@]}" \
    -d "{\"title\":\"\",\"submission_deadline\":\"$SUB_DEADLINE\",\"voting_deadline\":\"$VOTE_DEADLINE\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Create round without title fails" "400" "$code"

# Create round with voting before submission
result=$(apicall POST "rounds.php" "${AUTH_HEADERS[@]}" \
    -d "{\"title\":\"Bad Round\",\"submission_deadline\":\"$VOTE_DEADLINE\",\"voting_deadline\":\"$SUB_DEADLINE\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Create round with invalid deadlines fails" "400" "$code"

# Auth required for rounds
result=$(apicall GET "rounds.php" -H "X-Password: wrong" -H "X-Player: Hacker")
code="${result%%|*}"
assert_http_code "Rounds require auth" "401" "$code"

echo ""

# =============================================================
# Test Suite: Submissions
# =============================================================
echo "=== Submissions ==="

# Submit a YouTube URL (Alice)
result=$(apicall POST "submissions.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://www.youtube.com/watch?v=dQw4w9WgXcQ\",\"comment\":\"Never gonna give you up\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Alice submits a song" "201" "$code"
assert_contains "Submit returns youtube_id" '"youtube_id":"dQw4w9WgXcQ"' "$body"

# Submit another song (Bob)
BOB_HEADERS=(-H "X-Password: jamwall" -H "X-Player: Bob")
result=$(apicall POST "submissions.php" "${BOB_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://youtu.be/9bZkp7q19f0\",\"comment\":\"Gangnam Style\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Bob submits a song" "201" "$code"
assert_contains "Bob's youtube_id" '"youtube_id":"9bZkp7q19f0"' "$body"

# Third player (Charlie)
CHARLIE_HEADERS=(-H "X-Password: jamwall" -H "X-Player: Charlie")
result=$(apicall POST "submissions.php" "${CHARLIE_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://music.youtube.com/watch?v=kJQP7kiw5Fk\",\"comment\":\"Despacito\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Charlie submits a song" "201" "$code"

# Duplicate YouTube URL in same round (Charlie tries Alice's song)
result=$(apicall POST "submissions.php" "${CHARLIE_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://www.youtube.com/watch?v=dQw4w9WgXcQ\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Duplicate song in same round rejected" "400" "$code"

# Alice resubmits same song with updated comment (should succeed after duplicate check fix)
result=$(apicall POST "submissions.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://www.youtube.com/watch?v=dQw4w9WgXcQ\",\"comment\":\"Updated comment on same song\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Alice resubmits same song (comment update)" "201" "$code"

# Alice resubmits (upsert) with a different song
result=$(apicall POST "submissions.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://www.youtube.com/watch?v=L_jWHffIx5E\",\"comment\":\"Changed my mind - Smells Like Teen Spirit\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Alice resubmits (upsert)" "201" "$code"
assert_contains "New youtube_id" '"youtube_id":"L_jWHffIx5E"' "$body"

# Submit with v= as non-first query param (tests regex fix)
DAVE_HEADERS=(-H "X-Password: jamwall" -H "X-Player: Dave")
result=$(apicall POST "submissions.php" "${DAVE_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://www.youtube.com/watch?feature=share&v=hT_nvWreIhg\",\"comment\":\"v not first param\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Submit with v= as non-first param" "201" "$code"
assert_contains "Extracted ID from non-first v param" '"youtube_id":"hT_nvWreIhg"' "$body"

# Invalid YouTube URL
result=$(apicall POST "submissions.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"youtube_url\":\"https://www.google.com\"}")
code="${result%%|*}"
assert_http_code "Invalid YouTube URL rejected" "400" "$code"

# Get submissions (during submission phase — should hide others)
result=$(apicall GET "submissions.php?round_id=$ROUND_ID" "${AUTH_HEADERS[@]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Get submissions" "200" "$code"
assert_contains "Returns phase" '"phase":"submitting"' "$body"
assert_contains "Submissions array present" '"submissions"' "$body"

# Missing round_id
result=$(apicall GET "submissions.php" "${AUTH_HEADERS[@]}")
code="${result%%|*}"
assert_http_code "Submissions without round_id fails" "400" "$code"

echo ""

# =============================================================
# Test Suite: Voting
# =============================================================
echo "=== Voting ==="

# Move round to voting phase by updating submission_deadline to the past
PAST_SUB=$(date -u -d "-1 hour" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v-1H '+%Y-%m-%dT%H:%M:%S')
exec_sql "UPDATE rounds SET submission_deadline='$PAST_SUB' WHERE id=$ROUND_ID;"

# Verify we're in voting phase
result=$(apicall GET "submissions.php?round_id=$ROUND_ID" "${AUTH_HEADERS[@]}")
code="${result%%|*}"; body="${result#*|}"
assert_contains "Round now in voting phase" '"phase":"voting"' "$body"

# Get submission IDs (need them for voting)
SUB_IDS=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    $ids = [];
    foreach ($d["submissions"] as $s) { $ids[$s["player_name"]] = $s["id"]; }
    echo json_encode($ids);
')
BOB_SUB_ID=$(echo "$SUB_IDS" | php -r 'echo json_decode(file_get_contents("php://stdin"))->Bob;')
CHARLIE_SUB_ID=$(echo "$SUB_IDS" | php -r 'echo json_decode(file_get_contents("php://stdin"))->Charlie;')
ALICE_SUB_ID=$(echo "$SUB_IDS" | php -r 'echo json_decode(file_get_contents("php://stdin"))->Alice;')

# Alice votes (can't vote for own submission)
result=$(apicall POST "votes.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"votes\":[{\"submission_id\":$BOB_SUB_ID,\"points\":7},{\"submission_id\":$CHARLIE_SUB_ID,\"points\":3}]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Alice votes successfully" "200" "$code"
assert_contains "Vote success" '"success":true' "$body"

# Bob votes
result=$(apicall POST "votes.php" "${BOB_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"votes\":[{\"submission_id\":$ALICE_SUB_ID,\"points\":6},{\"submission_id\":$CHARLIE_SUB_ID,\"points\":4}]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Bob votes successfully" "200" "$code"

# Charlie votes
result=$(apicall POST "votes.php" "${CHARLIE_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"votes\":[{\"submission_id\":$ALICE_SUB_ID,\"points\":5},{\"submission_id\":$BOB_SUB_ID,\"points\":5}]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Charlie votes successfully" "200" "$code"

# Alice tries to vote for herself
result=$(apicall POST "votes.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"votes\":[{\"submission_id\":$ALICE_SUB_ID,\"points\":10}]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Self-vote rejected" "400" "$code"
assert_contains "Self-vote error message" "own submission" "$body"

# Over-budget vote (more than vote_points)
result=$(apicall POST "votes.php" "${AUTH_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND_ID,\"votes\":[{\"submission_id\":$BOB_SUB_ID,\"points\":20}]}")
code="${result%%|*}"
assert_http_code "Over-budget vote rejected" "400" "$code"

echo ""

# =============================================================
# Test Suite: Results & Leaderboard
# =============================================================
echo "=== Results & Leaderboard ==="

# Move round to results phase
PAST_VOTE=$(date -u -d "-1 minute" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v-1M '+%Y-%m-%dT%H:%M:%S')
exec_sql "UPDATE rounds SET voting_deadline='$PAST_VOTE' WHERE id=$ROUND_ID;"

# Verify results phase
result=$(apicall GET "submissions.php?round_id=$ROUND_ID" "${AUTH_HEADERS[@]}")
code="${result%%|*}"; body="${result#*|}"
assert_contains "Round now in results phase" '"phase":"results"' "$body"

# Check that submissions are sorted by points (highest first)
FIRST_POINTS=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    echo $d["submissions"][0]["total_points"];
')
LAST_POINTS=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    $subs = $d["submissions"];
    echo end($subs)["total_points"];
')
if [[ "$FIRST_POINTS" -ge "$LAST_POINTS" ]]; then
    echo "  PASS: Submissions sorted by points descending ($FIRST_POINTS >= $LAST_POINTS)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Submissions not sorted ($FIRST_POINTS < $LAST_POINTS)"
    FAIL=$((FAIL + 1))
    FAILURES+=("Submissions sorted by points descending")
fi

# Expected points: Alice=6+5=11, Bob=7+5=12, Charlie=3+4=7
# Bob should be first
WINNER=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    echo $d["submissions"][0]["player_name"];
')
assert_eq "Bob wins with most points" "Bob" "$WINNER"

# Leaderboard
result=$(apicall GET "leaderboard.php" "${AUTH_HEADERS[@]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Get leaderboard" "200" "$code"
assert_contains "Leaderboard has entries" '"leaderboard"' "$body"
assert_contains "Round results included" '"round_results"' "$body"

# Verify leaderboard ranking
LEADER=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    echo $d["leaderboard"][0]["player_name"];
')
assert_eq "Bob leads leaderboard" "Bob" "$LEADER"

echo ""

# =============================================================
# Test Suite: Comments
# =============================================================
echo "=== Comments ==="

# Add a comment
result=$(apicall POST "comments.php" "${AUTH_HEADERS[@]}" \
    -d "{\"submission_id\":$BOB_SUB_ID,\"comment\":\"Great pick!\"}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Add comment" "201" "$code"
assert_contains "Comment text in response" '"Great pick!"' "$body"
assert_contains "Comment author" '"player_name":"Alice"' "$body"

# Bob comments too
result=$(apicall POST "comments.php" "${BOB_HEADERS[@]}" \
    -d "{\"submission_id\":$ALICE_SUB_ID,\"comment\":\"Nice one!\"}")
code="${result%%|*}"
assert_http_code "Bob adds comment" "201" "$code"

# Empty comment rejected
result=$(apicall POST "comments.php" "${AUTH_HEADERS[@]}" \
    -d "{\"submission_id\":$BOB_SUB_ID,\"comment\":\"\"}")
code="${result%%|*}"
assert_http_code "Empty comment rejected" "400" "$code"

# Invalid submission_id
result=$(apicall POST "comments.php" "${AUTH_HEADERS[@]}" \
    -d "{\"submission_id\":99999,\"comment\":\"Ghost comment\"}")
code="${result%%|*}"
assert_http_code "Comment on nonexistent submission fails" "404" "$code"

# Verify comments show up in submissions
result=$(apicall GET "submissions.php?round_id=$ROUND_ID" "${AUTH_HEADERS[@]}")
body="${result#*|}"
assert_contains "Comments visible in submission data" '"Great pick!"' "$body"

echo ""

# =============================================================
# Test Suite: Round Deletion
# =============================================================
echo "=== Round Deletion ==="

# Create a round to delete
result=$(apicall POST "rounds.php" "${AUTH_HEADERS[@]}" \
    -d "{\"title\":\"Doomed Round\",\"description\":\"Will be deleted\",\"submission_deadline\":\"$SUB_DEADLINE\",\"voting_deadline\":\"$VOTE_DEADLINE\"}")
code="${result%%|*}"; body="${result#*|}"
DELETE_ROUND_ID=$(echo "$body" | php -r 'echo json_decode(file_get_contents("php://stdin"))->id;')
assert_http_code "Create round to delete" "201" "$code"

# Delete it
result=$(apicall DELETE "rounds.php?id=$DELETE_ROUND_ID" "${AUTH_HEADERS[@]}")
code="${result%%|*}"; body="${result#*|}"
assert_http_code "Delete round" "200" "$code"
assert_contains "Delete confirms success" '"success":true' "$body"

# Verify it's gone
result=$(apicall GET "rounds.php" "${AUTH_HEADERS[@]}")
body="${result#*|}"
if echo "$body" | grep -qF "Doomed Round"; then
    echo "  FAIL: Deleted round still present"
    FAIL=$((FAIL + 1))
    FAILURES+=("Deleted round still present")
else
    echo "  PASS: Deleted round no longer listed"
    PASS=$((PASS + 1))
fi

echo ""

# =============================================================
# Test Suite: Vote Re-submission (replace votes)
# =============================================================
echo "=== Vote Re-submission ==="

# Create a fresh voting-phase round
PAST_SUB2=$(date -u -d "-30 minutes" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v-30M '+%Y-%m-%dT%H:%M:%S')
FUTURE_VOTE2=$(date -u -d "+2 hours" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v+2H '+%Y-%m-%dT%H:%M:%S')

result=$(apicall POST "rounds.php" "${AUTH_HEADERS[@]}" \
    -d "{\"title\":\"Revote Round\",\"description\":\"Test revoting\",\"submission_deadline\":\"$PAST_SUB2\",\"voting_deadline\":\"$FUTURE_VOTE2\",\"vote_points\":10}")
body="${result#*|}"
ROUND2_ID=$(echo "$body" | php -r 'echo json_decode(file_get_contents("php://stdin"))->id;')

# Insert submissions directly via PHP/SQLite
exec_sql "INSERT INTO submissions (round_id, player_name, youtube_url, youtube_id) VALUES ($ROUND2_ID, 'Alice', 'https://youtu.be/aaa11111111', 'aaa11111111');"
exec_sql "INSERT INTO submissions (round_id, player_name, youtube_url, youtube_id) VALUES ($ROUND2_ID, 'Bob', 'https://youtu.be/bbb22222222', 'bbb22222222');"

# Get submission IDs
result=$(apicall GET "submissions.php?round_id=$ROUND2_ID" "${CHARLIE_HEADERS[@]}")
body="${result#*|}"
R2_ALICE_ID=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    foreach ($d["submissions"] as $s) { if ($s["player_name"]==="Alice") echo $s["id"]; }
')
R2_BOB_ID=$(echo "$body" | php -r '
    $d = json_decode(file_get_contents("php://stdin"), true);
    foreach ($d["submissions"] as $s) { if ($s["player_name"]==="Bob") echo $s["id"]; }
')

# Charlie votes initially
result=$(apicall POST "votes.php" "${CHARLIE_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND2_ID,\"votes\":[{\"submission_id\":$R2_ALICE_ID,\"points\":8},{\"submission_id\":$R2_BOB_ID,\"points\":2}]}")
code="${result%%|*}"
assert_http_code "Charlie initial vote" "200" "$code"

# Charlie changes votes (should replace)
result=$(apicall POST "votes.php" "${CHARLIE_HEADERS[@]}" \
    -d "{\"round_id\":$ROUND2_ID,\"votes\":[{\"submission_id\":$R2_ALICE_ID,\"points\":3},{\"submission_id\":$R2_BOB_ID,\"points\":7}]}")
code="${result%%|*}"
assert_http_code "Charlie revotes (replaces)" "200" "$code"

# Verify the updated points via PHP/SQLite
ALICE_PTS=$(run_sql "SELECT SUM(points) FROM votes WHERE submission_id=$R2_ALICE_ID AND voter_name='Charlie';")
BOB_PTS=$(run_sql "SELECT SUM(points) FROM votes WHERE submission_id=$R2_BOB_ID AND voter_name='Charlie';")
assert_eq "After revote Alice has 3 points from Charlie" "3" "$ALICE_PTS"
assert_eq "After revote Bob has 7 points from Charlie" "7" "$BOB_PTS"

# Verify no duplicate vote rows
VOTE_COUNT=$(run_sql "SELECT COUNT(*) FROM votes WHERE voter_name='Charlie' AND submission_id IN (SELECT id FROM submissions WHERE round_id=$ROUND2_ID);")
assert_eq "No duplicate vote rows after revote" "2" "$VOTE_COUNT"

echo ""

# =============================================================
# Summary
# =============================================================
echo "$(printf '=%.0s' {1..50})"
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:"
    for f in "${FAILURES[@]}"; do
        echo "  - $f"
    done
fi
echo "$(printf '=%.0s' {1..50})"
exit $FAIL
