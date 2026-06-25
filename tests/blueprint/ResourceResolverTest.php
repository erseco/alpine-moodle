<?php
/**
 * ResourceResolver tests: literal/base64/data-url descriptors, the "@name"
 * reference syntax, size enforcement and bundled path safety.
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\Logger;
use MoodleBlueprint\ResourceResolver;
use MoodleBlueprint\SecurityPolicy;

$workDir = sys_get_temp_dir() . '/bp-res-' . getmypid();
@mkdir($workDir, 0700, true);
$logger = new Logger();

it('resolves a literal resource', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $res = $resolver->resolve(['literal' => 'hello world']);
    assert_eq($res->contents(), 'hello world');
});

it('json-encodes a literal object resource', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $res = $resolver->resolve(['literal' => ['a' => 1]]);
    assert_eq($res->contents(), '{"a":1}');
});

it('resolves a base64 resource', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $res = $resolver->resolve(['base64' => base64_encode('binary-bytes')]);
    assert_eq($res->contents(), 'binary-bytes');
});

it('rejects invalid base64', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolve(['base64' => '!!!not base64!!!']);
    });
});

it('resolves a base64 data URL', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $res = $resolver->resolve(['data-url' => 'data:text/plain;base64,' . base64_encode('via-data-url')]);
    assert_eq($res->contents(), 'via-data-url');
});

it('resolves a percent-encoded data URL', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $res = $resolver->resolve(['data-url' => 'data:text/plain,hello%20world']);
    assert_eq($res->contents(), 'hello world');
});

it('resolves "@name" references against the resources map', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $resolver->setNamedResources(['readme' => ['literal' => 'from-map']]);
    $res = $resolver->resolveReference('@readme');
    assert_eq($res->contents(), 'from-map');
});

it('resolves inline descriptor references', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    $res = $resolver->resolveReference(['literal' => 'inline']);
    assert_eq($res->contents(), 'inline');
});

it('rejects unknown "@name" references', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolveReference('@missing');
    }, 'Unknown resource reference');
});

it('rejects url resources when remote is disabled', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(false), $workDir, $logger);
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolve(['url' => 'https://example.com/x.zip']);
    }, 'ALLOW_REMOTE_RESOURCES');
});

it('enforces the size limit on literal resources', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(true, false, 4), $workDir, $logger);
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolve(['literal' => 'too-long']);
    }, 'limit');
});

it('rejects bundled references that escape the bundle', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger, '/srv/bundle');
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolve(['bundled' => '../../etc/passwd']);
    });
});

it('rejects bundled references when no bundle is set', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolve(['bundled' => 'plugins/x.zip']);
    }, 'no bundle');
});

it('rejects the browser-only vfs resource type', function () use ($workDir, $logger) {
    $resolver = new ResourceResolver(new SecurityPolicy(), $workDir, $logger);
    assert_throws(BlueprintException::class, function () use ($resolver) {
        $resolver->resolve(['resource' => 'vfs', 'vfs' => '/x']);
    }, 'vfs');
});
