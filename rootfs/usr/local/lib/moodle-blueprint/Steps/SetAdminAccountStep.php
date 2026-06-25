<?php

namespace MoodleBlueprint\Steps;

use MoodleBlueprint\BlueprintException;
use MoodleBlueprint\RunContext;

/**
 * setAdminAccount — update the primary admin account.
 *
 * Input (all fields optional):
 *   { "step": "setAdminAccount", "username": "admin", "password": "...",
 *     "email": "admin@example.com", "firstname": "Admin", "lastname": "User" }
 *
 * When username, password and email are all provided, the existing
 * admin/cli/update_admin_user.php helper is reused. Partial updates (and the
 * optional firstname/lastname fields) go through the Moodle API. The password
 * is never written to the logs.
 */
class SetAdminAccountStep extends AbstractStep
{
    public function run(RunContext $context, array $config, int $index): void
    {
        $username = $this->optString($config, 'username');
        $password = $this->optString($config, 'password');
        $email = $this->optString($config, 'email');
        $firstname = $this->optString($config, 'firstname');
        $lastname = $this->optString($config, 'lastname');

        if ($username === '' && $password === '' && $email === '' && $firstname === '' && $lastname === '') {
            throw new BlueprintException('setAdminAccount requires at least one field to update.');
        }

        $fullTriple = $username !== '' && $password !== '' && $email !== '';
        $needsApi = $firstname !== '' || $lastname !== '' || !$fullTriple;

        if (!$needsApi) {
            // Preferred path: reuse the proven CLI helper for the common case.
            $context->runMoodleCli('update_admin_user.php', [
                '--username=' . $username,
                '--password=' . $password,
                '--email=' . $email,
            ]);
            $context->logger()->info('Admin account updated (username/email/password).');
            return;
        }

        $this->updateViaApi($context, $username, $password, $email, $firstname, $lastname);
    }

    private function updateViaApi(
        RunContext $context,
        string $username,
        string $password,
        string $email,
        string $firstname,
        string $lastname
    ): void {
        $this->requireMoodle();
        global $DB;

        $admin = get_admin();
        if (!$admin) {
            throw new BlueprintException('No admin user found to update.');
        }

        if ($username !== '') {
            $admin->username = $username;
        }
        if ($email !== '') {
            $admin->email = $email;
        }
        if ($firstname !== '') {
            $admin->firstname = $firstname;
        }
        if ($lastname !== '') {
            $admin->lastname = $lastname;
        }
        $DB->update_record('user', $admin);

        if ($password !== '') {
            update_internal_user_password($admin, $password);
        }

        $context->logger()->info('Admin account updated via Moodle API.');
    }
}
