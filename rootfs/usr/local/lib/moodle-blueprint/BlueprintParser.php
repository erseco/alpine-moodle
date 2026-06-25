<?php

namespace MoodleBlueprint;

/**
 * Parses and validates blueprint JSON.
 *
 * Responsibilities (the "declaration + validation" phases, kept separate from
 * resource resolution and step execution):
 *   - decode JSON, failing clearly on syntax errors;
 *   - require a `steps` array, each entry carrying a non-empty `step` name;
 *   - substitute `{{KEY}}` constants throughout the structure;
 *   - preserve unknown top-level fields without failing.
 */
class BlueprintParser
{
    /**
     * Parse a blueprint from a JSON string.
     */
    public function parse(string $json): Blueprint
    {
        $data = json_decode($json, true);
        if ($data === null && json_last_error() !== JSON_ERROR_NONE) {
            throw new BlueprintException('Invalid blueprint JSON: ' . json_last_error_msg());
        }
        if (!is_array($data) || array_keys($data) === range(0, count($data) - 1)) {
            throw new BlueprintException('Blueprint must be a JSON object.');
        }

        $constants = [];
        if (isset($data['constants'])) {
            if (!is_array($data['constants'])) {
                throw new BlueprintException('Blueprint "constants" must be an object.');
            }
            $constants = $data['constants'];
        }

        $data = self::substituteConstants($data, $constants);

        if (!array_key_exists('steps', $data)) {
            throw new BlueprintException('Blueprint must contain a "steps" array.');
        }
        if (!is_array($data['steps']) || (count($data['steps']) > 0 && array_keys($data['steps']) !== range(0, count($data['steps']) - 1))) {
            throw new BlueprintException('Blueprint "steps" must be an array.');
        }

        foreach ($data['steps'] as $index => $step) {
            if (!is_array($step)) {
                throw new BlueprintException('Each step must be an object.', (int) $index);
            }
            if (!isset($step['step']) || !is_string($step['step']) || $step['step'] === '') {
                throw new BlueprintException('Each step must have a non-empty "step" name.', (int) $index);
            }
        }

        return new Blueprint($data);
    }

    /**
     * Parse a blueprint from a file path.
     */
    public function parseFile(string $path): Blueprint
    {
        if (!is_file($path)) {
            throw new BlueprintException(sprintf('Blueprint file not found: %s', $path));
        }
        $json = file_get_contents($path);
        if ($json === false) {
            throw new BlueprintException(sprintf('Unable to read blueprint file: %s', $path));
        }
        return $this->parse($json);
    }

    /**
     * Recursively replace `{{KEY}}` placeholders in every string value using
     * the supplied constants map. Unknown placeholders are left untouched.
     *
     * @param mixed $value
     * @param array<string,mixed> $constants
     * @return mixed
     */
    public static function substituteConstants($value, array $constants)
    {
        if (is_string($value)) {
            return preg_replace_callback('/\{\{(\w+)\}\}/u', static function ($m) use ($constants) {
                return array_key_exists($m[1], $constants) ? (string) $constants[$m[1]] : $m[0];
            }, $value);
        }
        if (is_array($value)) {
            $out = [];
            foreach ($value as $k => $v) {
                $out[$k] = self::substituteConstants($v, $constants);
            }
            return $out;
        }
        return $value;
    }
}
