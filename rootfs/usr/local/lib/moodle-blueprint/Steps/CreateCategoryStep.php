<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * createCategory — create a course category (idempotent).
 *
 * Input:
 *   { "step": "createCategory", "name": "Demo",
 *     "idnumber": "demo", "parent": "Parent category", "description": "..." }
 *
 * Idempotent by idnumber when provided, otherwise by name under the same
 * parent. Returns/logs the resulting category id.
 */
class CreateCategoryStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $this->requireMoodle();
        $id = self::createOrGet(
            $context,
            $this->requireString($config, 'name'),
            $this->optString($config, 'idnumber'),
            $this->optString($config, 'parent'),
            $this->optString($config, 'description')
        );
        $context->logger()->info(sprintf('Category "%s" ready (id=%d).', $config['name'], $id));
    }

    /**
     * Create the category if missing and return its id.
     */
    public static function createOrGet(
        RunContext $context,
        string $name,
        string $idnumber = '',
        string $parent = '',
        string $description = ''
    ): int {
        global $DB;

        $parentid = 0;
        if ($parent !== '') {
            $parentid = self::resolveCategoryId($parent);
            if ($parentid === 0) {
                throw new BlueprintException(sprintf('Parent category "%s" not found.', $parent));
            }
        }

        // Idempotency check.
        if ($idnumber !== '') {
            $existing = $DB->get_record('course_categories', ['idnumber' => $idnumber]);
        } else {
            $existing = $DB->get_record('course_categories', ['name' => $name, 'parent' => $parentid]);
        }
        if ($existing) {
            return (int) $existing->id;
        }

        $data = ['name' => $name, 'parent' => $parentid];
        if ($idnumber !== '') {
            $data['idnumber'] = $idnumber;
        }
        if ($description !== '') {
            $data['description'] = $description;
        }

        $category = \core_course_category::create((object) $data);
        return (int) $category->id;
    }

    /**
     * Resolve a category by idnumber first, then by name. Returns 0 if none.
     */
    public static function resolveCategoryId(string $reference): int
    {
        global $DB;
        $record = $DB->get_record('course_categories', ['idnumber' => $reference]);
        if (!$record) {
            $record = $DB->get_record('course_categories', ['name' => $reference], '*', IGNORE_MULTIPLE);
        }
        return $record ? (int) $record->id : 0;
    }
}
