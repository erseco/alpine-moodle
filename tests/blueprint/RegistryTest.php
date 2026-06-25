<?php
/**
 * StepRegistry tests: step classification and handler instantiation.
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\StepRegistry;
use MoodleBlueprint\Steps\StepInterface;

$registry = new StepRegistry();

it('classifies implemented steps', function () use ($registry) {
    foreach (['setConfig', 'setConfigs', 'createCourse', 'enrolUser', 'installMoodlePlugin'] as $name) {
        assert_eq($registry->classify($name), StepRegistry::IMPLEMENTED, $name);
    }
});

it('classifies container/browser steps as no-op', function () use ($registry) {
    assert_eq($registry->classify('installMoodle'), StepRegistry::NOOP);
    assert_eq($registry->classify('login'), StepRegistry::NOOP);
});

it('classifies unsafe steps', function () use ($registry) {
    foreach (['runPhpCode', 'runPhpScript', 'writeFile', 'unzip', 'mkdir', 'request'] as $name) {
        assert_eq($registry->classify($name), StepRegistry::UNSAFE, $name);
    }
});

it('classifies recognised-but-unimplemented steps as planned', function () use ($registry) {
    foreach (['restoreCourse', 'addModule', 'installLanguagePack', 'createRole'] as $name) {
        assert_eq($registry->classify($name), StepRegistry::PLANNED, $name);
    }
});

it('classifies truly unknown steps as unknown', function () use ($registry) {
    assert_eq($registry->classify('totallyMadeUpStep'), StepRegistry::UNKNOWN);
});

it('returns a StepInterface handler for implemented steps', function () use ($registry) {
    $handler = $registry->handler('setConfig');
    assert_true($handler instanceof StepInterface, 'handler implements StepInterface');
});

it('lists exactly the implemented steps', function () use ($registry) {
    $expected = [
        'setConfig', 'setConfigs', 'setAdminAccount', 'installMoodlePlugin',
        'installTheme', 'setTheme', 'createCategory', 'createCourse',
        'createUser', 'createUsers', 'enrolUser',
    ];
    sort($expected);
    $actual = $registry->implementedSteps();
    sort($actual);
    assert_eq($actual, $expected);
});
