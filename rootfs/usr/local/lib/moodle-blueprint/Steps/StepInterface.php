<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\RunContext;

/**
 * Contract implemented by every blueprint step handler.
 */
interface StepInterface
{
    /**
     * Execute the step.
     *
     * @param array<string,mixed> $config The step object (including "step").
     * @param int                 $index  Zero-based position in the steps array.
     */
    public function run(RunContext $context, array $config, int $index): void;
}
