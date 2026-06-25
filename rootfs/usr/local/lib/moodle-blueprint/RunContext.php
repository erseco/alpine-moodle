<?php

namespace MoodleBlueprint;

/**
 * Shared services and configuration handed to every step handler.
 *
 * Keeps the step classes free of global lookups: they read everything they
 * need (logger, policy, resolver, paths, force flag) from this context.
 */
class RunContext
{
    /** @var Logger */
    private $logger;

    /** @var SecurityPolicy */
    private $policy;

    /** @var ResourceResolver */
    private $resolver;

    /** @var Blueprint */
    private $blueprint;

    /** @var string Absolute Moodle code root (e.g. /var/www/html). */
    private $moodleRoot;

    /** @var string Absolute Moodle data root (e.g. /var/www/moodledata). */
    private $dataRoot;

    /** @var string Working/temporary directory for this run. */
    private $workDir;

    /** @var bool Whether MOODLE_BLUEPRINT_FORCE is enabled. */
    private $force;

    public function __construct(
        Logger $logger,
        SecurityPolicy $policy,
        ResourceResolver $resolver,
        Blueprint $blueprint,
        string $moodleRoot,
        string $dataRoot,
        string $workDir,
        bool $force
    ) {
        $this->logger = $logger;
        $this->policy = $policy;
        $this->resolver = $resolver;
        $this->blueprint = $blueprint;
        $this->moodleRoot = rtrim($moodleRoot, '/');
        $this->dataRoot = rtrim($dataRoot, '/');
        $this->workDir = rtrim($workDir, '/');
        $this->force = $force;
    }

    public function logger(): Logger
    {
        return $this->logger;
    }

    public function policy(): SecurityPolicy
    {
        return $this->policy;
    }

    public function resolver(): ResourceResolver
    {
        return $this->resolver;
    }

    public function blueprint(): Blueprint
    {
        return $this->blueprint;
    }

    public function moodleRoot(): string
    {
        return $this->moodleRoot;
    }

    public function dataRoot(): string
    {
        return $this->dataRoot;
    }

    public function workDir(): string
    {
        return $this->workDir;
    }

    public function force(): bool
    {
        return $this->force;
    }

    /**
     * Run a Moodle CLI script (under <moodleRoot>/admin/cli) with safely
     * escaped arguments. Returns captured stdout/stderr; throws on failure.
     *
     * @param array<int,string> $args e.g. ['--name=debug', '--set=32767']
     */
    public function runMoodleCli(string $script, array $args = []): string
    {
        $path = $this->moodleRoot . '/admin/cli/' . $script;
        if (!is_file($path)) {
            throw new BlueprintException(sprintf('Moodle CLI script not found: %s', $path));
        }

        // Prefer the image's /usr/local/bin/php wrapper, which applies the
        // operator-configurable ini tuning (memory_limit, post_max_size, …).
        // Plugin upgrades run via this path can be memory-hungry, so honouring
        // those settings matters. Fall back to PHP_BINARY off-container.
        $php = is_executable('/usr/local/bin/php') ? '/usr/local/bin/php' : (PHP_BINARY ?: 'php');
        $cmd = escapeshellarg($php) . ' -d max_input_vars=10000 ' . escapeshellarg($path);
        foreach ($args as $arg) {
            $cmd .= ' ' . escapeshellarg($arg);
        }
        $cmd .= ' 2>&1';

        exec($cmd, $output, $status);
        $text = implode("\n", $output);
        if ($status !== 0) {
            throw new BlueprintException(sprintf('Moodle CLI "%s" failed (exit %d): %s', $script, $status, $text));
        }
        return $text;
    }
}
