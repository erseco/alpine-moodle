<?php

namespace MoodleBlueprint;

/**
 * Structured error raised while parsing or applying a blueprint.
 *
 * Carries optional step context (index + name) so the runner can produce
 * actionable messages such as "step 3 (installMoodlePlugin): ...".
 */
class BlueprintException extends \RuntimeException
{
    /** @var int|null Zero-based index of the failing step, if applicable. */
    private $stepIndex;

    /** @var string|null Name of the failing step, if applicable. */
    private $stepName;

    public function __construct(string $message, ?int $stepIndex = null, ?string $stepName = null, ?\Throwable $previous = null)
    {
        $this->stepIndex = $stepIndex;
        $this->stepName = $stepName;
        parent::__construct($message, 0, $previous);
    }

    public function getStepIndex(): ?int
    {
        return $this->stepIndex;
    }

    public function getStepName(): ?string
    {
        return $this->stepName;
    }

    /**
     * Human-readable message prefixed with the failing step when known.
     */
    public function describe(): string
    {
        if ($this->stepIndex !== null) {
            $name = $this->stepName !== null ? $this->stepName : 'unknown';
            return sprintf('step %d (%s): %s', $this->stepIndex, $name, $this->getMessage());
        }
        return $this->getMessage();
    }
}
