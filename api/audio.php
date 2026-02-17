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

// Already converted
if (file_exists($mp3Path)) {
    jsonResponse(['status' => 'ready', 'url' => "/audio/$ytId.mp3"]);
}

// Previous conversion failed — retry
if (file_exists($errPath)) {
    unlink($errPath);
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
