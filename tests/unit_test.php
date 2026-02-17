<?php
/**
 * JamWall Unit Tests
 *
 * Tests pure functions from api/db.php: extractYouTubeId() and getRoundPhase().
 * Run with: php tests/unit_test.php
 */

// --- Minimal test framework ---
$testsPassed = 0;
$testsFailed = 0;
$failures = [];

function assertEqual($expected, $actual, string $testName): void {
    global $testsPassed, $testsFailed, $failures;
    if ($expected === $actual) {
        $testsPassed++;
        echo "  PASS: $testName\n";
    } else {
        $testsFailed++;
        $failures[] = $testName;
        echo "  FAIL: $testName\n";
        echo "    Expected: " . var_export($expected, true) . "\n";
        echo "    Actual:   " . var_export($actual, true) . "\n";
    }
}

// --- Load only the pure functions from db.php (no DB needed) ---
// These must be kept in sync with api/db.php.

function extractYouTubeId(string $url): ?string {
    $patterns = [
        '/(?:youtube\.com\/watch\?(?:[^#]*&)?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/v\/|youtube\.com\/shorts\/|music\.youtube\.com\/watch\?(?:[^#]*&)?v=)([a-zA-Z0-9_-]{11})/',
    ];
    foreach ($patterns as $pattern) {
        if (preg_match($pattern, $url, $matches)) {
            return $matches[1];
        }
    }
    return null;
}

function getRoundPhase(array $round): string {
    $now = date('Y-m-d\TH:i:s');
    if ($now < $round['submission_deadline']) {
        return 'submitting';
    } elseif ($now < $round['voting_deadline']) {
        return 'voting';
    }
    return 'results';
}

// =============================================================
// Test Suite: extractYouTubeId()
// =============================================================
echo "\n=== extractYouTubeId() ===\n\n";

// Standard youtube.com/watch URLs
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
    'Standard watch URL');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://youtube.com/watch?v=dQw4w9WgXcQ'),
    'Watch URL without www');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('http://www.youtube.com/watch?v=dQw4w9WgXcQ'),
    'Watch URL with http');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42'),
    'Watch URL with extra params after v');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmE'),
    'Watch URL with playlist param after v');

// v= not as first query parameter (previously broken)
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/watch?list=PLrAXtmE&v=dQw4w9WgXcQ'),
    'Watch URL with v= as second param');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ'),
    'Watch URL with feature param before v');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/watch?si=abcdef&list=PL123&v=dQw4w9WgXcQ'),
    'Watch URL with multiple params before v');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://music.youtube.com/watch?list=RDAMVM&v=dQw4w9WgXcQ'),
    'YouTube Music with v= as second param');

// Short URLs (youtu.be)
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://youtu.be/dQw4w9WgXcQ'),
    'Short youtu.be URL');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://youtu.be/dQw4w9WgXcQ?t=42'),
    'Short youtu.be URL with timestamp');

// Embed URLs
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
    'Embed URL');

// Old /v/ format
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/v/dQw4w9WgXcQ'),
    'Old /v/ URL');

// Shorts
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
    'Shorts URL');

// YouTube Music
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
    'YouTube Music URL');
assertEqual('dQw4w9WgXcQ', extractYouTubeId('https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM'),
    'YouTube Music URL with list param');

// IDs with hyphens and underscores
assertEqual('abc-_1234EF', extractYouTubeId('https://youtu.be/abc-_1234EF'),
    'ID with hyphen and underscore');

// Invalid / edge cases
assertEqual(null, extractYouTubeId('https://www.google.com'),
    'Non-YouTube URL returns null');
assertEqual(null, extractYouTubeId('not a url at all'),
    'Plain text returns null');
assertEqual(null, extractYouTubeId(''),
    'Empty string returns null');
assertEqual(null, extractYouTubeId('https://youtube.com/watch?v=short'),
    'Too-short ID returns null');
assertEqual(null, extractYouTubeId('https://vimeo.com/12345678'),
    'Vimeo URL returns null');
assertEqual(null, extractYouTubeId('https://youtube.com/channel/UCxxxxxx'),
    'Channel URL returns null');

// =============================================================
// Test Suite: getRoundPhase()
// =============================================================
echo "\n=== getRoundPhase() ===\n\n";

// Use the same format as the fixed getRoundPhase: Y-m-d\TH:i:s (no timezone offset)
$fmt = 'Y-m-d\TH:i:s';

// Future deadlines → submitting
$futureSubmission = date($fmt, strtotime('+1 hour'));
$futureVoting = date($fmt, strtotime('+2 hours'));
assertEqual('submitting', getRoundPhase([
    'submission_deadline' => $futureSubmission,
    'voting_deadline' => $futureVoting,
]), 'Both deadlines in future → submitting');

// Submission past, voting future → voting
$pastSubmission = date($fmt, strtotime('-1 hour'));
$futureVoting2 = date($fmt, strtotime('+1 hour'));
assertEqual('voting', getRoundPhase([
    'submission_deadline' => $pastSubmission,
    'voting_deadline' => $futureVoting2,
]), 'Submission past, voting future → voting');

// Both past → results
$pastSubmission2 = date($fmt, strtotime('-2 hours'));
$pastVoting = date($fmt, strtotime('-1 hour'));
assertEqual('results', getRoundPhase([
    'submission_deadline' => $pastSubmission2,
    'voting_deadline' => $pastVoting,
]), 'Both deadlines past → results');

// Far future (next year)
$farFutureSubmission = date($fmt, strtotime('+1 year'));
$farFutureVoting = date($fmt, strtotime('+2 years'));
assertEqual('submitting', getRoundPhase([
    'submission_deadline' => $farFutureSubmission,
    'voting_deadline' => $farFutureVoting,
]), 'Far future deadlines → submitting');

// Far past
$farPastSubmission = date($fmt, strtotime('-1 year'));
$farPastVoting = date($fmt, strtotime('-6 months'));
assertEqual('results', getRoundPhase([
    'submission_deadline' => $farPastSubmission,
    'voting_deadline' => $farPastVoting,
]), 'Far past deadlines → results');

// Edge: submission just barely in the past (1 second ago)
$justPast = date($fmt, time() - 1);
$futureVoting3 = date($fmt, strtotime('+1 hour'));
assertEqual('voting', getRoundPhase([
    'submission_deadline' => $justPast,
    'voting_deadline' => $futureVoting3,
]), 'Submission 1s ago, voting future → voting');

// Cross-format: deadlines stored without timezone offset should still compare correctly
assertEqual('submitting', getRoundPhase([
    'submission_deadline' => '2099-12-31T23:59:59',
    'voting_deadline' => '2099-12-31T23:59:59',
]), 'Far future ISO date without offset → submitting');

assertEqual('results', getRoundPhase([
    'submission_deadline' => '2000-01-01T00:00:00',
    'voting_deadline' => '2000-01-01T00:00:01',
]), 'Far past ISO date without offset → results');

// =============================================================
// Summary
// =============================================================
echo "\n" . str_repeat('=', 50) . "\n";
echo "Results: $testsPassed passed, $testsFailed failed\n";
if ($testsFailed > 0) {
    echo "Failed tests:\n";
    foreach ($failures as $f) {
        echo "  - $f\n";
    }
}
echo str_repeat('=', 50) . "\n";
exit($testsFailed > 0 ? 1 : 0);
