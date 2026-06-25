<?php
/**
 * Bundle tests: blueprint.json detection at the root or one directory deep,
 * __MACOSX handling and ambiguity/missing errors (directory bundles).
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\Bundle;
use MoodleBlueprint\Logger;
use MoodleBlueprint\SecurityPolicy;

$tmp = sys_get_temp_dir() . '/bp-bundle-' . getmypid();
@mkdir($tmp, 0700, true);
$policy = new SecurityPolicy();
$logger = new Logger();

/** Helper to create a directory with files. */
$make = function (string $dir, array $files) {
    @mkdir($dir, 0700, true);
    foreach ($files as $rel => $content) {
        $path = $dir . '/' . $rel;
        @mkdir(dirname($path), 0700, true);
        file_put_contents($path, $content);
    }
    return $dir;
};

it('detects blueprint.json at the bundle root', function () use ($make, $tmp, $policy, $logger) {
    $dir = $make($tmp . '/root-bundle', ['blueprint.json' => '{"steps":[]}']);
    $bundle = Bundle::open($policy, $dir, $tmp . '/wd1', $logger);
    assert_eq($bundle->root(), $dir);
    assert_eq($bundle->blueprintPath(), $dir . '/blueprint.json');
});

it('detects blueprint.json one directory deep, ignoring __MACOSX', function () use ($make, $tmp, $policy, $logger) {
    $dir = $make($tmp . '/deep-bundle', [
        'inner/blueprint.json' => '{"steps":[]}',
        '__MACOSX/._inner' => 'junk',
    ]);
    $bundle = Bundle::open($policy, $dir, $tmp . '/wd2', $logger);
    assert_eq($bundle->root(), $dir . '/inner');
    assert_eq($bundle->blueprintPath(), $dir . '/inner/blueprint.json');
});

it('errors on ambiguous bundles', function () use ($make, $tmp, $policy, $logger) {
    $dir = $make($tmp . '/ambiguous-bundle', [
        'a/blueprint.json' => '{"steps":[]}',
        'b/blueprint.json' => '{"steps":[]}',
    ]);
    assert_throws(BlueprintException::class, function () use ($policy, $dir, $tmp, $logger) {
        Bundle::open($policy, $dir, $tmp . '/wd3', $logger);
    }, 'Ambiguous');
});

it('errors when no blueprint.json is present', function () use ($make, $tmp, $policy, $logger) {
    $dir = $make($tmp . '/empty-bundle', ['readme.txt' => 'nothing here']);
    assert_throws(BlueprintException::class, function () use ($policy, $dir, $tmp, $logger) {
        Bundle::open($policy, $dir, $tmp . '/wd4', $logger);
    }, 'No blueprint.json');
});

it('errors when the bundle path does not exist', function () use ($tmp, $policy, $logger) {
    assert_throws(BlueprintException::class, function () use ($policy, $tmp, $logger) {
        Bundle::open($policy, $tmp . '/does-not-exist', $tmp . '/wd5', $logger);
    }, 'does not exist');
});
