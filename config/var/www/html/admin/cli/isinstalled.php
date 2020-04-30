<?php
define('CLI_SCRIPT', true);
// extra execution prevention - we can not just require config.php here
if (isset($_SERVER['REMOTE_ADDR'])) {
    exit(1);
}
// Nothing to do if config.php exists
$configfile = __DIR__.'/../../config.php';
require($configfile);
if ($DB->get_tables() ) {
    // If tables exists, a previous instalation is found, so exit with error
    exit(2);
}