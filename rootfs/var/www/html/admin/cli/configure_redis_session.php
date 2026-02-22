<?php
declare(strict_types=1);

define('CLI_SCRIPT', true);

// Extra execution prevention - this script must only run via CLI.
if (isset($_SERVER['REMOTE_ADDR'])) {
    exit(1);
}

if (isset($argv[1]) && in_array($argv[1], ['-h', '--help'], true)) {
    fwrite(STDOUT, "Configure Redis session settings in config.php.\n\n");
    fwrite(STDOUT, "Usage:\n");
    fwrite(STDOUT, "  php configure_redis_session.php [REDIS_HOST] [REDIS_PASSWORD] [REDIS_USER]\n\n");
    fwrite(STDOUT, "Notes:\n");
    fwrite(STDOUT, "  - If REDIS_HOST is empty or omitted, Redis session settings are removed.\n");
    fwrite(STDOUT, "  - If REDIS_USER is provided, REDIS_PASSWORD must also be provided.\n");
    exit(0);
}

$redisHost = isset($argv[1]) ? (string)$argv[1] : '';
$redisPassword = (isset($argv[2]) && $argv[2] !== '') ? (string)$argv[2] : '';
$redisUser = (isset($argv[3]) && $argv[3] !== '') ? (string)$argv[3] : '';

if ($redisUser !== '' && $redisPassword === '') {
    fwrite(STDERR, "Error: REDIS_USER requires REDIS_PASSWORD.\n");
    exit(1);
}

$configFile = __DIR__ . '/../../config.php';
if (!is_file($configFile)) {
    fwrite(STDERR, "Error: config.php not found at: {$configFile}\n");
    exit(1);
}

$contents = file_get_contents($configFile);
if ($contents === false) {
    fwrite(STDERR, "Error: Unable to read config.php.\n");
    exit(1);
}

$requirePattern = '/^\s*require_once\s*\(/m';
if (!preg_match($requirePattern, $contents, $m, PREG_OFFSET_CAPTURE)) {
    fwrite(STDERR, "Error: Could not locate require_once(...) in config.php.\n");
    exit(1);
}

$requireOffset = (int)$m[0][1];
$before = substr($contents, 0, $requireOffset);
$after = substr($contents, $requireOffset);

$keys = [
    'session_handler_class',
    'session_redis_host',
    'session_redis_serializer_use_igbinary',
    'session_redis_auth',
];

foreach ($keys as $k) {
    $before = preg_replace('/^\s*\$CFG->' . preg_quote($k, '/') . '\s*=.*;\s*$(\R)?/m', '', $before) ?? $before;
}

$lines = [];

if ($redisHost !== '') {
    $lines[] = '$CFG->session_handler_class = ' . var_export('\\core\\session\\redis', true) . ';';
    $lines[] = '$CFG->session_redis_host = ' . var_export($redisHost, true) . ';';
    $lines[] = '$CFG->session_redis_serializer_use_igbinary = ' . var_export(true, true) . ';';

    if ($redisPassword !== '') {
        $auth = $redisUser !== '' ? [$redisUser, $redisPassword] : $redisPassword;
        $lines[] = '$CFG->session_redis_auth = ' . var_export($auth, true) . ';';
    }
}

if ($before !== '' && !str_ends_with($before, "\n")) {
    $before .= "\n";
}

$insert = '';
if (!empty($lines)) {
    $insert = implode("\n", $lines) . "\n";
}

$newContents = $before . $insert . $after;
if ($newContents !== $contents) {
    $ok = file_put_contents($configFile, $newContents, LOCK_EX);
    if ($ok === false) {
        fwrite(STDERR, "Error: Unable to write updated config.php.\n");
        exit(1);
    }
}

exit(0);

