<?php
/**
 * BlueprintRunner tests covering source selection, idempotency markers and
 * fail-fast rejection of unknown/unsafe/planned steps.
 *
 * These never reach a Moodle-API step, so no bootstrapped Moodle is required.
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\Blueprint;
use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\BlueprintParser;
use MoodleBlueprint\BlueprintRunner;
use MoodleBlueprint\Logger;
use MoodleBlueprint\SecurityPolicy;

$tmp = sys_get_temp_dir() . '/bp-runner-' . getmypid();
@mkdir($tmp . '/wd', 0700, true);
$logger = new Logger();

/** Write a blueprint file and return its path. */
$writeBlueprint = function (string $name, string $json) use ($tmp) {
    $path = $tmp . '/' . $name;
    file_put_contents($path, $json);
    return $path;
};

$makeRunner = function (bool $force = false) use ($logger, $tmp) {
    return new BlueprintRunner($logger, new SecurityPolicy(), '/var/www/html', $tmp, $tmp . '/wd', $force);
};

it('rejects an unknown step with clear context', function () use ($writeBlueprint, $makeRunner) {
    $file = $writeBlueprint('unknown.json', '{"steps":[{"step":"doesNotExist"}]}');
    assert_throws(BlueprintException::class, function () use ($makeRunner, $file) {
        $makeRunner()->apply(null, $file, null);
    }, 'unknown step type');
});

it('rejects an unsafe step by default', function () use ($writeBlueprint, $makeRunner) {
    $file = $writeBlueprint('unsafe.json', '{"steps":[{"step":"runPhpCode","code":"echo 1;"}]}');
    assert_throws(BlueprintException::class, function () use ($makeRunner, $file) {
        $makeRunner()->apply(null, $file, null);
    }, 'disabled by default');
});

it('rejects a planned step clearly', function () use ($writeBlueprint, $makeRunner) {
    $file = $writeBlueprint('planned.json', '{"steps":[{"step":"addModule","module":"label","course":"X"}]}');
    assert_throws(BlueprintException::class, function () use ($makeRunner, $file) {
        $makeRunner()->apply(null, $file, null);
    }, 'planned');
});

it('skips reapplication when the marker exists', function () use ($writeBlueprint, $makeRunner, $tmp) {
    // A blueprint that would throw if any step ran.
    $json = '{"steps":[{"step":"doesNotExist"}]}';
    $file = $writeBlueprint('idem.json', $json);

    // Pre-create the marker for this blueprint's hash.
    $hash = (new BlueprintParser())->parse($json)->canonicalHash();
    @mkdir($tmp . '/.blueprints', 0700, true);
    file_put_contents($tmp . '/.blueprints/' . $hash . '.done', "hash={$hash}\n");

    // apply() must short-circuit and NOT throw.
    $result = $makeRunner()->apply(null, $file, null);
    assert_true($result === true, 'apply returned true on already-applied');
});

it('reapplies (and fails on the bad step) when force is set', function () use ($writeBlueprint, $makeRunner, $tmp) {
    $json = '{"steps":[{"step":"doesNotExist"}]}';
    $file = $writeBlueprint('idem2.json', $json);
    $hash = (new BlueprintParser())->parse($json)->canonicalHash();
    @mkdir($tmp . '/.blueprints', 0700, true);
    file_put_contents($tmp . '/.blueprints/' . $hash . '.done', "hash={$hash}\n");

    assert_throws(BlueprintException::class, function () use ($makeRunner, $file) {
        $makeRunner(true)->apply(null, $file, null); // force=true
    }, 'unknown step type');
});

it('errors when no source is provided', function () use ($makeRunner) {
    assert_throws(BlueprintException::class, function () use ($makeRunner) {
        $makeRunner()->apply(null, null, null);
    }, 'No blueprint source');
});

it('validate() summarises step classifications without applying', function () use ($writeBlueprint, $makeRunner) {
    $json = '{"steps":[' .
        '{"step":"setConfig","name":"debug","value":1},' .
        '{"step":"installMoodle"},' .
        '{"step":"addModule"},' .
        '{"step":"runPhpCode"},' .
        '{"step":"madeUp"}' .
        ']}';
    $file = $writeBlueprint('validate.json', $json);
    $summary = $makeRunner()->validate(null, $file, null);
    assert_eq($summary['implemented'] ?? 0, 1);
    assert_eq($summary['noop'] ?? 0, 1);
    assert_eq($summary['planned'] ?? 0, 1);
    assert_eq($summary['unsafe'] ?? 0, 1);
    assert_eq($summary['unknown'] ?? 0, 1);
});
