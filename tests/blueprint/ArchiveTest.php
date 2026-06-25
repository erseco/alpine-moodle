<?php
/**
 * Archive tests: ZIP-slip protection, __MACOSX handling and normal extraction.
 * Skipped automatically when the PHP zip extension is unavailable.
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\Archive;
use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\SecurityPolicy;

if (!class_exists('ZipArchive')) {
    fwrite(STDOUT, "  skip - ZipArchive not available; archive tests skipped\n");
    return;
}

$tmp = sys_get_temp_dir() . '/bp-zip-' . getmypid();
@mkdir($tmp, 0700, true);
$policy = new SecurityPolicy();

it('extracts a normal archive safely', function () use ($tmp, $policy) {
    $zipPath = $tmp . '/good.zip';
    $zip = new ZipArchive();
    $zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE);
    $zip->addFromString('mod_demo/version.php', "<?php // version\n");
    $zip->addFromString('mod_demo/lib.php', "<?php // lib\n");
    $zip->close();

    $dest = $tmp . '/good-out';
    Archive::extract($policy, $zipPath, $dest);
    assert_true(is_file($dest . '/mod_demo/version.php'), 'version.php extracted');
    assert_true(is_file($dest . '/mod_demo/lib.php'), 'lib.php extracted');
});

it('rejects a ZIP-slip archive', function () use ($tmp, $policy) {
    $zipPath = $tmp . '/evil.zip';
    $zip = new ZipArchive();
    $zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE);
    $zip->addFromString('../../escape.txt', "owned\n");
    $zip->close();

    $dest = $tmp . '/evil-out';
    assert_throws(BlueprintException::class, function () use ($policy, $zipPath, $dest) {
        Archive::extract($policy, $zipPath, $dest);
    });
    assert_true(!is_file($tmp . '/escape.txt'), 'no file written outside dest');
    assert_true(!is_file(dirname($tmp) . '/escape.txt'), 'no file written above tmp');
});

it('ignores __MACOSX metadata entries', function () use ($tmp, $policy) {
    $zipPath = $tmp . '/mac.zip';
    $zip = new ZipArchive();
    $zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE);
    $zip->addFromString('__MACOSX/._foo', "junk\n");
    $zip->addFromString('real.txt', "content\n");
    $zip->close();

    $dest = $tmp . '/mac-out';
    Archive::extract($policy, $zipPath, $dest);
    assert_true(is_file($dest . '/real.txt'), 'real file extracted');
    assert_true(!is_dir($dest . '/__MACOSX'), '__MACOSX ignored');
});
