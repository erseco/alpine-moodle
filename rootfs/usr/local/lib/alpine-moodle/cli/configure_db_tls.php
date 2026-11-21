<?php

[, $action, $path] = $argv;

if ($action === 'generate') {
    // install_database.php checks the environment and installs the schema from this config.
    $config = "<?php\n\nunset(\$CFG);\nglobal \$CFG;\n\$CFG = new stdClass();\n";
    $settings = [
        'dbtype' => getenv('DB_TYPE'),
        'dblibrary' => 'native',
        'dbhost' => getenv('DB_HOST'),
        'dbname' => getenv('DB_NAME'),
        'dbuser' => getenv('DB_USER'),
        'dbpass' => getenv('DB_PASS'),
        'prefix' => getenv('DB_PREFIX'),
        'dboptions' => ['dbpersist' => 0, 'dbport' => getenv('DB_PORT'), 'dbsocket' => ''],
        'wwwroot' => getenv('SITE_URL'),
        'dataroot' => '/var/www/moodledata/',
        'admin' => 'admin',
        'directorypermissions' => 02777,
    ];
    foreach ($settings as $key => $value) {
        $config .= "\$CFG->$key = " . var_export($value, true) . ";\n";
    }
    $config .= "\nrequire_once(__DIR__ . '/lib/setup.php');\n";
} else {
    $mode = $argv[3] ?? '';
    if (!in_array($mode, ['require', 'verify-full'], true)) {
        fwrite(STDERR, "ERROR: DB_SSL must be require, verify-full, or empty.\n");
        exit(1);
    }
    $original = file_get_contents($path);
    if ($original === false) {
        exit(1);
    }

    // Keep the override on the bootstrap line so startup's other config edits cannot separate them.
    $setting = static fn ($mode) => "\$CFG->dboptions = ['ssl' => '$mode'] + (\$CFG->dboptions ?? []); ";
    $previous = null;
    foreach (PhpToken::tokenize($original, TOKEN_PARSE) as $token) {
        if ($token->isIgnorable()) {
            continue;
        }
        $statement = $previous === null || $previous->is([';', '{', '}']);
        $previous = $token;
        if (!$statement || !$token->is([T_REQUIRE, T_REQUIRE_ONCE])) {
            continue;
        }
        $bootstrap = substr($original, $token->pos);
        if (!preg_match('~^require(?:_once)?\s*\(?\s*__DIR__\s*\.\s*([\x27"])/(?:public/)?lib/setup\.php\1\s*\)?\s*;~i', $bootstrap)) {
            continue;
        }
        $before = substr($original, 0, $token->pos);
        foreach (['require', 'verify-full'] as $oldmode) {
            if (str_ends_with($before, $setting($oldmode))) {
                $before = substr($before, 0, -strlen($setting($oldmode)));
                break;
            }
        }
        $config = $before . $setting($mode) . $bootstrap;
        break;
    }
    if (!isset($config)) {
        fwrite(STDERR, "ERROR: DB_SSL could not locate Moodle's setup.php require in $path.\n");
        exit(1);
    }
    if ($config === $original) {
        exit(0);
    }
}

PhpToken::tokenize($config, TOKEN_PARSE);
$temporary = tempnam(dirname($path), '.db-tls-');
if ($temporary === false) {
    exit(1);
}
try {
    $written = file_put_contents($temporary, $config) === strlen($config) && rename($temporary, $path);
} finally {
    if (is_file($temporary)) {
        unlink($temporary);
    }
}
exit($written ? 0 : 1);
