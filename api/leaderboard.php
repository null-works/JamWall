<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();
$db = getDB();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    // Overall leaderboard: total points across all completed rounds
    $results = $db->query('
        SELECT 
            s.player_name,
            COALESCE(SUM(v.points), 0) as total_points,
            COUNT(DISTINCT s.round_id) as rounds_played,
            COUNT(DISTINCT CASE WHEN v.points > 0 THEN s.round_id END) as rounds_scored
        FROM submissions s
        LEFT JOIN votes v ON v.submission_id = s.id
        JOIN rounds r ON s.round_id = r.id
        WHERE r.voting_deadline < datetime(\'now\')
        GROUP BY s.player_name
        ORDER BY total_points DESC
    ');
    
    $leaderboard = [];
    $rank = 1;
    while ($row = $results->fetchArray(SQLITE3_ASSOC)) {
        $row['rank'] = $rank++;
        $leaderboard[] = $row;
    }
    
    // Also get per-round breakdowns
    $roundResults = [];
    $rounds = $db->query('SELECT * FROM rounds WHERE voting_deadline < datetime(\'now\') ORDER BY created_at DESC');
    while ($round = $rounds->fetchArray(SQLITE3_ASSOC)) {
        $stmt = $db->prepare('
            SELECT s.player_name, s.video_title, s.youtube_id, COALESCE(SUM(v.points), 0) as points
            FROM submissions s
            LEFT JOIN votes v ON v.submission_id = s.id
            WHERE s.round_id = ?
            GROUP BY s.id
            ORDER BY points DESC
        ');
        $stmt->bindValue(1, $round['id']);
        $subs = $stmt->execute();
        
        $roundSubs = [];
        while ($sub = $subs->fetchArray(SQLITE3_ASSOC)) {
            $roundSubs[] = $sub;
        }
        
        $roundResults[] = [
            'round' => $round,
            'results' => $roundSubs
        ];
    }
    
    jsonResponse([
        'leaderboard' => $leaderboard,
        'round_results' => $roundResults
    ]);
}

jsonError('Method not allowed', 405);
