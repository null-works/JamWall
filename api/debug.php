<?php
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    jsonResponse(null, 204);
}

requireAuth();

$audioDir = '/var/www/data/audio';
$logDir = "$audioDir/logs";

$action = $_GET['action'] ?? 'status';

// GET ?action=status — overview of all conversions
if ($action === 'status') {
    $entries = [];

    // Scan audio dir for known youtube IDs
    $seen = [];
    foreach (['mp3', 'lock', 'err'] as $ext) {
        $files = glob("$audioDir/*.$ext");
        if (!$files) continue;
        foreach ($files as $f) {
            $id = basename($f, ".$ext");
            if (!preg_match('/^[a-zA-Z0-9_-]{11}$/', $id)) continue;
            $seen[$id] = true;
        }
    }

    foreach (array_keys($seen) as $id) {
        $mp3 = "$audioDir/$id.mp3";
        $lock = "$audioDir/$id.lock";
        $err = "$audioDir/$id.err";
        $log = "$logDir/$id.log";

        $entry = [
            'youtube_id' => $id,
            'status' => 'unknown',
            'mp3_exists' => file_exists($mp3),
            'mp3_size' => file_exists($mp3) ? filesize($mp3) : null,
            'lock_exists' => file_exists($lock),
            'error' => file_exists($err) ? trim(file_get_contents($err)) : null,
            'has_log' => file_exists($log),
            'log_size' => file_exists($log) ? filesize($log) : null,
        ];

        if (file_exists($mp3)) {
            $entry['status'] = 'ready';
            // Get MP3 duration via ffprobe if available
            $duration = shell_exec("ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " . escapeshellarg($mp3) . " 2>/dev/null");
            $entry['duration'] = $duration ? round((float)$duration, 1) : null;
        } elseif (file_exists($lock)) {
            $entry['status'] = 'converting';
            // Check if lock is stale (older than 10 minutes)
            $lockAge = time() - filemtime($lock);
            $entry['lock_age_seconds'] = $lockAge;
            if ($lockAge > 600) {
                $entry['status'] = 'stale_lock';
            }
        } elseif (file_exists($err)) {
            $entry['status'] = 'failed';
        }

        $entries[] = $entry;
    }

    // Sort by status: failed first, then converting, then ready
    $order = ['failed' => 0, 'stale_lock' => 1, 'converting' => 2, 'unknown' => 3, 'ready' => 4];
    usort($entries, fn($a, $b) => ($order[$a['status']] ?? 5) - ($order[$b['status']] ?? 5));

    jsonResponse([
        'entries' => $entries,
        'audio_dir' => $audioDir,
        'disk_usage' => trim(shell_exec("du -sh $audioDir 2>/dev/null") ?: 'unknown'),
    ]);
}

// GET ?action=log&id=XXXXXXXXXXX — get log for a specific conversion
if ($action === 'log') {
    $id = $_GET['id'] ?? '';
    if (!preg_match('/^[a-zA-Z0-9_-]{11}$/', $id)) {
        jsonError('Invalid YouTube ID', 400);
    }

    $logFile = "$logDir/$id.log";
    if (!file_exists($logFile)) {
        jsonResponse(['log' => '(no log file found)', 'youtube_id' => $id]);
    }

    $content = file_get_contents($logFile);
    // Limit to last 50KB to avoid huge responses
    if (strlen($content) > 51200) {
        $content = "...(truncated)...\n" . substr($content, -51200);
    }

    jsonResponse(['log' => $content, 'youtube_id' => $id, 'size' => filesize($logFile)]);
}

// GET ?action=retry&id=XXXXXXXXXXX — clear error/lock and re-trigger conversion
if ($action === 'retry') {
    $id = $_GET['id'] ?? '';
    if (!preg_match('/^[a-zA-Z0-9_-]{11}$/', $id)) {
        jsonError('Invalid YouTube ID', 400);
    }

    // Clean up stale state
    @unlink("$audioDir/$id.err");
    @unlink("$audioDir/$id.lock");
    @unlink("$audioDir/$id.mp3");

    // Re-trigger conversion
    $scriptPath = __DIR__ . '/convert.sh';
    $escapedId = escapeshellarg($id);
    exec("nohup sh $scriptPath $escapedId > /dev/null 2>&1 &");

    jsonResponse(['status' => 'retrying', 'youtube_id' => $id]);
}

jsonError('Unknown action', 400);
