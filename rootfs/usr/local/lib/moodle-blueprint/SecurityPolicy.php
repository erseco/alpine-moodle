<?php

namespace MoodleBlueprint;

/**
 * Central security policy for blueprint execution.
 *
 * All size limits, remote-resource toggles, unsafe-step toggles and path
 * containment checks live here so the rest of the runner can stay declarative
 * and the safe defaults are enforced in a single, auditable place.
 */
class SecurityPolicy
{
    /** @var bool Whether `url` resources may be downloaded. */
    private $allowRemoteResources;

    /** @var bool Whether unsafe steps (arbitrary code/file ops) may run. */
    private $allowUnsafeSteps;

    /** @var int Maximum size in bytes for any resolved/downloaded resource. */
    private $maxResourceSize;

    /**
     * Absolute directories under which the runner is allowed to write Moodle
     * files (plugin installs, etc.). Anything outside is rejected.
     *
     * @var string[]
     */
    private $allowedMoodlePaths;

    /**
     * @param string[] $allowedMoodlePaths
     */
    public function __construct(
        bool $allowRemoteResources = true,
        bool $allowUnsafeSteps = false,
        int $maxResourceSize = 52428800,
        array $allowedMoodlePaths = ['/var/www/html']
    ) {
        $this->allowRemoteResources = $allowRemoteResources;
        $this->allowUnsafeSteps = $allowUnsafeSteps;
        $this->maxResourceSize = $maxResourceSize;
        $this->allowedMoodlePaths = $allowedMoodlePaths;
    }

    public function allowsRemoteResources(): bool
    {
        return $this->allowRemoteResources;
    }

    public function allowsUnsafeSteps(): bool
    {
        return $this->allowUnsafeSteps;
    }

    public function maxResourceSize(): int
    {
        return $this->maxResourceSize;
    }

    /**
     * Parse a human size string such as "50M", "10k", "1G" or a plain byte
     * count into an integer number of bytes.
     */
    public static function parseSize(string $size): int
    {
        $size = trim($size);
        if ($size === '') {
            throw new BlueprintException('Empty size value.');
        }

        if (!preg_match('/^([0-9]+(?:\.[0-9]+)?)\s*([kKmMgG]?)[bB]?$/', $size, $m)) {
            throw new BlueprintException(sprintf('Invalid size value "%s". Use bytes or a K/M/G suffix.', $size));
        }

        $value = (float) $m[1];
        switch (strtolower($m[2])) {
            case 'g':
                $value *= 1024 * 1024 * 1024;
                break;
            case 'm':
                $value *= 1024 * 1024;
                break;
            case 'k':
                $value *= 1024;
                break;
        }

        return (int) $value;
    }

    /**
     * Throw unless remote resources are permitted.
     */
    public function assertRemoteAllowed(string $url): void
    {
        if (!$this->allowRemoteResources) {
            throw new BlueprintException(sprintf(
                'Remote resource "%s" rejected: set MOODLE_BLUEPRINT_ALLOW_REMOTE_RESOURCES=true to allow URL resources.',
                $url
            ));
        }

        $scheme = strtolower((string) parse_url($url, PHP_URL_SCHEME));
        if ($scheme !== 'http' && $scheme !== 'https') {
            throw new BlueprintException(sprintf('Unsupported URL scheme "%s"; only http/https are allowed.', $scheme));
        }
    }

    /**
     * Throw unless a number of bytes is within the configured maximum.
     */
    public function assertWithinSizeLimit(int $bytes, string $what = 'resource'): void
    {
        if ($bytes > $this->maxResourceSize) {
            throw new BlueprintException(sprintf(
                '%s is %d bytes, exceeding the %d byte limit (MOODLE_BLUEPRINT_MAX_RESOURCE_SIZE).',
                ucfirst($what),
                $bytes,
                $this->maxResourceSize
            ));
        }
    }

