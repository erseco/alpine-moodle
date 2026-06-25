<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * createCourse — create a course (idempotent by shortname).
 *
 * Input:
 *   { "step": "createCourse", "fullname": "Demo course",
 *     "shortname": "DEMO101", "category": "Demo",
 *     "summary": "...", "format": "topics", "numsections": 5 }
 *
 * If a course with the same shortname exists, its basic fields are updated
 * instead of creating a duplicate. The category is resolved by idnumber or
 * name; an unknown explicit category is an error.
 */
class CreateCourseStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $this->requireMoodle();
        global $DB, $CFG;
        require_once($CFG->dirroot . '/course/lib.php');

        $fullname = $this->requireString($config, 'fullname');
        $shortname = $this->requireString($config, 'shortname');
        $summary = $this->optString($config, 'summary');
        $format = $this->optString($config, 'format');

        $categoryid = $this->resolveCategory($config);

        $existing = $DB->get_record('course', ['shortname' => $shortname]);
        if ($existing) {
            $update = (object) ['id' => $existing->id, 'fullname' => $fullname];
            if ($summary !== '') {
                $update->summary = $summary;
            }
            update_course($update);
            $context->logger()->info(sprintf('Course "%s" already existed; basic fields updated (id=%d).', $shortname, $existing->id));
            return;
        }

        $course = (object) [
            'fullname' => $fullname,
            'shortname' => $shortname,
            'category' => $categoryid,
            'summary' => $summary,
            'summaryformat' => FORMAT_HTML,
        ];
        if ($format !== '') {
            $course->format = $format;
        }
        if (isset($config['numsections']) && is_numeric($config['numsections'])) {
            $course->numsections = (int) $config['numsections'];
        }

        $created = create_course($course);
        $context->logger()->info(sprintf('Created course "%s" (id=%d).', $shortname, $created->id));
    }

    /**
     * Resolve the destination category id. Defaults to the first available
     * category when none is specified.
     *
     * @param array<string,mixed> $config
     */
    private function resolveCategory(array $config): int
    {
        global $DB;
        $category = $this->optString($config, 'category');
        if ($category === '') {
            $first = $DB->get_records('course_categories', null, 'sortorder ASC', 'id', 0, 1);
            if ($first) {
                return (int) reset($first)->id;
            }
            throw new BlueprintException('No course category available to create the course in.');
        }
        $id = CreateCategoryStep::resolveCategoryId($category);
        if ($id === 0) {
            throw new BlueprintException(sprintf('Category "%s" not found for course.', $category));
        }
        return $id;
    }
}
