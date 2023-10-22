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
        'help' => false,
        'username' => '',
        'password' => '',
        'email' => '',
    ),
    array(
        'h' => 'help',
        'u' => 'username',
        'p' => 'password',
        'e' => 'email',
    )
);

if ($options['help']) {
    $help =
"Update admin username, password and email.

Options:
-h, --help            Print out this help
-u, --username        New admin username
-p, --password        New admin password
-e, --email           New admin email

Example:
\$sudo -u www-data /usr/bin/php admin/cli/update_admin_user.php --username=newadmin --password=newpassword --email=newemail@example.com";
    echo $help;
    die;
}

if (empty($options['username']) || empty($options['password']) || empty($options['email'])) {
    cli_error('Username, password, and email must all be specified.');
}

$new_username = $options['username'];
$new_password = $options['password'];
$new_email = $options['email'];

$admin_user = get_admin();
if ($admin_user) {
    $admin_user->username = $new_username;
    $admin_user->password = hash_internal_user_password($new_password);
    $admin_user->email = $new_email;
    $success = $DB->update_record('user', $admin_user);
    if ($success) {
        echo "Admin username, password, and email updated successfully.\n";
    } else {
        echo "Failed to update admin username, password, and email.\n";
    }
} else {
    echo "Admin user not found.\n";
}
