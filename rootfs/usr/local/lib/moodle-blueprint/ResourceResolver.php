<?php

namespace MoodleBlueprint;

/**
 * Resolves blueprint resource descriptors into concrete bytes.
 *
 * Supported descriptor shapes (Moodle Playground style plus the WordPress
 * Playground `resource` discriminator where it maps cleanly):
 *
 *   { "url": "https://..." }                         { "resource": "url", "url": "..." }
 *   { "base64": "..." }                              { "resource": "base64", "base64": "..." }
 *   { "data-url": "data:...;base64,..." }
 *   { "literal": "text" }                            { "resource": "literal", "contents": "..." }
 *   { "bundled": "plugins/x.zip" }                   { "resource": "bundled", "path": "/plugins/x.zip" }
 *
 * Resolved resources are cached for the duration of a single run so a resource
 * referenced by several steps is only fetched/decoded once.
 */
class ResourceResolver
{
    /** @var SecurityPolicy */
    private $policy;

    /** @var string Directory used to materialise temporary files. */
    private $workDir;

    /** @var string|null Root of the extracted bundle, when one is in use. */
    private $bundleRoot;

    /** @var Logger */
    private $logger;

    /** @var array<string,ResolvedResource> */
    private $cache = [];

    /** @var array<string,mixed> Named resources declared at the blueprint top level. */
    private $named = [];

    public function __construct(SecurityPolicy $policy, string $workDir, Logger $logger, ?string $bundleRoot = null)
    {
        $this->policy = $policy;
        $this->workDir = $workDir;
        $this->logger = $logger;
        $this->bundleRoot = $bundleRoot !== null ? rtrim($bundleRoot, '/') : null;
    }

    /**
     * Register the blueprint's top-level `resources` map so steps can use the
     * "@name" reference syntax.
     *
     * @param array<string,mixed> $named
     */
    public function setNamedResources(array $named): void
    {
        $this->named = $named;
    }

    /**
     * Resolve a resource reference as used inside steps. Accepts either:
     *   - "@name"  -> a named resource declared in the top-level `resources` map
     *   - an inline descriptor array, e.g. {"url": "..."} or {"bundled": "..."}
     *
     * @param mixed $ref
     */
    public function resolveReference($ref): ResolvedResource
    {
        if (is_string($ref)) {
            if ($ref === '' || $ref[0] !== '@') {
                throw new BlueprintException(sprintf('Invalid resource reference "%s" (expected "@name" or a descriptor object).', $ref));
            }
            $name = substr($ref, 1);
            if (!isset($this->named[$name]) || !is_array($this->named[$name])) {
                throw new BlueprintException(sprintf('Unknown resource reference "@%s".', $name));
            }
            return $this->resolve($this->named[$name]);
        }
        if (is_array($ref)) {
            return $this->resolve($ref);
        }
        throw new BlueprintException('Resource reference must be a "@name" string or a descriptor object.');
    }

    /**
     * Resolve a descriptor (array) into a ResolvedResource.
     *
     * @param array<string,mixed> $descriptor
     */
    public function resolve(array $descriptor): ResolvedResource
    {
        $cacheKey = md5(json_encode($descriptor));
        if (isset($this->cache[$cacheKey])) {
            return $this->cache[$cacheKey];
        }

        $kind = $this->detectKind($descriptor);
        switch ($kind) {
            case 'url':
                $resource = $this->resolveUrl($descriptor);
                break;
            case 'base64':
                $resource = $this->resolveBase64($descriptor);
                break;
            case 'data-url':
                $resource = $this->resolveDataUrl($descriptor);
                break;
            case 'literal':
                $resource = $this->resolveLiteral($descriptor);
                break;
            case 'bundled':
                $resource = $this->resolveBundled($descriptor);
                break;
            case 'vfs':
                throw new BlueprintException('The "vfs" resource type is browser-runtime specific and is not supported by the Docker runtime.');
            default:
                throw new BlueprintException(sprintf(
                    'Unsupported resource descriptor: %s',
                    json_encode(Logger::redact($descriptor))
                ));
        }

        $this->cache[$cacheKey] = $resource;
        return $resource;
    }

    /**
     * @param array<string,mixed> $descriptor
     */
    private function detectKind(array $descriptor): string
    {
        if (isset($descriptor['resource']) && is_string($descriptor['resource'])) {
            $r = strtolower($descriptor['resource']);
            // Normalise a couple of WordPress Playground aliases.
            if ($r === 'literal' && !isset($descriptor['literal'])) {
                return 'literal';
            }
            return $r;
        }

        foreach (['url', 'base64', 'literal', 'bundled'] as $key) {
            if (array_key_exists($key, $descriptor)) {
                return $key;
            }
        }
        foreach (['data-url', 'dataUrl', 'data_url'] as $key) {
            if (array_key_exists($key, $descriptor)) {
                return 'data-url';
            }
        }
        return 'unknown';
    }

