<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * setConfigs — set several Moodle configuration values at once.
 *
 * Supports both shapes seen in the ecosystem:
 *
 *   Object map (alpine-moodle docs):
 *     { "step": "setConfigs", "values": { "debug": 32767, "debugdisplay": 1 } }
 *     { "step": "setConfigs", "configs": { "debug": 32767 } }
 *
 *   Array of descriptors (Moodle Playground):
 *     { "step": "setConfigs", "configs": [ { "name": "debug", "value": 32767, "plugin": null } ] }
 */
class SetConfigsStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $entries = $this->collectEntries($config);
        if ($entries === []) {
            throw new BlueprintException('setConfigs requires a non-empty "values" or "configs" map/array.');
        }

        foreach ($entries as $entry) {
            SetConfigStep::apply($context, $entry['name'], $this->coerceConfigValue($entry['value']), $entry['plugin']);
        }
    }

    /**
     * Normalise the various accepted shapes into a list of
     * ['name' => string, 'value' => mixed, 'plugin' => ?string].
     *
     * @param array<string,mixed> $config
     * @return array<int,array{name:string,value:mixed,plugin:?string}>
     */
    private function collectEntries(array $config): array
    {
        $entries = [];

        if (isset($config['values']) && is_array($config['values'])) {
            foreach ($config['values'] as $name => $value) {
                $entries[] = ['name' => (string) $name, 'value' => $value, 'plugin' => null];
            }
        }

        if (isset($config['configs']) && is_array($config['configs'])) {
            $configs = $config['configs'];
            $isList = array_keys($configs) === range(0, count($configs) - 1);
            if ($isList) {
                foreach ($configs as $item) {
                    if (!is_array($item) || !isset($item['name'])) {
                        throw new BlueprintException('Each "configs" array entry must be an object with a "name".');
                    }
                    $entries[] = [
                        'name' => (string) $item['name'],
                        'value' => $item['value'] ?? '',
                        'plugin' => isset($item['plugin']) && $item['plugin'] !== null ? (string) $item['plugin'] : null,
                    ];
                }
            } else {
                foreach ($configs as $name => $value) {
                    $entries[] = ['name' => (string) $name, 'value' => $value, 'plugin' => null];
                }
            }
        }

        return $entries;
    }
}
