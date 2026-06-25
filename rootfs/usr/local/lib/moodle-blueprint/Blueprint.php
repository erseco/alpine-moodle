<?php

namespace MoodleBlueprint;

/**
 * Parsed, constant-substituted blueprint.
 *
 * Holds the decoded blueprint data and exposes typed accessors for the parts
 * the runner cares about. Unknown top-level fields are preserved verbatim in
 * {@see data()} so forward-compatible blueprints do not fail to load.
 */
class Blueprint
{
    /** @var array<string,mixed> */
    private $data;

    /**
     * @param array<string,mixed> $data Decoded + substituted blueprint data.
     */
    public function __construct(array $data)
    {
        $this->data = $data;
    }

    /**
     * @return array<string,mixed>
     */
    public function data(): array
    {
        return $this->data;
    }

    /**
     * @return array<int,array<string,mixed>>
     */
    public function steps(): array
    {
        return $this->data['steps'] ?? [];
    }

    /**
     * Top-level named resources map.
     *
     * @return array<string,mixed>
     */
    public function resources(): array
    {
        $resources = $this->data['resources'] ?? [];
        return is_array($resources) ? $resources : [];
    }

    /**
     * @return array<string,mixed>
     */
    public function constants(): array
    {
        $constants = $this->data['constants'] ?? [];
        return is_array($constants) ? $constants : [];
    }

    public function landingPage(): ?string
    {
        return isset($this->data['landingPage']) ? (string) $this->data['landingPage'] : null;
    }

    /**
     * @return array<string,mixed>
     */
    public function preferredVersions(): array
    {
        $pv = $this->data['preferredVersions'] ?? [];
        return is_array($pv) ? $pv : [];
    }

    /**
     * Stable SHA-256 over the canonical (recursively key-sorted) blueprint
     * content, used as the idempotency marker name.
     *
     * NOTE: this hashes the declarative blueprint content only. It does not
     * incorporate the bytes of bundled/remote resources, so changing a
     * referenced resource without editing the blueprint will not change the
     * hash. See docs/blueprints.md for this documented limitation.
     */
    public function canonicalHash(): string
    {
        return hash('sha256', self::canonicalize($this->data));
    }

    /**
     * Produce a deterministic JSON encoding by recursively sorting array keys.
     *
     * @param mixed $value
     */
    private static function canonicalize($value): string
    {
        if (is_array($value)) {
            $isList = array_keys($value) === range(0, count($value) - 1);
            if (!$isList) {
                ksort($value);
            }
            $parts = [];
            foreach ($value as $k => $v) {
                $parts[] = json_encode((string) $k) . ':' . self::canonicalize($v);
            }
            return ($isList ? '[' : '{') . implode(',', $parts) . ($isList ? ']' : '}');
        }
        return json_encode($value);
    }
}
