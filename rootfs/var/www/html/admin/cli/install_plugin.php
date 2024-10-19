<?php
define('CLI_SCRIPT', true);

require(__DIR__ . '/../../config.php');
require_once($CFG->libdir . '/clilib.php');
require_once($CFG->libdir . '/adminlib.php');
require_once($CFG->libdir . '/upgradelib.php');

$help = "Command line tool to install or update plugins.

Options:
    -h --help                   Print this help.
    --plugin=<pluginname>       The name of the plugin to install.
    --url=<pluginurl>           The URL to download the plugin from.
    --type=<plugintype>         The type of the plugin (e.g., mod, block, filter, theme, local). Defaults to mod.
    --run                       Execute install. If this option is not set, the script will run in dry mode.
    --force                     Force install even if plugin exists (useful for development).
    --debug                     Enable debug mode to see detailed error messages.
    --showsql                   Show SQL queries before they are executed.
    --showdebugging             Show developer level debugging information.

Examples:
    # php install_plugin.php --plugin=mod_assign
        Dry run of installing mod_assign plugin.

    # php install_plugin.php --plugin=mod_assign --run
        Run install of mod_assign plugin.

    # php install_plugin.php --url=https://example.com/plugin.zip --run
        Download and install plugin from URL.
";

list($options, $unrecognised) = cli_get_params([
    'help' => false,
    'plugin' => false,
    'url' => false,
    'type' => 'mod', // Default plugin type
    'run' => false,
    'force' => false,
    'showsql' => false,
    'debug' => false,
    'showdebugging' => false,
], [
    'h' => 'help'
]);

if ($unrecognised) {
    $unrecognised = implode(PHP_EOL . '  ', $unrecognised);
    cli_error(get_string('cliunknowoption', 'core_admin', $unrecognised));
}

if ($options['debug']) {
    set_debugging(DEBUG_DEVELOPER, true);
    cli_writeln('Debug mode enabled.');
}

if ($options['help']) {
    cli_writeln($help);
    exit(0);
}

if ($options['showdebugging']) {
    set_debugging(DEBUG_DEVELOPER, true);
}

if ($options['showsql']) {
    $DB->set_debug(true);
}

if (!$options['plugin'] && !$options['url']) {
    cli_writeln('You must specify either a plugin name or a URL.');
    cli_writeln($help);
    exit(0);
}

$pluginman = \core\plugin_manager::instance();

$plugins = [];
if ($options['url']) {
    $pluginurl = $options['url'];
    $tempdir = make_request_directory();

    cli_writeln("Downloading plugin from $pluginurl...");
    $tempfile = download_and_extract_plugin($pluginurl, $tempdir);

    if (!$tempfile) {
        cli_error('Failed to download or extract plugin.');
    }

    cli_writeln('Plugin downloaded and extracted.');

    // Detect the plugin directory
    $rootdir = $pluginman->get_plugin_zip_root_dir($tempfile);
    if (!$rootdir) {
        cli_error('Failed to detect plugin directory.');
    }

    // Verificar el directorio esperado
    if (!is_dir("$tempdir/$rootdir")) {
        cli_error('Extracted plugin directory does not exist: ' . "$tempdir/$rootdir");
    }

    $pluginname = detect_plugin_name("$tempdir/$rootdir");
    if (!$pluginname) {
        cli_error('Failed to detect plugin name.');
    }

    $destination = detect_and_move_plugin($pluginname, "$tempdir/$rootdir", $options['type']);
    if (!$destination) {
        cli_error('Failed to move plugin to the correct directory.');
    }

    $destination = detect_and_move_plugin($pluginname, $pluginDir, $options['type']);
    if (!$destination) {
        cli_error('Failed to move plugin to the correct directory.');
    }

    $plugins[] = (object)[
        'component' => $pluginname,
        'zipfilepath' => $tempfile,
    ];
} else {
    $pluginDir = $CFG->dirroot . '/mod/' . $options['plugin'];

    $plugininfo = get_plugin_info_from_version_file($pluginDir);
    if (!$plugininfo) {
        cli_error('Invalid plugin directory: ' . $pluginDir);
    }

    $pluginname = $plugininfo->component;
    cli_writeln("Preparing to install plugin: $pluginname");

    // Check if the plugin is already installed, unless forced
    if ($pluginman->get_plugin_info($pluginname) && !$options['force']) {
        cli_error("Plugin $pluginname is already installed. Use --force to reinstall.");
    }

    $plugins[] = (object)[
        'component' => $pluginname,
        'zipfilepath' => null,
    ];
}

