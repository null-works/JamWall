<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();
$db = getDB();

// POST - Add a comment to a submission
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $player = getPlayerName();
    $data = getJsonBody();
    
    $submissionId = intval($data['submission_id'] ?? 0);
    $comment = trim($data['comment'] ?? '');
    
    if ($submissionId <= 0) jsonError('Submission ID required');
    if (empty($comment)) jsonError('Comment text required');
    
    // Verify submission exists
    $stmt = $db->prepare('SELECT s.*, r.voting_deadline FROM submissions s JOIN rounds r ON s.round_id = r.id WHERE s.id = ?');
    $stmt->bindValue(1, $submissionId);
    $sub = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    if (!$sub) jsonError('Submission not found', 404);
    
    $stmt = $db->prepare('INSERT INTO comments (submission_id, player_name, comment) VALUES (?, ?, ?)');
    $stmt->bindValue(1, $submissionId);
    $stmt->bindValue(2, $player);
    $stmt->bindValue(3, $comment);
    $stmt->execute();
    
    jsonResponse([
        'success' => true,
        'id' => $db->lastInsertRowID(),
        'player_name' => $player,
        'comment' => $comment,
        'created_at' => date('c')
    ], 201);
}

jsonError('Method not allowed', 405);
