<?php

namespace MoodleBlueprint;

/**
 * A blueprint bundle: a self-contained directory or ZIP archive holding a
 * `blueprint.json` plus the resources it references (inspired by WordPress
 * Playground Blueprint Bundles).
 *
 * Detection rules (matching the WordPress Playground convention):
 *   - `blueprint.json` may live at the bundle root, OR
 *   - exactly one directory deep inside a single top-level folder.
 *   - The `__MACOSX` metadata directory is ignored during detection.
 *   - Multiple candidate `blueprint.json` files are an ambiguity error.
 */
class Bundle
{
    /** @var string Directory containing blueprint.json (resource resolution root). */
    private $root;

    /** @var string Absolute path to the blueprint.json file. */
    private $blueprintPath;

    private function __construct(string $root, string $blueprintPath)
    {
        $this->root = $root;
        $this->blueprintPath = $blueprintPath;
    }

    public function root(): string
    {
        return $this->root;
    }

    public function blueprintPath(): string
    {
        return $this->blueprintPath;
    }

    /**
     * Open a bundle from a directory or ZIP path. ZIP bundles are extracted
     * under $workDir/bundle before detection.
     */
    public static function open(SecurityPolicy $policy, string $bundlePath, string $workDir, Logger $logger): self
    {
        if (is_dir($bundlePath)) {
            $logger->info('Using bundle directory: ' . $bundlePath);
            $extracted = rtrim($bundlePath, '/');
        } elseif (is_file($bundlePath)) {
            if (!Archive::isZip($bundlePath)) {
                throw new BlueprintException(sprintf('Bundle "%s" is neither a directory nor a valid ZIP archive.', $bundlePath));
            }
            $logger->info('Extracting bundle ZIP: ' . $bundlePath);
            $extracted = $workDir . '/bundle';
            Archive::extract($policy, $bundlePath, $extracted);
        } else {
            throw new BlueprintException(sprintf('Bundle path "%s" does not exist.', $bundlePath));
        }

        [$root, $blueprintPath] = self::locateBlueprint($extracted);
        return new self($root, $blueprintPath);
    }

    /**
     * Locate blueprint.json at the bundle root or one directory deep.
     *
     * @return array{0:string,1:string} [bundleRoot, blueprintPath]
     */
    private static function locateBlueprint(string $root): array
    {
        $rootCandidate = $root . '/blueprint.json';
        if (is_file($rootCandidate)) {
            return [$root, $rootCandidate];
        }

        $matches = [];
        $entries = scandir($root) ?: [];
        foreach ($entries as $entry) {
            if ($entry === '.' || $entry === '..' || $entry === '__MACOSX') {
                continue;
            }
            $sub = $root . '/' . $entry;
            if (is_dir($sub) && is_file($sub . '/blueprint.json')) {
                $matches[] = $sub;
            }
        }

        if (count($matches) === 1) {
            return [$matches[0], $matches[0] . '/blueprint.json'];
        }
        if (count($matches) > 1) {
            throw new BlueprintException('Ambiguous bundle: multiple blueprint.json files found one directory deep.');
        }
        throw new BlueprintException('No blueprint.json found at the bundle root or one directory deep.');
    }
}
