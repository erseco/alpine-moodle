<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * setTheme — set the active Moodle theme.
 *
 * Accepts the alpine-moodle "theme" field and the Moodle Playground "name"
 * field:
 *   { "step": "setTheme", "theme": "boost" }
 *   { "step": "setTheme", "name": "boost" }
 */
class SetThemeStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $theme = $this->optString($config, 'theme');
        if ($theme === '') {
            $theme = $this->optString($config, 'name');
        }
        if ($theme === '') {
            throw new BlueprintException('setTheme requires a "theme" (or "name") value.');
        }
        if (!preg_match('/^[a-z][a-z0-9_]+$/', $theme)) {
            throw new BlueprintException(sprintf('Invalid theme name "%s".', $theme));
        }

        SetConfigStep::apply($context, 'theme', $theme);
        $context->logger()->info(sprintf('Theme set to "%s".', $theme));
    }
}
