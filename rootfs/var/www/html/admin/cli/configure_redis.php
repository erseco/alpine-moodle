<?php

// Ensure this script is being run via CLI
define('CLI_SCRIPT', true);

// Extra execution prevention - we cannot just require config.php here
if (isset($_SERVER['REMOTE_ADDR'])) {
    exit(1);
}

// Include Moodle configuration
$configfile = __DIR__.'/../../config.php';
require($configfile);

// Include CLI libraries
require_once($CFG->libdir.'/clilib.php');

$help = "Configure Redis cache store.\n\n".
    "Usage:\n".
    "  php configure_redis.php <REDIS_HOST> [REDIS_PASSWORD] [REDIS_USER]\n".
    "  php configure_redis.php --host=<REDIS_HOST> [--password=<REDIS_PASSWORD>] [--user=<REDIS_USER>]\n\n".
    "Notes:\n".
    "  - If REDIS_USER/--user is provided, REDIS_PASSWORD/--password must also be provided.\n";

$hasoptions = isset($argv[1]) && is_string($argv[1]) && $argv[1] !== '' && $argv[1][0] === '-';

$redis_server = '';
$redis_password = '';
$redis_user = '';

if ($hasoptions) {
    list($options, $unrecognized) = cli_get_params(
        [
            'help' => false,
            'host' => '',
            'password' => '',
            'user' => '',
        ],
        [
            'h' => 'help',
        ]
    );

    if (!empty($unrecognized)) {
        cli_error("Unrecognized option(s): ".implode(' ', $unrecognized)."\n\n".$help);
    }

    if ($options['help']) {
        echo $help;
        exit(0);
    }

    $redis_server = (string)$options['host'];
    $redis_password = (string)$options['password'];
    $redis_user = (string)$options['user'];
} else {
    if (!isset($argv[1]) || $argv[1] === '') {
        cli_error($help);
    }
    $redis_server = (string)$argv[1];
    $redis_password = (isset($argv[2]) && $argv[2] !== '') ? (string)$argv[2] : '';
    $redis_user = (isset($argv[3]) && $argv[3] !== '') ? (string)$argv[3] : '';
}

if ($redis_user !== '' && $redis_password === '') {
    cli_error('REDIS_USER requires REDIS_PASSWORD.');
}

// Check if the Redis host is up
$fp = fsockopen($redis_server, 6379, $errno, $errstr, 5);  // 5-second timeout
if (!$fp) {
    cli_error("Unable to connect to Redis at {$redis_server}:6379. Error: {$errstr} ({$errno})");
}
fclose($fp);


/**
 * Configure Redis cache store and mode mappings.
 *
 * @param string $name          Unique name for this instance.
 * @param string $plugin        Cache store plugin name.
 * @param array  $configuration Plugin-specific settings.
 * @return void
 */
function configure_redis_store($name, $plugin, array $configuration) {
    global $CFG;

    // Include classes for modern Moodle versions
    if (file_exists($CFG->dirroot . '/cache/classes/config_writer.php')) {
        require_once($CFG->dirroot . '/cache/classes/config_writer.php');
    }
    // Fallback for older Moodle LTS versions
    elseif (file_exists($CFG->dirroot . '/cache/locallib.php')) {
        require_once($CFG->dirroot . '/cache/locallib.php');
    } else {
        mtrace("Cache library not found. Skipping Redis configuration.");
        return;
    }

    // Get writer instance if available
    if (!class_exists('cache_config_writer')) {
        mtrace("Cache config writer class not available. Skipping Redis configuration.");
        return;
    }

    $writer = cache_config_writer::instance();

    // Add new store instance if it does not exist
    $existing = cache_config::instance()->get_all_stores();
    if (array_key_exists($name, $existing)) {
        mtrace("Store instance '{$name}' already exists. Nothing to do.");
        return;
    }

    try {
        $writer->add_store_instance($name, $plugin, $configuration);
        mtrace("Instance '{$name}' added successfully.");

        // Define mode mappings
        $modes = [
            cache_store::MODE_APPLICATION => [$name],
            cache_store::MODE_SESSION     => [$name],
            cache_store::MODE_REQUEST     => ['default_request'],
        ];
        $writer->set_mode_mappings($modes);
        mtrace("Mode mappings updated successfully.");
    } catch (cache_exception $e) {
        mtrace("Error adding cache instance: " . $e->getMessage());
    }
}

// Build cache store configuration
$config = [
    'server'     => $redis_server,
    'port'       => 6379,
    'serializer' => 2, // igbinary serializer
];

if ($redis_password !== '') {
    $config['password'] = $redis_user !== '' ? [$redis_user, $redis_password] : $redis_password;
}

configure_redis_store('redis1', 'redis', $config);
