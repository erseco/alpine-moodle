<?php

namespace MoodleBlueprint;

/**
 * Orchestrates applying a blueprint: source selection, parsing, idempotency,
 * and sequential (fail-fast) step execution.
 *
 * Source precedence (matching the documented behaviour):
 *   1. bundle  (MOODLE_BLUEPRINT_BUNDLE)
 *   2. file    (MOODLE_BLUEPRINT)
 *   3. url     (MOODLE_BLUEPRINT_URL)
 */
class BlueprintRunner
{
    /** @var Logger */
    private $logger;

    /** @var SecurityPolicy */
    private $policy;

    /** @var string */
    private $moodleRoot;

    /** @var string */
    private $dataRoot;

    /** @var string */
    private $workDir;

    /** @var bool */
    private $force;

    public function __construct(
        Logger $logger,
        SecurityPolicy $policy,
        string $moodleRoot,
        string $dataRoot,
        string $workDir,
        bool $force
    ) {
        $this->logger = $logger;
        $this->policy = $policy;
        $this->moodleRoot = rtrim($moodleRoot, '/');
        $this->dataRoot = rtrim($dataRoot, '/');
        $this->workDir = rtrim($workDir, '/');
        $this->force = $force;
    }

    /**
     * Apply a blueprint chosen from the provided sources.
     *
     * @return bool True when the blueprint was applied (or already applied).
     */
    public function apply(?string $bundle, ?string $file, ?string $url): bool
    {
        [$blueprintPath, $bundleRoot] = $this->selectSource($bundle, $file, $url);

        $parser = new BlueprintParser();
        $blueprint = $parser->parseFile($blueprintPath);

        $hash = $blueprint->canonicalHash();
        $markerFile = $this->dataRoot . '/.blueprints/' . $hash . '.done';
        if (!$this->force && is_file($markerFile)) {
            $this->logger->info('Blueprint already applied: ' . $hash);
            return true;
        }

        $resolver = new ResourceResolver($this->policy, $this->workDir, $this->logger, $bundleRoot);
        $resolver->setNamedResources($blueprint->resources());

        $context = new RunContext(
            $this->logger,
            $this->policy,
            $resolver,
            $blueprint,
            $this->moodleRoot,
            $this->dataRoot,
            $this->workDir,
            $this->force
        );

        $this->runSteps($context, $blueprint);

        $this->writeMarker($markerFile, $hash);
        $this->logger->info('Blueprint applied successfully: ' . $hash);

        $landing = $blueprint->landingPage();
        if ($landing !== null && $landing !== '') {
            $this->logger->info(sprintf('Landing page hint: %s (the Docker runtime does not auto-navigate).', $landing));
        }

        return true;
    }

    /**
     * Validate a blueprint without applying it. Returns a summary of step
     * classifications. Does not require a bootstrapped Moodle.
     *
     * @return array<string,int>
     */
    public function validate(?string $bundle, ?string $file, ?string $url): array
    {
        [$blueprintPath] = $this->selectSource($bundle, $file, $url);
        $parser = new BlueprintParser();
        $blueprint = $parser->parseFile($blueprintPath);

        $registry = new StepRegistry();
        $summary = [];
        foreach ($blueprint->steps() as $step) {
            $kind = $registry->classify((string) $step['step']);
            $summary[$kind] = ($summary[$kind] ?? 0) + 1;
        }
        $this->logger->info('Blueprint is valid. Hash: ' . $blueprint->canonicalHash());
        return $summary;
    }

    /**
     * @return array{0:string,1:?string} [blueprintPath, bundleRoot]
     */
    private function selectSource(?string $bundle, ?string $file, ?string $url): array
    {
        if ($bundle !== null && $bundle !== '') {
            $this->logger->info('Blueprint source: bundle (' . $bundle . ')');
            $opened = Bundle::open($this->policy, $bundle, $this->workDir, $this->logger);
            return [$opened->blueprintPath(), $opened->root()];
        }
        if ($file !== null && $file !== '') {
            if (!is_file($file)) {
                throw new BlueprintException(sprintf('Blueprint file not found: %s', $file));
            }
            $this->logger->info('Blueprint source: file (' . $file . ')');
            return [$file, null];
        }
        if ($url !== null && $url !== '') {
            $this->logger->info('Blueprint source: url (' . $url . ')');
            $contents = Http::download($url, $this->policy->maxResourceSize(), $this->logger, $this->workDir);
            $dest = $this->workDir . '/blueprint.json';
            if (file_put_contents($dest, $contents) === false) {
                throw new BlueprintException('Unable to store the downloaded blueprint.');
            }
            return [$dest, null];
        }
        throw new BlueprintException('No blueprint source provided.');
    }

    private function runSteps(RunContext $context, Blueprint $blueprint): void
    {
        $registry = new StepRegistry();

        foreach ($blueprint->steps() as $index => $step) {
            $index = (int) $index;
            $name = (string) $step['step'];
            $kind = $registry->classify($name);

            switch ($kind) {
                case StepRegistry::IMPLEMENTED:
                    $this->logger->info(sprintf('Step %d: %s', $index, $name));
                    try {
                        $registry->handler($name)->run($context, $step, $index);
                    } catch (BlueprintException $e) {
                        // Attach step context if the handler did not already.
                        if ($e->getStepIndex() === null) {
                            throw new BlueprintException($e->getMessage(), $index, $name, $e);
                        }
                        throw $e;
                    } catch (\Throwable $e) {
                        throw new BlueprintException($e->getMessage(), $index, $name, $e);
                    }
                    break;

                case StepRegistry::NOOP:
                    $this->logger->info(sprintf(
                        'Step %d: %s skipped (handled by the container / not applicable to the Docker runtime).',
                        $index,
                        $name
                    ));
                    break;

                case StepRegistry::PLANNED:
                    throw new BlueprintException(
                        sprintf('step "%s" is a recognised Moodle Playground step that is not yet implemented in the Docker runtime (planned).', $name),
                        $index,
                        $name
                    );

                case StepRegistry::UNSAFE:
                    if (!$this->policy->allowsUnsafeSteps()) {
                        throw new BlueprintException(
                            sprintf('unsafe step "%s" is disabled by default (set MOODLE_BLUEPRINT_ALLOW_UNSAFE_STEPS=true to opt in); it is also not implemented in this version.', $name),
                            $index,
                            $name
                        );
                    }
                    throw new BlueprintException(
                        sprintf('unsafe step "%s" is enabled but not implemented in this version.', $name),
                        $index,
                        $name
                    );

                default:
                    throw new BlueprintException(sprintf('unknown step type "%s".', $name), $index, $name);
            }
        }
    }

    private function writeMarker(string $markerFile, string $hash): void
    {
        $dir = dirname($markerFile);
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new BlueprintException(sprintf('Unable to create marker directory "%s".', $dir));
        }
        $payload = sprintf("hash=%s\napplied=%s\n", $hash, gmdate('c'));
        if (file_put_contents($markerFile, $payload) === false) {
            throw new BlueprintException(sprintf('Unable to write idempotency marker "%s".', $markerFile));
        }
    }
}
