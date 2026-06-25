<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\Archive;
use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\Frankenstyle;
use MoodleBlueprint\ResolvedResource;
use MoodleBlueprint\RunContext;

/**
 * installMoodlePlugin — install a plugin from a ZIP resource.
 *
 * Input shapes:
 *   { "step": "installMoodlePlugin", "source": "@pluginZip" }
 *   { "step": "installMoodlePlugin", "zipUrl": "https://.../plugin.zip" }
 *   { "step": "installMoodlePlugin", "url": "https://.../plugin.zip" }
 *
 * The ZIP is validated and extracted safely (ZIP-slip proof), its
 * version.php is parsed WITHOUT executing it, the frankenstyle component is
 * mapped to its install directory, and Moodle's CLI upgrade is run. Installs
 * are idempotent: an already-present plugin of the same version is left alone
 * unless MOODLE_BLUEPRINT_FORCE is set.
 */
class InstallMoodlePluginStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $resource = $this->resolveZipSource($context, $config);
        self::install($context, $resource);
    }

    /**
     * Shared install routine used by installMoodlePlugin and installTheme.
     *
     * @param string|null $expectedType frankenstyle type to enforce (e.g. "theme").
     */
    public static function install(RunContext $context, ResolvedResource $resource, ?string $expectedType = null): void
    {
        $logger = $context->logger();
        $policy = $context->policy();

        $zipPath = $resource->path();
        if (!Archive::isZip($zipPath)) {
            throw new BlueprintException(sprintf('Resource "%s" is not a valid ZIP archive.', $resource->label()));
        }

        $extractDir = $context->workDir() . '/plugin_' . substr(sha1($resource->label() . $zipPath), 0, 12);
        Archive::extract($policy, $zipPath, $extractDir);

        [$pluginDir, $component, $version] = self::inspectPlugin($extractDir);
        [$type] = explode('_', $component, 2);

        if ($expectedType !== null && $type !== $expectedType) {
            throw new BlueprintException(sprintf(
                'Expected a "%s" plugin but the archive contains "%s".',
                $expectedType,
                $component
            ));
        }

        $relative = Frankenstyle::relativePath($component);
        $target = $context->moodleRoot() . '/' . $relative;
        $policy->assertAllowedMoodlePath($target);

        if (is_dir($target)) {
            $existingVersion = self::readVersion($target . '/version.php');
            if (!$context->force() && $existingVersion !== null && $existingVersion === $version) {
                $logger->info(sprintf('Plugin %s already installed (version %s); skipping.', $component, $version));
                return;
            }
            $logger->info(sprintf('Replacing existing plugin %s at %s.', $component, $relative));
            self::removeDir($target);
        }

        $parent = dirname($target);
        if (!is_dir($parent) && !mkdir($parent, 0775, true) && !is_dir($parent)) {
            throw new BlueprintException(sprintf('Unable to create plugin directory "%s".', $parent));
        }
        if (!rename($pluginDir, $target)) {
            throw new BlueprintException(sprintf('Unable to move plugin into place at "%s".', $target));
        }

        // Match the image convention; the container runs as the nobody user, so
        // chowning to another owner is best-effort.
        @self::chownRecursive($target, 'nobody', 'nobody');

        $logger->info(sprintf('Installed plugin %s (version %s) into %s.', $component, $version ?? 'unknown', $relative));

        $context->runMoodleCli('upgrade.php', ['--non-interactive', '--allow-unstable']);
        $logger->info('Moodle upgrade completed after plugin install.');
    }

    /**
     * Find the plugin root inside the extracted tree and return
     * [pluginDir, component, version].
     *
     * @return array{0:string,1:string,2:?string}
     */
    private static function inspectPlugin(string $root): array
    {
        $versionFiles = [];
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)
        );
        foreach ($iterator as $file) {
            if ($file->getFilename() === 'version.php') {
                $versionFiles[] = $file->getPathname();
            }
        }
        if ($versionFiles === []) {
            throw new BlueprintException('No version.php found in the plugin archive.');
        }

        // Prefer the shallowest version.php that declares a component.
        usort($versionFiles, static function ($a, $b) {
            return substr_count($a, '/') <=> substr_count($b, '/');
        });

        foreach ($versionFiles as $vf) {
            $component = self::readComponent($vf);
            if ($component !== null) {
                return [dirname($vf), $component, self::readVersion($vf)];
            }
        }
        throw new BlueprintException('Could not determine the plugin component from version.php ($plugin->component).');
    }

    /**
     * Parse $plugin->component from a version.php without executing it.
     */
    private static function readComponent(string $versionFile): ?string
    {
        $contents = @file_get_contents($versionFile);
        if ($contents === false) {
            return null;
        }
        if (preg_match('/\$plugin->component\s*=\s*[\'"]([a-z][a-z0-9_]+)[\'"]\s*;/', $contents, $m)) {
            return $m[1];
        }
        return null;
    }

    /**
     * Parse $plugin->version from a version.php without executing it.
     */
    private static function readVersion(string $versionFile): ?string
    {
        $contents = @file_get_contents($versionFile);
        if ($contents === false) {
            return null;
        }
        if (preg_match('/\$plugin->version\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*;/', $contents, $m)) {
            return $m[1];
        }
        return null;
    }

    private static function removeDir(string $dir): void
    {
        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($dir, \FilesystemIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($iterator as $item) {
            if ($item->isDir()) {
                @rmdir($item->getPathname());
            } else {
                @unlink($item->getPathname());
            }
        }
        @rmdir($dir);
    }

    private static function chownRecursive(string $path, string $user, string $group): void
    {
        @chown($path, $user);
        @chgrp($path, $group);
        if (is_dir($path)) {
            $iterator = new \RecursiveIteratorIterator(
                new \RecursiveDirectoryIterator($path, \FilesystemIterator::SKIP_DOTS)
            );
            foreach ($iterator as $item) {
                @chown($item->getPathname(), $user);
                @chgrp($item->getPathname(), $group);
            }
        }
    }
}
