<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * enrolUser — enrol a user into a course via manual enrolment (idempotent).
 *
 * Input:
 *   { "step": "enrolUser", "username": "student1",
 *     "course": "DEMO101", "role": "student" }
 *
 * Resolves the user by username, the course by shortname and the role by
 * shortname, then enrols through the manual enrolment plugin. Re-running does
 * not create duplicate enrolments.
 */
class EnrolUserStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $this->requireMoodle();
        global $DB, $CFG;

        $username = $this->requireString($config, 'username');
        $courseShortname = $this->requireString($config, 'course');
        $roleShortname = $this->optString($config, 'role', 'student');

        $user = $DB->get_record('user', ['username' => \core_text::strtolower($username)]);
        if (!$user) {
            throw new BlueprintException(sprintf('Cannot enrol: user "%s" not found.', $username));
        }
        $course = $DB->get_record('course', ['shortname' => $courseShortname]);
        if (!$course) {
            throw new BlueprintException(sprintf('Cannot enrol: course "%s" not found.', $courseShortname));
        }
        $role = $DB->get_record('role', ['shortname' => $roleShortname]);
        if (!$role) {
            throw new BlueprintException(sprintf('Cannot enrol: role "%s" not found.', $roleShortname));
        }

        $plugin = enrol_get_plugin('manual');
        if (!$plugin) {
            throw new BlueprintException('Manual enrolment plugin is not available.');
        }

        $instance = $DB->get_record('enrol', ['courseid' => $course->id, 'enrol' => 'manual']);
        if (!$instance) {
            $instanceid = $plugin->add_instance($course);
            $instance = $DB->get_record('enrol', ['id' => $instanceid], '*', MUST_EXIST);
        }

        // enrol_user is safe to call repeatedly; it updates rather than duplicates.
        $plugin->enrol_user($instance, $user->id, $role->id);

        $context->logger()->info(sprintf(
            'Enrolled "%s" into "%s" as "%s".',
            $username,
            $courseShortname,
            $roleShortname
        ));
    }
}
