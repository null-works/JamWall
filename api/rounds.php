<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();
$db = getDB();

// GET - List all rounds with metadata
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $rounds = [];
    $results = $db->query('SELECT * FROM rounds ORDER BY created_at DESC');
    
    while ($row = $results->fetchArray(SQLITE3_ASSOC)) {
        $row['phase'] = getRoundPhase($row);
        
        // Count submissions
        $stmt = $db->prepare('SELECT COUNT(*) as count FROM submissions WHERE round_id = ?');
        $stmt->bindValue(1, $row['id']);
        $row['submission_count'] = $stmt->execute()->fetchArray(SQLITE3_ASSOC)['count'];
        
        // Count unique voters
        $stmt = $db->prepare('
            SELECT COUNT(DISTINCT voter_name) as count 
            FROM votes v 
            JOIN submissions s ON v.submission_id = s.id 
            WHERE s.round_id = ?
        ');
        $stmt->bindValue(1, $row['id']);
        $row['voter_count'] = $stmt->execute()->fetchArray(SQLITE3_ASSOC)['count'];
        
        $rounds[] = $row;
    }
    
    jsonResponse($rounds);
}

// POST - Create a new round
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $player = getPlayerName();
    $data = getJsonBody();
    
    $title = trim($data['title'] ?? '');
    $description = trim($data['description'] ?? '');
    $submissionDeadline = $data['submission_deadline'] ?? '';
    $votingDeadline = $data['voting_deadline'] ?? '';
    $votePoints = intval($data['vote_points'] ?? 10);
    
    if (empty($title)) jsonError('Round title is required');
    if (empty($submissionDeadline)) jsonError('Submission deadline is required');
    if (empty($votingDeadline)) jsonError('Voting deadline is required');
    if ($votingDeadline <= $submissionDeadline) jsonError('Voting deadline must be after submission deadline');
    
    $stmt = $db->prepare('
        INSERT INTO rounds (title, description, submission_deadline, voting_deadline, vote_points, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ');
    $stmt->bindValue(1, $title);
    $stmt->bindValue(2, $description);
    $stmt->bindValue(3, $submissionDeadline);
    $stmt->bindValue(4, $votingDeadline);
    $stmt->bindValue(5, $votePoints);
    $stmt->bindValue(6, $player);
    $stmt->execute();
    
    $id = $db->lastInsertRowID();
    
    $stmt = $db->prepare('SELECT * FROM rounds WHERE id = ?');
    $stmt->bindValue(1, $id);
    $round = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    $round['phase'] = getRoundPhase($round);
    $round['submission_count'] = 0;
    $round['voter_count'] = 0;
    
    jsonResponse($round, 201);
}

// DELETE - Remove a round
if ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
    $id = intval($_GET['id'] ?? 0);
    if ($id <= 0) jsonError('Round ID required');
    
    $stmt = $db->prepare('DELETE FROM rounds WHERE id = ?');
    $stmt->bindValue(1, $id);
    $stmt->execute();
    
    jsonResponse(['success' => true]);
}

jsonError('Method not allowed', 405);
