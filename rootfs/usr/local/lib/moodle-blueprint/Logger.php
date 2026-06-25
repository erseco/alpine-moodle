<?php

namespace MoodleBlueprint;

/**
 * Tiny stdout/stderr logger with a consistent prefix.
 *
 * The runner never logs secret values directly; helpers here exist so callers
 * can scrub sensitive fields (passwords, tokens) before emitting a message.
 */
class Logger
{
    /** @var string Prefix prepended to every line. */
    private $prefix;

    /** Field names whose values must never be printed. */
    private const SECRET_KEYS = ['password', 'pass', 'pwd', 'secret', 'token', 'apikey', 'api_key', 'auth'];

    public function __construct(string $prefix = '[blueprint]')
    {
        $this->prefix = $prefix;
    }

    public function info(string $message): void
    {
        fwrite(STDOUT, $this->prefix . ' ' . $message . "\n");
    }

    public function warn(string $message): void
    {
        fwrite(STDERR, $this->prefix . ' WARNING: ' . $message . "\n");
    }

    public function error(string $message): void
    {
        fwrite(STDERR, $this->prefix . ' ERROR: ' . $message . "\n");
    }

    /**
     * Return a redacted copy of an associative array safe for logging.
     *
     * Any key that looks like a secret has its value replaced with "***".
     *
     * @param array<string,mixed> $data
     * @return array<string,mixed>
     */
    public static function redact(array $data): array
    {
        $safe = [];
        foreach ($data as $key => $value) {
            if (is_string($key) && in_array(strtolower($key), self::SECRET_KEYS, true)) {
                $safe[$key] = '***';
            } elseif (is_array($value)) {
                $safe[$key] = self::redact($value);
            } else {
                $safe[$key] = $value;
            }
        }
        return $safe;
    }
}
