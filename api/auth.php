<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonError('Method not allowed', 405);
}

$data = getJsonBody();
$password = $data['password'] ?? '';

$db = getDB();
$stmt = $db->prepare('SELECT value FROM settings WHERE key = ?');
$stmt->bindValue(1, 'password');
$result = $stmt->execute()->fetchArray(SQLITE3_ASSOC);

if ($result && $password === $result['value']) {
    // Also return league name
    $stmt2 = $db->prepare('SELECT value FROM settings WHERE key = ?');
    $stmt2->bindValue(1, 'league_name');
    $nameResult = $stmt2->execute()->fetchArray(SQLITE3_ASSOC);
    
    jsonResponse([
        'success' => true,
        'league_name' => $nameResult['value'] ?? 'JamWall'
    ]);
} else {
    jsonError('Wrong password', 401);
}
