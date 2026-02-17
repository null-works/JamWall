<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();
$db = getDB();

// POST - Submit votes for a round
// Expects: { round_id, votes: [{ submission_id, points }] }
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $player = getPlayerName();
    $data = getJsonBody();
    
    $roundId = intval($data['round_id'] ?? 0);
    $votes = $data['votes'] ?? [];
    
    if ($roundId <= 0) jsonError('Round ID required');
    if (empty($votes)) jsonError('Votes are required');
    
    // Validate round is in voting phase
    $stmt = $db->prepare('SELECT * FROM rounds WHERE id = ?');
    $stmt->bindValue(1, $roundId);
    $round = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    if (!$round) jsonError('Round not found', 404);
    
    $phase = getRoundPhase($round);
    if ($phase !== 'voting') jsonError('Voting is not open for this round');
    
    // Validate total points don't exceed limit
    $totalPoints = array_sum(array_column($votes, 'points'));
    if ($totalPoints > $round['vote_points']) {
        jsonError("You can only distribute {$round['vote_points']} points total");
    }
    
    // Can't vote for own submission
    $stmt = $db->prepare('SELECT id FROM submissions WHERE round_id = ? AND player_name = ?');
    $stmt->bindValue(1, $roundId);
    $stmt->bindValue(2, $player);
    $ownSubmission = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    $ownId = $ownSubmission ? $ownSubmission['id'] : -1;
    
    // Begin transaction
    $db->exec('BEGIN TRANSACTION');
    
    try {
        // Clear existing votes for this round by this player
        $stmt = $db->prepare('
            DELETE FROM votes WHERE voter_name = ? AND submission_id IN 
            (SELECT id FROM submissions WHERE round_id = ?)
        ');
        $stmt->bindValue(1, $player);
        $stmt->bindValue(2, $roundId);
        $stmt->execute();
        
        // Insert new votes
        foreach ($votes as $vote) {
            $subId = intval($vote['submission_id']);
            $points = intval($vote['points']);
            
            if ($points <= 0) continue;
            if ($subId === $ownId) {
                $db->exec('ROLLBACK');
                jsonError("You can't vote for your own submission");
            }
            
            // Verify submission belongs to this round
            $stmt = $db->prepare('SELECT id FROM submissions WHERE id = ? AND round_id = ?');
            $stmt->bindValue(1, $subId);
            $stmt->bindValue(2, $roundId);
            if (!$stmt->execute()->fetchArray()) {
                $db->exec('ROLLBACK');
                jsonError("Invalid submission ID: $subId");
            }
            
            $stmt = $db->prepare('INSERT INTO votes (submission_id, voter_name, points) VALUES (?, ?, ?)');
            $stmt->bindValue(1, $subId);
            $stmt->bindValue(2, $player);
            $stmt->bindValue(3, $points);
            $stmt->execute();
        }
        
        $db->exec('COMMIT');
        jsonResponse(['success' => true]);
        
    } catch (Exception $e) {
        $db->exec('ROLLBACK');
        jsonError('Failed to save votes: ' . $e->getMessage(), 500);
    }
}

jsonError('Method not allowed', 405);