if ($options['run']) {
    cli_writeln('Installing plugin...');

    // Use the install_plugins function to handle the installation
    if ($pluginman->install_plugins($plugins, true, false)) {
        cli_writeln('Plugin installed successfully.');
    } else {
        cli_error('Failed to install plugin.');
    }

    // Run the Moodle upgrade script
    upgrade_noncore(true);
    \core\session\manager::gc(); // Clean up sessions
    exit(0);
} else {
    cli_writeln('Dry run complete. Use --run to install the plugin.');
    exit(0);
}

/**
 * Download and extract the plugin from the given URL.
 *
 * @param string $url The URL to download the plugin from.
 * @param string $tempdir The temporary directory to extract the plugin to.
 * @return string|bool The path to the extracted plugin or false on failure.
 */
function download_and_extract_plugin($url, $tempdir) {
    $zipfile = "$tempdir/plugin.zip";

    // Descargar el archivo
    if (!download_file($url, $zipfile)) {
        return false;
    }

    // Extraer el archivo
    $zip = new ZipArchive;
    if ($zip->open($zipfile) === true) {
        $zip->extractTo($tempdir);
        $zip->close();
    } else {
        return false;
    }

    return $zipfile;
}

/**
 * Get plugin info from version.php file in the plugin directory.
 *
 * @param string $pluginDir Path to the plugin directory.
 * @return stdClass|null Plugin info object or null if invalid.
 */
function get_plugin_info_from_version_file($pluginDir) {
    $versionFile = $pluginDir . '/version.php';
    if (!file_exists($versionFile)) {
        return null;
    }

    // Create a new stdClass object to hold the plugin info.
    $plugin = new stdClass();

    // Include the version file to get the $plugin array.
    include($versionFile);

    if (!isset($plugin->component)) {
        return null;
    }

    return (object)[
        'component' => $plugin->component,
        'version' => $plugin->version,
        'requires' => $plugin->requires,
        'release' => $plugin->release,
        'maturity' => $plugin->maturity,
    ];
}

/**
 * Detect the plugin name from the extracted plugin directory.
 *
 * @param string $dir Path to the extracted plugin directory.
 * @return string|bool The plugin name or false on failure.
 */
function detect_plugin_name($dir) {
    $versionFile = $dir . '/version.php';
    if (!file_exists($versionFile)) {
        return false;
    }

    $plugin = new stdClass();
    include($versionFile);

    if (!isset($plugin->component)) {
        return false;
    }

    return $plugin->component;
}

/**
 * Detect the plugin type and move to the correct directory.
 * 
 * @param string $pluginname Name of the plugin.
 * @param string $sourcepath Path to the extracted plugin.
 * @param string $type The type of the plugin.
 * @return bool|string Returns the new path of the plugin if successful, or false on failure.
 */
function detect_and_move_plugin($pluginname, $sourcepath, $type) {
    global $CFG;

    // Define the base paths for different plugin types
    $plugin_types = [
        'mod' => $CFG->dirroot . '/mod/',
        'block' => $CFG->dirroot . '/blocks/',
        'filter' => $CFG->dirroot . '/filter/',
        'theme' => $CFG->dirroot . '/theme/',
        // Add other plugin types as needed
    ];

    // Use the provided type to determine the destination path
    if (array_key_exists($type, $plugin_types)) {
        $destination = $plugin_types[$type] . basename($sourcepath);

        // Ensure the directory is writable before moving the plugin
        if (!is_writable($destination)) {
            cli_error("Directory $destination is not writable. Check permissions.");
        }

        // Move the plugin to the correct directory
        if (rename($sourcepath, $destination)) {
            cli_writeln("Plugin moved to $destination.");
            return $destination;
        } else {
            return false;
        }
    }

    // If the plugin type is not recognized
    cli_error("Unknown plugin type: $type. Plugin was not moved.");
    return false;
}

