<?php
/**
 * SecurityPolicy tests: size parsing, remote toggles, path traversal and the
 * Moodle path allowlist.
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\SecurityPolicy;

it('parses human-readable sizes', function () {
    assert_eq(SecurityPolicy::parseSize('50M'), 50 * 1024 * 1024);
    assert_eq(SecurityPolicy::parseSize('10k'), 10 * 1024);
    assert_eq(SecurityPolicy::parseSize('1G'), 1024 * 1024 * 1024);
    assert_eq(SecurityPolicy::parseSize('1024'), 1024);
});

it('rejects invalid sizes', function () {
    assert_throws(BlueprintException::class, function () {
        SecurityPolicy::parseSize('not-a-size');
    });
});

it('rejects remote resources when disabled', function () {
    $policy = new SecurityPolicy(false);
    assert_throws(BlueprintException::class, function () use ($policy) {
        $policy->assertRemoteAllowed('https://example.com/x.zip');
    }, 'ALLOW_REMOTE_RESOURCES');
});

it('rejects non-http(s) schemes even when remote is allowed', function () {
    $policy = new SecurityPolicy(true);
    assert_throws(BlueprintException::class, function () use ($policy) {
        $policy->assertRemoteAllowed('file:///etc/passwd');
    }, 'scheme');
});

it('enforces the size limit', function () {
    $policy = new SecurityPolicy(true, false, 100);
    $policy->assertWithinSizeLimit(100, 'thing'); // boundary ok
    assert_throws(BlueprintException::class, function () use ($policy) {
        $policy->assertWithinSizeLimit(101, 'thing');
    }, 'limit');
});

it('normalises paths lexically', function () {
    assert_eq(SecurityPolicy::normalizePath('/a/b/../c'), '/a/c');
    assert_eq(SecurityPolicy::normalizePath('/a/./b/'), '/a/b');
    assert_eq(SecurityPolicy::normalizePath('/a/b/../../..'), '/');
});

it('rejects parent-directory traversal in safeJoin', function () {
    $policy = new SecurityPolicy();
    assert_throws(BlueprintException::class, function () use ($policy) {
        $policy->safeJoin('/srv/bundle', '../../etc/passwd');
    }, 'escapes');
});

it('rejects absolute resource paths in safeJoin', function () {
    $policy = new SecurityPolicy();
    assert_throws(BlueprintException::class, function () use ($policy) {
        $policy->safeJoin('/srv/bundle', '/etc/passwd');
    }, 'Absolute');
});

it('accepts safe relative paths in safeJoin', function () {
    $policy = new SecurityPolicy();
    assert_eq($policy->safeJoin('/srv/bundle', 'plugins/mod_x.zip'), '/srv/bundle/plugins/mod_x.zip');
});

it('allows writes only under allowlisted Moodle paths', function () {
    $policy = new SecurityPolicy(true, false, 1024, ['/var/www/html']);
    $policy->assertAllowedMoodlePath('/var/www/html/mod/demo'); // ok
    assert_throws(BlueprintException::class, function () use ($policy) {
        $policy->assertAllowedMoodlePath('/etc/cron.d/evil');
    }, 'allowlisted');
});

it('rejects ZIP entries that attempt traversal', function () {
    $policy = new SecurityPolicy();
    foreach (['../evil', '/abs/evil', 'a/../../b', 'win\\path'] as $bad) {
        assert_throws(BlueprintException::class, function () use ($policy, $bad) {
            $policy->assertSafeArchiveEntry($bad);
        });
    }
    // A normal nested entry is accepted.
    $policy->assertSafeArchiveEntry('mod_demo/version.php');
});
