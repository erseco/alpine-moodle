<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\RunContext;

/**
 * installTheme — install a theme plugin from a ZIP resource.
 *
 * Shares the safe install routine with installMoodlePlugin but enforces that
 * the archive contains a theme_* component.
 *
 *   { "step": "installTheme", "source": "@themeZip" }
 *   { "step": "installTheme", "url": "https://.../theme.zip" }
 */
class InstallThemeStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $resource = $this->resolveZipSource($context, $config);
        InstallMoodlePluginStep::install($context, $resource, 'theme');
    }
}
