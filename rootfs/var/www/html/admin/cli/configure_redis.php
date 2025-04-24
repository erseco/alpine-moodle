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

$cache = cache_config::instance();
$stores = $cache->get_all_stores();

// Check if the 'redis1' configuration already exists
if (array_key_exists('redis1', $stores)) {
    echo "Configuration 'redis1' already exists. Exiting.\n";
    exit;
}

// Include cache libraries
// require_once($CFG->dirroot.'/cache/classes/config_writer.php');
require_once($CFG->dirroot.'/cache/locallib.php');

// Get an instance of the cache_config_writer class
$writer = cache_config_writer::instance();

// Define the configuration for the new Redis cache store instance
$name = 'redis1';  // Choose a unique name for this instance
$plugin = 'redis';  // The name of the cache store plugin
$configuration = array(
    'server' => $redis_server,
    'port' => 6379,
    'serializer' => 2, // The faster igbinary serializer
);

// Try to add the new Redis cache store instance
try {
    $writer->add_store_instance($name, $plugin, $configuration);
    mtrace("Instance '{$name}' has been added successfully.");

    // Prepare mode mappings
    $mode_mappings = array(
        cache_store::MODE_APPLICATION => array('redis1'),
        cache_store::MODE_SESSION => array('redis1'),
        cache_store::MODE_REQUEST => array('default_request'),
    );

    // Set mode mappings
    $writer->set_mode_mappings($mode_mappings);
    mtrace("Mode mappings have been updated successfully.");

} catch (cache_exception $e) {
    mtrace("Error adding cache instance: " . $e->getMessage());
}
