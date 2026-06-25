<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\ResolvedResource;
use MoodleBlueprint\RunContext;

/**
 * Base class with shared argument-reading and helper logic for step handlers.
 */
abstract class AbstractStep implements StepInterface
{
    /**
     * Require a non-empty string field.
     *
     * @param array<string,mixed> $config
     */
    protected function requireString(array $config, string $key): string
    {
        if (!isset($config[$key]) || !is_scalar($config[$key]) || (string) $config[$key] === '') {
            throw new BlueprintException(sprintf('Missing required "%s" field.', $key));
        }
        return (string) $config[$key];
    }

    /**
     * Read an optional string field with a default.
     *
     * @param array<string,mixed> $config
     */
    protected function optString(array $config, string $key, string $default = ''): string
    {
        if (!isset($config[$key]) || !is_scalar($config[$key])) {
            return $default;
        }
        return (string) $config[$key];
    }

    /**
     * Read an optional boolean field with a default.
     *
     * @param array<string,mixed> $config
     */
    protected function optBool(array $config, string $key, bool $default): bool
    {
        if (!array_key_exists($key, $config)) {
            return $default;
        }
        return filter_var($config[$key], FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE) ?? $default;
    }

    /**
     * Convert a blueprint value into a string Moodle config accepts.
     *
     * @param mixed $value
     */
    protected function coerceConfigValue($value): string
    {
        if (is_bool($value)) {
            return $value ? '1' : '0';
        }
        if ($value === null) {
            return '';
        }
        if (is_array($value)) {
            throw new BlueprintException('Config values must be scalars, not arrays.');
        }
        return (string) $value;
    }

    /**
     * Resolve a plugin/theme ZIP source from common step shapes:
     *   - "source"  : "@ref" or an inline descriptor object
     *   - "url"     : remote ZIP URL
     *   - "zipUrl"  : remote ZIP URL (Moodle Playground alias)
     *   - "bundled" : path inside the bundle
     *
     * @param array<string,mixed> $config
     */
    protected function resolveZipSource(RunContext $context, array $config): ResolvedResource
    {
        if (isset($config['source'])) {
            return $context->resolver()->resolveReference($config['source']);
        }
        foreach (['zipUrl', 'url'] as $key) {
            if (isset($config[$key]) && is_string($config[$key]) && $config[$key] !== '') {
                return $context->resolver()->resolve(['url' => $config[$key]]);
            }
        }
        if (isset($config['bundled']) && is_string($config['bundled'])) {
            return $context->resolver()->resolve(['bundled' => $config['bundled']]);
        }
        throw new BlueprintException('No plugin source provided (expected "source", "url", "zipUrl" or "bundled").');
    }

    /**
     * Ensure Moodle has been bootstrapped before using its PHP API.
     */
    protected function requireMoodle(): void
    {
        if (!isset($GLOBALS['CFG']) || !isset($GLOBALS['DB'])) {
            throw new BlueprintException('This step requires a bootstrapped Moodle environment.');
        }
    }
}
