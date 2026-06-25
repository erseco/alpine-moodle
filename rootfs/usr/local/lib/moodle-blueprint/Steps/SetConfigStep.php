<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * setConfig — set a single Moodle configuration value via admin/cli/cfg.php.
 *
 * Input:
 *   { "step": "setConfig", "name": "debug", "value": 32767, "plugin": "..." }
 */
class SetConfigStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $name = $this->requireString($config, 'name');
        $value = $this->coerceConfigValue($config['value'] ?? '');
        $plugin = $this->optString($config, 'plugin');

        self::apply($context, $name, $value, $plugin !== '' ? $plugin : null);
    }

    /**
     * Apply a single config value through Moodle's CLI. Values are never logged
     * (a config name may carry a secret such as an SMTP password).
     */
    public static function apply(RunContext $context, string $name, string $value, ?string $plugin = null): void
    {
        if (!preg_match('/^[a-zA-Z0-9_.\-]+$/', $name)) {
            throw new BlueprintException(sprintf('Invalid config name "%s".', $name));
        }

        $args = ['--name=' . $name, '--set=' . $value];
        if ($plugin !== null && $plugin !== '') {
            if (!preg_match('/^[a-z][a-z0-9_]+$/', $plugin)) {
                throw new BlueprintException(sprintf('Invalid plugin component "%s".', $plugin));
            }
            $args[] = '--component=' . $plugin;
        }

        $context->runMoodleCli('cfg.php', $args);
        $context->logger()->info(sprintf('setConfig %s%s applied.', $plugin ? $plugin . '/' : '', $name));
    }
}
