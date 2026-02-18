<?php
// Database connection and shared utilities

if (!defined('DB_PATH')) define('DB_PATH', '/var/www/data/jamwall.sqlite');
if (!defined('SCHEMA_PATH')) define('SCHEMA_PATH', '/var/www/data/schema.sql');

function getDB(): SQLite3 {
    static $instance = null;
    if ($instance !== null) {
        return $instance;
    }

    $isNew = !file_exists(DB_PATH);
    $db = new SQLite3(DB_PATH);
    $db->enableExceptions(true);
    $db->exec('PRAGMA journal_mode=WAL');
    $db->exec('PRAGMA foreign_keys=ON');

    if ($isNew) {
        $schema = file_get_contents(SCHEMA_PATH);
        $db->exec($schema);
    }

    $instance = $db;
    return $db;
}

function jsonResponse($data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, X-Password, X-Player');
    
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
    
    echo json_encode($data);
    exit;
}

function jsonError(string $message, int $code = 400): void {
    jsonResponse(['error' => $message], $code);
}

function getJsonBody(): array {
    $body = file_get_contents('php://input');
    $data = json_decode($body, true);
    return $data ?: [];
}

function requireAuth(): void {
    $db = getDB();
    $password = $_SERVER['HTTP_X_PASSWORD'] ?? '';
    
    $stmt = $db->prepare('SELECT value FROM settings WHERE key = ?');
    $stmt->bindValue(1, 'password');
    $result = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
    
    if (!$result || $password !== $result['value']) {
        jsonError('Invalid password', 401);
    }
}

function getPlayerName(): string {
    $name = trim($_SERVER['HTTP_X_PLAYER'] ?? '');
    if (empty($name)) {
        jsonError('Player name required', 400);
    }
    return $name;
}

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
