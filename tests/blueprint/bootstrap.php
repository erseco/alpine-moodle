<?php
/**
 * Minimal, dependency-free test harness for the Moodle blueprint runner.
 *
 * These tests exercise the pure (non-Moodle) parts of the runner — parser,
 * security policy, resource resolver, registry, archive safety and the
 * idempotency hash — so they run with a plain `php` binary and need neither
 * PHPUnit nor a bootstrapped Moodle.
 *
 * Each test file requires this bootstrap, declares cases with it(), and exits
 * with a non-zero status if any case fails (handled by the shutdown function).
 */

$repoRoot = dirname(__DIR__, 2);
require $repoRoot . '/rootfs/usr/local/lib/moodle-blueprint/autoload.php';

final class TestRunner
{
    /** @var int */
    public static $passed = 0;
    /** @var int */
    public static $failed = 0;

    public static function it(string $name, callable $fn): void
    {
        try {
            $fn();
            self::$passed++;
            fwrite(STDOUT, "  ok   - {$name}\n");
        } catch (\Throwable $e) {
            self::$failed++;
            fwrite(STDOUT, "  FAIL - {$name}: " . $e->getMessage() . "\n");
        }
    }
}

function it(string $name, callable $fn): void
{
    TestRunner::it($name, $fn);
}

function assert_true($cond, string $message = 'expected true'): void
{
    if (!$cond) {
        throw new \Exception($message);
    }
}

function assert_eq($actual, $expected, string $message = ''): void
{
    if ($actual !== $expected) {
        throw new \Exception(
            ($message !== '' ? $message . ': ' : '') .
            'expected ' . var_export($expected, true) . ' but got ' . var_export($actual, true)
        );
    }
}

function assert_contains(string $haystack, string $needle, string $message = ''): void
{
    if (strpos($haystack, $needle) === false) {
        throw new \Exception(($message !== '' ? $message . ': ' : '') . "'{$needle}' not found in '{$haystack}'");
    }
}

/**
 * Assert that running $fn throws an exception of $class (optionally with a
 * message containing $contains).
 */
function assert_throws(string $class, callable $fn, ?string $contains = null): void
{
    try {
        $fn();
    } catch (\Throwable $e) {
        if (!($e instanceof $class)) {
            throw new \Exception("expected {$class} but caught " . get_class($e) . ': ' . $e->getMessage());
        }
        if ($contains !== null) {
            assert_contains($e->getMessage(), $contains, 'exception message');
        }
        return;
    }
    throw new \Exception("expected {$class} to be thrown, but nothing was thrown");
}

register_shutdown_function(static function () {
    fwrite(STDOUT, sprintf("  -> %d passed, %d failed\n", TestRunner::$passed, TestRunner::$failed));
    if (TestRunner::$failed > 0) {
        exit(1);
    }
});
