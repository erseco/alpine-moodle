<?php
/**
 * Parser tests: invalid JSON, missing steps, step validation, constants and
 * the idempotency hash.
 */

require __DIR__ . '/bootstrap.php';

use MoodleBlueprint\Blueprint;
use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\BlueprintParser;

$parser = new BlueprintParser();

it('rejects invalid JSON', function () use ($parser) {
    assert_throws(BlueprintException::class, function () use ($parser) {
        $parser->parse('{ not valid json');
    }, 'Invalid blueprint JSON');
});

it('rejects a non-object blueprint', function () use ($parser) {
    assert_throws(BlueprintException::class, function () use ($parser) {
        $parser->parse('[1, 2, 3]');
    }, 'must be a JSON object');
});

it('rejects a blueprint without steps', function () use ($parser) {
    assert_throws(BlueprintException::class, function () use ($parser) {
        $parser->parse('{"landingPage": "/"}');
    }, 'must contain a "steps" array');
});

it('rejects steps that are not an array', function () use ($parser) {
    assert_throws(BlueprintException::class, function () use ($parser) {
        $parser->parse('{"steps": {"step": "setConfig"}}');
    }, 'must be an array');
});

it('rejects a step missing its "step" name', function () use ($parser) {
    assert_throws(BlueprintException::class, function () use ($parser) {
        $parser->parse('{"steps": [{"name": "debug"}]}');
    }, 'non-empty "step" name');
});

it('accepts an empty steps array', function () use ($parser) {
    $bp = $parser->parse('{"steps": []}');
    assert_eq($bp->steps(), []);
});

it('preserves unknown top-level fields', function () use ($parser) {
    $bp = $parser->parse('{"futureField": {"a": 1}, "steps": []}');
    $data = $bp->data();
    assert_true(isset($data['futureField']), 'unknown field preserved');
    assert_eq($data['futureField']['a'], 1);
});

it('substitutes {{CONSTANTS}} in string values', function () use ($parser) {
    $json = '{"constants": {"NAME": "Demo"}, "steps": [{"step": "createCategory", "name": "{{NAME}} Category"}]}';
    $bp = $parser->parse($json);
    assert_eq($bp->steps()[0]['name'], 'Demo Category');
});

it('leaves unknown placeholders untouched', function () use ($parser) {
    $json = '{"constants": {"A": "x"}, "steps": [{"step": "setConfig", "name": "{{MISSING}}"}]}';
    $bp = $parser->parse($json);
    assert_eq($bp->steps()[0]['name'], '{{MISSING}}');
});

it('produces a stable hash regardless of key order or whitespace', function () use ($parser) {
    $a = $parser->parse('{"landingPage":"/","steps":[{"step":"setConfig","name":"debug","value":1}]}');
    $b = $parser->parse("{\n  \"steps\": [ { \"value\": 1, \"name\": \"debug\", \"step\": \"setConfig\" } ],\n  \"landingPage\": \"/\"\n}");
    assert_eq($a->canonicalHash(), $b->canonicalHash(), 'hash is order/whitespace independent');
});

it('changes the hash when content changes', function () use ($parser) {
    $a = $parser->parse('{"steps":[{"step":"setConfig","name":"debug","value":1}]}');
    $b = $parser->parse('{"steps":[{"step":"setConfig","name":"debug","value":2}]}');
    assert_true($a->canonicalHash() !== $b->canonicalHash(), 'different content => different hash');
});

it('parses the demo fixture and exposes resources/constants', function () use ($parser) {
    $bp = $parser->parseFile(__DIR__ . '/fixtures/demo.blueprint.json');
    assert_eq(count($bp->steps()), 5);
    assert_eq($bp->landingPage(), '/course/index.php');
    // Constant substituted into the category name.
    assert_eq($bp->steps()[1]['name'], 'Blueprint demo');
});