    /**
     * @param array<string,mixed> $descriptor
     */
    private function resolveUrl(array $descriptor): ResolvedResource
    {
        $url = (string) ($descriptor['url'] ?? '');
        if ($url === '') {
            throw new BlueprintException('URL resource is missing the "url" field.');
        }
        $this->policy->assertRemoteAllowed($url);
        $this->logger->info('Downloading resource: ' . $url);
        $contents = Http::download($url, $this->policy->maxResourceSize(), $this->logger, $this->workDir);
        return ResolvedResource::fromContents($contents, $this->workDir, 'url:' . basename(parse_url($url, PHP_URL_PATH) ?: 'download'));
    }

    /**
     * @param array<string,mixed> $descriptor
     */
    private function resolveBase64(array $descriptor): ResolvedResource
    {
        $encoded = (string) ($descriptor['base64'] ?? '');
        // Reject using the (cheap) encoded length before allocating the decode:
        // base64 decodes to ~3/4 of its encoded length.
        if (intdiv(strlen($encoded), 4) * 3 > $this->policy->maxResourceSize()) {
            $this->policy->assertWithinSizeLimit(intdiv(strlen($encoded), 4) * 3, 'base64 resource');
        }
        $decoded = base64_decode($encoded, true);
        if ($decoded === false) {
            throw new BlueprintException('Invalid base64 resource content.');
        }
        $this->policy->assertWithinSizeLimit(strlen($decoded), 'base64 resource');
        return ResolvedResource::fromContents($decoded, $this->workDir, 'base64');
    }

    /**
     * @param array<string,mixed> $descriptor
     */
    private function resolveDataUrl(array $descriptor): ResolvedResource
    {
        $value = (string) ($descriptor['data-url'] ?? $descriptor['dataUrl'] ?? $descriptor['data_url'] ?? '');
        if (strncmp($value, 'data:', 5) !== 0) {
            throw new BlueprintException('Invalid data URL: must start with "data:".');
        }
        $comma = strpos($value, ',');
        if ($comma === false) {
            throw new BlueprintException('Invalid data URL: missing comma separator.');
        }
        $meta = substr($value, 5, $comma - 5);
        $payload = substr($value, $comma + 1);

        // Pre-check on the encoded payload length before decoding. Both base64
        // (~3/4) and percent-decoding only shrink or keep the payload size, so
        // the encoded length is a safe upper bound.
        $this->policy->assertWithinSizeLimit(strlen($payload), 'data URL resource');

        if (stripos($meta, ';base64') !== false) {
            $decoded = base64_decode($payload, true);
            if ($decoded === false) {
                throw new BlueprintException('Invalid base64 payload in data URL.');
            }
        } else {
            $decoded = rawurldecode($payload);
        }

        $this->policy->assertWithinSizeLimit(strlen($decoded), 'data URL resource');
        return ResolvedResource::fromContents($decoded, $this->workDir, 'data-url');
    }

    /**
     * @param array<string,mixed> $descriptor
     */
    private function resolveLiteral(array $descriptor): ResolvedResource
    {
        if (array_key_exists('literal', $descriptor)) {
            $value = $descriptor['literal'];
        } elseif (array_key_exists('contents', $descriptor)) {
            $value = $descriptor['contents'];
        } else {
            throw new BlueprintException('Literal resource is missing "literal"/"contents".');
        }

        if (is_array($value)) {
            $value = json_encode($value);
        } else {
            $value = (string) $value;
        }

        $this->policy->assertWithinSizeLimit(strlen($value), 'literal resource');
        return ResolvedResource::fromContents($value, $this->workDir, 'literal');
    }

    /**
     * @param array<string,mixed> $descriptor
     */
    private function resolveBundled(array $descriptor): ResolvedResource
    {
        if ($this->bundleRoot === null) {
            throw new BlueprintException('Bundled resource referenced but no bundle was provided (set MOODLE_BLUEPRINT_BUNDLE).');
        }

        $relative = (string) ($descriptor['bundled'] ?? $descriptor['path'] ?? '');
        if ($relative === '') {
            throw new BlueprintException('Bundled resource is missing its path.');
        }
        // Bundle paths may be written with a leading slash relative to the
        // bundle root (WordPress Playground style); strip it before joining.
        $relative = ltrim($relative, '/');

        $resolved = $this->policy->safeJoin($this->bundleRoot, $relative);
        if (!is_file($resolved)) {
            throw new BlueprintException(sprintf('Bundled resource "%s" not found inside the bundle.', $relative));
        }
        $this->policy->assertWithinSizeLimit(filesize($resolved) ?: 0, 'bundled resource');

        return ResolvedResource::fromPath($resolved, $this->workDir, 'bundled:' . $relative);
    }
}
