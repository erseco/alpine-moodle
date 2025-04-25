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

// Ensure the REDIS_HOST parameter is provided
if (!isset($argv[1])) {
    echo "Usage: php configure_redis.php <REDIS_HOST>\n";
    exit;
}

$redis_server = $argv[1];

// Check if the Redis host is up
$fp = fsockopen($redis_server, 6379, $errno, $errstr, 5);  // 5-second timeout
if (!$fp) {
    echo "Unable to connect to Redis at $redis_server:6379. Error: $errstr ($errno)\n";
    exit;
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

// Execute configuration
configure_redis_store(
    'redis1',
    'redis',
    [
        'server'     => $redis_server,
        'port'       => 6379,
        'serializer' => 2, // igbinary serializer
    ]
);
