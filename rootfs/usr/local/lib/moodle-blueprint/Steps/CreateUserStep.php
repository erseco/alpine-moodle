<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * createUser — create a user (idempotent by username).
 *
 * Input:
 *   { "step": "createUser", "username": "student1", "password": "...",
 *     "email": "student1@example.com", "firstname": "Student", "lastname": "One" }
 *
 * If the user exists, basic profile fields are updated; the password is only
 * changed when one is explicitly provided. Passwords are never logged.
 */
class CreateUserStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $this->requireMoodle();
        $id = self::createOrUpdate($context, $config);
        $context->logger()->info(sprintf('User "%s" ready (id=%d).', $config['username'], $id));
    }

    /**
     * Create or update a user from a config array and return its id.
     *
     * @param array<string,mixed> $config
     */
    public static function createOrUpdate(RunContext $context, array $config): int
    {
        global $DB, $CFG;
        require_once($CFG->dirroot . '/user/lib.php');

        if (!isset($config['username']) || !is_string($config['username']) || $config['username'] === '') {
            throw new BlueprintException('createUser requires a "username".');
        }
        $username = \core_text::strtolower(trim($config['username']));
        $password = isset($config['password']) && is_scalar($config['password']) ? (string) $config['password'] : '';

        $existing = $DB->get_record('user', ['username' => $username, 'mnethostid' => $CFG->mnet_localhost_id]);
        if ($existing) {
            $update = (object) ['id' => $existing->id];
            foreach (['email', 'firstname', 'lastname'] as $field) {
                if (isset($config[$field]) && is_scalar($config[$field]) && (string) $config[$field] !== '') {
                    $update->$field = (string) $config[$field];
                }
            }
            user_update_user($update, false, false);
            if ($password !== '') {
                update_internal_user_password($existing, $password);
            }
            return (int) $existing->id;
        }

        $user = (object) [
            'username' => $username,
            'auth' => self::stringOr($config, 'auth', 'manual'),
            'confirmed' => 1,
            'mnethostid' => $CFG->mnet_localhost_id,
            'email' => self::stringOr($config, 'email', $username . '@example.com'),
            'firstname' => self::stringOr($config, 'firstname', $username),
            'lastname' => self::stringOr($config, 'lastname', 'User'),
            'lang' => self::stringOr($config, 'lang', $CFG->lang ?? 'en'),
        ];
        // A valid local account needs a password; generate one when none is
        // supplied (never logged) so the account is usable.
        $user->password = $password !== '' ? $password : self::randomPassword();

        $id = user_create_user($user, true, false);
        return (int) $id;
    }

    /**
     * @param array<string,mixed> $config
     */
    private static function stringOr(array $config, string $key, string $default): string
    {
        return isset($config[$key]) && is_scalar($config[$key]) && (string) $config[$key] !== ''
            ? (string) $config[$key]
            : $default;
    }

    private static function randomPassword(): string
    {
        // Mixed-class password to satisfy default Moodle password policy.
        return 'Bp!' . bin2hex(random_bytes(8)) . 'A1';
    }
}
