<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * createUsers — create or update several users.
 *
 * Input:
 *   { "step": "createUsers", "users": [ { "username": "student1", ... } ] }
 */
class CreateUsersStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $this->requireMoodle();
        if (!isset($config['users']) || !is_array($config['users'])) {
            throw new BlueprintException('createUsers requires a "users" array.');
        }

        foreach ($config['users'] as $i => $user) {
            if (!is_array($user)) {
                throw new BlueprintException(sprintf('createUsers entry %d must be an object.', $i));
            }
            $id = CreateUserStep::createOrUpdate($context, $user);
            $context->logger()->info(sprintf('User "%s" ready (id=%d).', $user['username'] ?? '?', $id));
        }
    }
}