    /**
     * Lexically normalise a path, collapsing "." and ".." segments WITHOUT
     * touching the filesystem. The result is always absolute when the input is.
     */
    public static function normalizePath(string $path): string
    {
        $isAbsolute = isset($path[0]) && $path[0] === '/';
        $parts = explode('/', $path);
        $stack = [];

        foreach ($parts as $part) {
            if ($part === '' || $part === '.') {
                continue;
            }
            if ($part === '..') {
                if ($stack && end($stack) !== '..') {
                    array_pop($stack);
                } elseif (!$isAbsolute) {
                    $stack[] = '..';
                }
                continue;
            }
            $stack[] = $part;
        }

        $normalized = implode('/', $stack);
        return $isAbsolute ? '/' . $normalized : $normalized;
    }

    /**
     * Safely join a relative path to a base directory and guarantee the result
     * stays inside that base. Rejects absolute paths and "../" escapes.
     *
     * @return string Absolute, normalised path inside $base.
     */
    public function safeJoin(string $base, string $relative): string
    {
        if (isset($relative[0]) && $relative[0] === '/') {
            throw new BlueprintException(sprintf('Absolute resource path "%s" is not allowed.', $relative));
        }
        if (strpos($relative, "\0") !== false) {
            throw new BlueprintException('Null byte in resource path is not allowed.');
        }

        $base = rtrim(self::normalizePath($base), '/');
        $candidate = self::normalizePath($base . '/' . $relative);

        $this->assertWithinDirectory($base, $candidate);
        return $candidate;
    }

    /**
     * Throw unless $candidate is contained within $base.
     *
     * Both arguments are normalised lexically; when the candidate exists on
     * disk its realpath is also checked to defeat symlink escapes.
     */
    public function assertWithinDirectory(string $base, string $candidate): void
    {
        $base = rtrim(self::normalizePath($base), '/');
        $candidate = self::normalizePath($candidate);

        if ($candidate !== $base && strncmp($candidate . '/', $base . '/', strlen($base) + 1) !== 0) {
            throw new BlueprintException(sprintf('Path "%s" escapes the allowed directory "%s".', $candidate, $base));
        }

        // If the target already exists, resolve symlinks and re-check so that a
        // symlink inside the bundle cannot point outside it.
        $realBase = realpath($base);
        $realCandidate = realpath($candidate);
        if ($realBase !== false && $realCandidate !== false) {
            if ($realCandidate !== $realBase && strncmp($realCandidate . '/', $realBase . '/', strlen($realBase) + 1) !== 0) {
                throw new BlueprintException(sprintf('Path "%s" resolves outside the allowed directory.', $candidate));
            }
        }
    }

    /**
     * Throw unless $path lives under one of the allowlisted Moodle directories.
     * Used before the runner writes plugin files into the codebase.
     */
    public function assertAllowedMoodlePath(string $path): void
    {
        $normalized = self::normalizePath($path);
        foreach ($this->allowedMoodlePaths as $allowed) {
            $allowed = rtrim(self::normalizePath($allowed), '/');
            if ($normalized === $allowed || strncmp($normalized . '/', $allowed . '/', strlen($allowed) + 1) === 0) {
                return;
            }
        }
        throw new BlueprintException(sprintf(
            'Refusing to write outside allowlisted Moodle directories: "%s".',
            $path
        ));
    }

    /**
     * Validate a ZIP entry name before it is used as a destination path.
     * Rejects absolute paths, parent-directory traversal and null bytes.
     */
    public function assertSafeArchiveEntry(string $name): void
    {
        if ($name === '') {
            throw new BlueprintException('Empty archive entry name.');
        }
        if (isset($name[0]) && $name[0] === '/') {
            throw new BlueprintException(sprintf('Archive entry "%s" uses an absolute path (possible ZIP slip).', $name));
        }
        if (strpos($name, "\0") !== false) {
            throw new BlueprintException('Archive entry contains a null byte.');
        }
        // Drive-letter / backslash style paths are never valid here either.
        if (preg_match('#(^|/)\.\.(/|$)#', $name) || strpos($name, '\\') !== false) {
            throw new BlueprintException(sprintf('Archive entry "%s" attempts directory traversal (possible ZIP slip).', $name));
        }
    }
}
