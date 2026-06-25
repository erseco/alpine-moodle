<?php

namespace MoodleBlueprint;

/**
 * Maps a Moodle frankenstyle component (e.g. "mod_quiz") to its install
 * directory relative to the Moodle code root.
 *
 * The plugin-type table mirrors rootfs/docker-entrypoint-init.d/015-copy-plugins.sh
 * so blueprint plugin installs land in exactly the same places as the existing
 * PLUGINS mechanism.
 */
class Frankenstyle
{
    /** @var array<string,string> plugin type => path relative to Moodle root */
    private const TYPE_DIRS = [
        'mod'                => 'mod',
        'block'              => 'blocks',
        'theme'              => 'theme',
        'local'              => 'local',
        'report'             => 'report',
        'auth'               => 'auth',
        'filter'             => 'filter',
        'gradeexport'        => 'grade/export',
        'gradeimport'        => 'grade/import',
        'gradereport'        => 'grade/report',
        'message'            => 'message/output',
        'tool'               => 'admin/tool',
        'profilefield'       => 'user/profile/field',
        'quiz'               => 'mod/quiz/report',
        'quizaccess'         => 'mod/quiz/accessrule',
        'plagiarism'         => 'plagiarism',
        'portfolio'          => 'portfolio',
        'repository'         => 'repository',
        'search'             => 'search/engine',
        'reportbuilder'      => 'reportbuilder/source',
        'payment'            => 'payment/gateway',
        'paygw'              => 'payment/gateway',
        'enrol'              => 'enrol',
        'assignfeedback'     => 'mod/assign/feedback',
        'assignsubmission'   => 'mod/assign/submission',
        'workshopallocation' => 'mod/workshop/allocation',
        'workshopform'       => 'mod/workshop/form',
        'workshopeval'       => 'mod/workshop/eval',
        'question'           => 'question/type',
        'qtype'              => 'question/type',
        'qbehaviour'         => 'question/behaviour',
        'qformat'            => 'question/format',
        'qbank'              => 'question/bank',
        'editor'             => 'lib/editor',
        'tiny'               => 'lib/editor/tiny/plugins',
        'atto'               => 'lib/editor/atto/plugins',
        'tinymce'            => 'lib/editor/tinymce/plugins',
        'availability'       => 'availability/condition',
        'datafield'          => 'mod/data/field',
        'datapreset'         => 'mod/data/preset',
        'scormreport'        => 'mod/scorm/report',
        'ltisource'          => 'mod/lti/source',
        'contenttype'        => 'contentbank/contenttype',
        'format'             => 'course/format',
        'customfield'        => 'customfield/field',
        'analytics'          => 'analytics/indicator',
        'aiprovider'         => 'ai/provider',
        'aiplacement'        => 'ai/placement',
        'cachelock'          => 'cache/locks',
        'cachestore'         => 'cache/stores',
        'logstore'           => 'admin/tool/log/store',
        'calendartype'       => 'calendar/type',
        'media'              => 'media/player',
        'webservice'         => 'webservice',
        'coursereport'       => 'course/report',
        'mlbackend'          => 'lib/mlbackend',
        'fileconverter'      => 'files/converter',
        'antivirus'          => 'lib/antivirus',
        'h5plib'             => 'h5p/h5plib',
    ];

    /**
     * Resolve the install directory for a frankenstyle component relative to
     * the Moodle code root.
     *
     * @return string Path relative to the Moodle root (e.g. "mod/quiz").
     * @throws BlueprintException for unknown plugin types.
     */
    public static function relativePath(string $component): string
    {
        if (strpos($component, '_') === false) {
            throw new BlueprintException(sprintf('Invalid frankenstyle component "%s" (expected type_name).', $component));
        }
        [$type, $name] = explode('_', $component, 2);
        if ($type === '' || $name === '' || !preg_match('/^[a-z][a-z0-9_]*$/', $name)) {
            throw new BlueprintException(sprintf('Invalid frankenstyle component "%s".', $component));
        }
        if (!isset(self::TYPE_DIRS[$type])) {
            throw new BlueprintException(sprintf('Unknown plugin type "%s" for component "%s".', $type, $component));
        }
        return self::TYPE_DIRS[$type] . '/' . $name;
    }
}
