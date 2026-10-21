<?php
// Integration fixture: durable application data and a plugin across 4.5 -> 5.3.
define('CLI_SCRIPT', true);
require('/var/www/html/config.php');
require_once($CFG->dirroot . '/course/lib.php');
if ($argv[1] === 'seed') {
    create_course((object)['fullname' => 'Upgrade fixture', 'shortname' => 'upgrade-fixture', 'category' => 1]);
    file_put_contents($CFG->dataroot . '/upgrade-fixture.txt', 'persistent data');
    mkdir($CFG->dirroot . '/local/upgradefixture', 0777, true);
    file_put_contents($CFG->dirroot . '/local/upgradefixture/version.php',
        '<?php $plugin->component = "local_upgradefixture"; $plugin->version = 2026091600; $plugin->requires = 2024100700;');
    echo "Seeded course, data file and plugin\n";
} else {
    require($CFG->dirroot . '/version.php');
    if ($branch !== '503' || PHP_MAJOR_VERSION . PHP_MINOR_VERSION !== '84'
        || !$DB->record_exists('course', ['shortname' => 'upgrade-fixture'])
        || file_get_contents($CFG->dataroot . '/upgrade-fixture.txt') !== 'persistent data'
        || !is_file($CFG->dirroot . '/local/upgradefixture/version.php')
        || (string)get_config('local_upgradefixture', 'version') !== '2026091600') {
        throw new RuntimeException('Upgrade did not preserve/upgrade the fixture');
    }
    echo "Moodle 5.3 / PHP 8.4: course, file and installed plugin preserved\n";
}
