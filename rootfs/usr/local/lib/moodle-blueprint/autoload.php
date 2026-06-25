<?php
// Minimal PSR-4-style autoloader for the Moodle blueprint runner.
//
// All runner classes live under the `MoodleBlueprint\` namespace and are
// resolved relative to this file's directory, so the same library works both
// inside the container (/usr/local/lib/moodle-blueprint) and from the test
// harness on a developer machine without any code changes.

spl_autoload_register(static function ($class) {
    $prefix = 'MoodleBlueprint\\';
    if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
        return;
    }

    $relative = substr($class, strlen($prefix));
    $relative = str_replace('\\', '/', $relative);
    $file = __DIR__ . '/' . $relative . '.php';

    if (is_file($file)) {
        require $file;
    }
});
