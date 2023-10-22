<?php

define('CLI_SCRIPT', true);
// extra execution prevention - we can not just require config.php here
if (isset($_SERVER['REMOTE_ADDR'])) {
    exit(1);
}
// Nothing to do if config.php exists
$configfile = __DIR__.'/../../config.php';
require($configfile);

require_once($CFG->libdir.'/clilib.php');

list($options, $unrecognized) = cli_get_params(
    array(
        'help'        => false,
        'user'        => false,
        'courseid'    => false,
        'role'        => 'student',
    ),
    array(
        'h' => 'help',
        'u' => 'user',
        'c' => 'courseid',
        'r' => 'role',
    )
);

if ($options['help'] || empty($options['user']) || empty($options['courseid'])) {
    $help = "Enroll a user in a course.

Options:
-h, --help            Print out this help
-u, --user            Username of the user
-c, --courseid        ID of the course
-r, --role            Role of the user in the course (default is student)

Example:
\$sudo -u www-data /usr/bin/php admin/enrol.php --user=moodleuser --courseid=2 --role=student";
    echo $help;
    die;
}

// Check for missing values and print error messages.
if ($options['username'] === false) {
    cli_error('Error: Missing username. Use --username to specify the username.');
}

if ($options['courseid'] === false) {
    cli_error('Error: Missing course ID. Use --courseid to specify the course ID.');
}

$username   = $options['user'];
$courseid   = $options['courseid'];
$rolename   = $options['role'];

$user = $DB->get_record('user', array('username' => $username), '*', MUST_EXIST);
$course = $DB->get_record('course', array('id' => $courseid), '*', MUST_EXIST);
$role = $DB->get_record('role', array('shortname' => $rolename), '*', MUST_EXIST);

$context = context_course::instance($course->id);

role_assign($role->id, $user->id, $context->id);

echo "User '{$username}' has been enrolled in course '{$course->fullname}' as a '{$rolename}'.\n";
