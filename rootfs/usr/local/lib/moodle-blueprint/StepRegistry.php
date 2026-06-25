<?php

namespace MoodleBlueprint;

/**
 * Maps blueprint step names to their handler classes and classifies every
 * other Moodle Playground step so the runner can react predictably:
 *
 *   - IMPLEMENTED : run the handler.
 *   - NO-OP       : intentionally skipped in Docker (e.g. installMoodle/login),
 *                   logged loudly rather than silently ignored.
 *   - PLANNED     : a recognised Moodle Playground step not yet implemented by
 *                   the Docker runtime — fails clearly.
 *   - UNSAFE      : arbitrary code/file operations, disabled by default.
 *   - UNKNOWN     : not a recognised step — fails clearly.
 */
class StepRegistry
{
    public const IMPLEMENTED = 'implemented';
    public const NOOP = 'noop';
    public const PLANNED = 'planned';
    public const UNSAFE = 'unsafe';
    public const UNKNOWN = 'unknown';

    /** @var array<string,string> step name => handler class */
    private const HANDLERS = [
        'setConfig'           => Steps\SetConfigStep::class,
        'setConfigs'          => Steps\SetConfigsStep::class,
        'setAdminAccount'     => Steps\SetAdminAccountStep::class,
        'installMoodlePlugin' => Steps\InstallMoodlePluginStep::class,
        'installTheme'        => Steps\InstallThemeStep::class,
        'setTheme'            => Steps\SetThemeStep::class,
        'createCategory'      => Steps\CreateCategoryStep::class,
        'createCourse'        => Steps\CreateCourseStep::class,
        'createUser'          => Steps\CreateUserStep::class,
        'createUsers'         => Steps\CreateUsersStep::class,
        'enrolUser'           => Steps\EnrolUserStep::class,
    ];

    /**
     * Steps that have no meaning in the Docker runtime because the container
     * already handles them. Skipped with an explanatory log line.
     *
     * @var string[]
     */
    private const NOOP_STEPS = [
        'installMoodle', // Moodle is installed/upgraded by the container startup.
        'login',         // Browser-only auto-login; not applicable server-side.
    ];

    /**
     * Steps that perform arbitrary code or unrestricted file operations.
     * Disabled by default and not implemented in this version.
     *
     * @var string[]
     */
    private const UNSAFE_STEPS = [
        'runPhpCode', 'runPhpScript', 'runCli', 'request',
        'writeFile', 'writeFiles', 'unzip', 'mkdir', 'rmdir',
        'copyFile', 'moveFile',
    ];

    /**
     * Recognised Moodle Playground steps not yet implemented by the Docker
     * runtime. Listed so the runner can emit a "planned" message instead of an
     * "unknown step" error.
     *
     * @var string[]
     */
    private const PLANNED_STEPS = [
        'setConfigFile', 'setConfigFiles', 'setLandingPage',
        'createCategories', 'createCourses',
        'createSection', 'createSections',
        'enrolUsers', 'restoreCourse', 'addModule', 'installLanguagePack',
        'createRole', 'createRoles', 'importRolePreset', 'importRoles',
        'createScale', 'createScales', 'createCohort', 'createCohorts',
    ];

    /**
     * Classify a step name into one of the class constants above.
     */
    public function classify(string $name): string
    {
        if (isset(self::HANDLERS[$name])) {
            return self::IMPLEMENTED;
        }
        if (in_array($name, self::NOOP_STEPS, true)) {
            return self::NOOP;
        }
        if (in_array($name, self::UNSAFE_STEPS, true)) {
            return self::UNSAFE;
        }
        if (in_array($name, self::PLANNED_STEPS, true)) {
            return self::PLANNED;
        }
        return self::UNKNOWN;
    }

    /**
     * Instantiate the handler for an implemented step.
     */
    public function handler(string $name): Steps\StepInterface
    {
        if (!isset(self::HANDLERS[$name])) {
            throw new BlueprintException(sprintf('No handler registered for step "%s".', $name));
        }
        $class = self::HANDLERS[$name];
        return new $class();
    }

    /**
     * @return string[] Names of implemented steps.
     */
    public function implementedSteps(): array
    {
        return array_keys(self::HANDLERS);
    }
}
