<?php
// Exit codes (checked by 02-configure-moodle.sh):
//   0 = Moodle bootstraps but the database has no tables yet (not installed)
//   2 = database tables exist (already installed)
//   anything else = the check itself could not run (bad bootstrap, DB down…)
define('CLI_SCRIPT', true);
// extra execution prevention - we can not just require config.php here
if (isset($_SERVER['REMOTE_ADDR'])) {
    exit(1);
}
// This helper lives in the image (outside the volume-shadowed Moodle tree),
// so it must bootstrap Moodle from the runtime document root explicitly.
$moodleroot = getenv('MOODLE_HTML_DIR') ?: '/var/www/html';
require($moodleroot . '/config.php');
if ($DB->get_tables() ) {
    // If tables exists, a previous instalation is found, so exit with error
    exit(2);
}