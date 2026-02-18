<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();
$db = getDB();

// GET - Get submissions for a round
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $roundId = intval($_GET['round_id'] ?? 0);
    if ($roundId <= 0) jsonError('Round ID required');
    
    $player = getPlayerName();
    
    // Get round info to determine phase
    $stmt = $db->prepare('SELECT * FROM rounds WHERE id = ?');
    $stmt->bindValue(1, $roundId);
    $round = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    if (!$round) jsonError('Round not found', 404);
    
    $phase = getRoundPhase($round);
    
    // Get submissions
    $stmt = $db->prepare('SELECT * FROM submissions WHERE round_id = ? ORDER BY created_at ASC');
    $stmt->bindValue(1, $roundId);
    $results = $stmt->execute();
    
    $submissions = [];
    while ($row = $results->fetchArray(SQLITE3_ASSOC)) {
        // During submission phase, hide who submitted what (unless it's yours)
        if ($phase === 'submitting' && $row['player_name'] !== $player) {
            $row['player_name'] = '???';
            $row['youtube_url'] = '';
            $row['youtube_id'] = '';
            $row['video_title'] = 'Hidden until voting begins';
            $row['video_thumbnail'] = '';
        }
        
        // Get votes for this submission
        $vStmt = $db->prepare('SELECT voter_name, points FROM votes WHERE submission_id = ?');
        $vStmt->bindValue(1, $row['id']);
        $vResults = $vStmt->execute();
        $row['votes'] = [];
        $row['total_points'] = 0;
        while ($vote = $vResults->fetchArray(SQLITE3_ASSOC)) {
            // During voting, only show your own votes
            if ($phase === 'voting' && $vote['voter_name'] !== $player) {
                continue;
            }
            $row['votes'][] = $vote;
            $row['total_points'] += $vote['points'];
        }
        
        // If in results phase, show all votes total
        if ($phase === 'results') {
            $tStmt = $db->prepare('SELECT COALESCE(SUM(points), 0) as total FROM votes WHERE submission_id = ?');
            $tStmt->bindValue(1, $row['id']);
            $row['total_points'] = $tStmt->execute()->fetchArray(SQLITE3_ASSOC)['total'];
        }
        
        // Get comments
        $cStmt = $db->prepare('SELECT * FROM comments WHERE submission_id = ? ORDER BY created_at ASC');
        $cStmt->bindValue(1, $row['id']);
        $cResults = $cStmt->execute();
        $row['comments'] = [];
        while ($comment = $cResults->fetchArray(SQLITE3_ASSOC)) {
            $row['comments'][] = $comment;
        }
        
        $submissions[] = $row;
    }
    
    // Sort by points in results phase
    if ($phase === 'results') {
        usort($submissions, fn($a, $b) => $b['total_points'] - $a['total_points']);
    }
    
    jsonResponse([
        'round' => $round,
        'phase' => $phase,
        'submissions' => $submissions
    ]);
}

// POST - Submit a song
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $player = getPlayerName();
    $data = getJsonBody();
    
    $roundId = intval($data['round_id'] ?? 0);
    $youtubeUrl = trim($data['youtube_url'] ?? '');
    $comment = trim($data['comment'] ?? '');
    
    if ($roundId <= 0) jsonError('Round ID required');
    if (empty($youtubeUrl)) jsonError('YouTube URL required');
    
    // Validate round exists and is in submission phase
    $stmt = $db->prepare('SELECT * FROM rounds WHERE id = ?');
    $stmt->bindValue(1, $roundId);
    $round = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    if (!$round) jsonError('Round not found', 404);
    
    $phase = getRoundPhase($round);
    if ($phase !== 'submitting') jsonError('Submissions are closed for this round');
    
    // Extract YouTube ID
    $youtubeId = extractYouTubeId($youtubeUrl);
    if (!$youtubeId) jsonError('Invalid YouTube URL');
    
    // Check for duplicate YouTube ID in this round (exclude own submission for resubmit)
    $stmt = $db->prepare('SELECT id FROM submissions WHERE round_id = ? AND youtube_id = ? AND player_name != ?');
    $stmt->bindValue(1, $roundId);
    $stmt->bindValue(2, $youtubeId);
    $stmt->bindValue(3, $player);
    if ($stmt->execute()->fetchArray()) {
        jsonError('This song has already been submitted for this round');
    }
    
    // Upsert submission (replace if player already submitted)
    $stmt = $db->prepare('
        INSERT INTO submissions (round_id, player_name, youtube_url, youtube_id, comment)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(round_id, player_name) DO UPDATE SET
            youtube_url = excluded.youtube_url,
            youtube_id = excluded.youtube_id,
            comment = excluded.comment,
            created_at = datetime(\'now\')
    ');
    $stmt->bindValue(1, $roundId);
    $stmt->bindValue(2, $player);
    $stmt->bindValue(3, $youtubeUrl);
    $stmt->bindValue(4, $youtubeId);
    $stmt->bindValue(5, $comment);
    $stmt->execute();
    
    // Kick off background audio conversion
    $scriptPath = __DIR__ . '/convert.sh';
    $escapedId = escapeshellarg($youtubeId);
    exec("nohup sh $scriptPath $escapedId > /dev/null 2>&1 &");

    jsonResponse(['success' => true, 'youtube_id' => $youtubeId], 201);
}

jsonError('Method not allowed', 405);
