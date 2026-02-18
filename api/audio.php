<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();

$ytId = $_GET['id'] ?? '';
if (!preg_match('/^[a-zA-Z0-9_-]{11}$/', $ytId)) {
    jsonError('Invalid YouTube ID', 400);
}

$audioDir = '/var/www/data/audio';
$mp3Path = "$audioDir/$ytId.mp3";
$lockPath = "$audioDir/$ytId.lock";
$errPath = "$audioDir/$ytId.err";

// Already converted — but verify the file isn't truncated/empty
if (file_exists($mp3Path)) {
    $size = filesize($mp3Path);
    if ($size > 5242880) { // > 5MB = valid
        jsonResponse(['status' => 'ready', 'url' => "/audio/$ytId.mp3"]);
    }
    // Truncated file — delete and reconvert
    @unlink($mp3Path);
    @unlink($errPath);
}

// Previous conversion failed — report it (debug tab can retry)
if (file_exists($errPath)) {
    $errMsg = trim(file_get_contents($errPath));
    jsonResponse(['status' => 'failed', 'error' => $errMsg]);
}

// Currently converting
if (file_exists($lockPath)) {
    jsonResponse(['status' => 'converting']);
}

// Kick off background conversion
if (!is_dir($audioDir)) {
    mkdir($audioDir, 0755, true);
}

$scriptPath = __DIR__ . '/convert.sh';
$escapedId = escapeshellarg($ytId);
exec("nohup sh $scriptPath $escapedId > /dev/null 2>&1 &");

jsonResponse(['status' => 'converting']);
