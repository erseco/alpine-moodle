<?php

namespace MoodleBlueprint;

/**
 * Minimal, size-bounded HTTP downloader.
 *
 * Uses PHP streams when allow_url_fopen is available and falls back to the
 * curl binary otherwise. Downloads are always capped at $maxBytes to protect
 * the container from oversized or runaway responses.
 */
class Http
{
    /**
     * Download a URL and return its contents, enforcing a hard byte cap.
     *
     * @throws BlueprintException on any failure or when the cap is exceeded.
     */
    public static function download(string $url, int $maxBytes, Logger $logger, string $workDir): string
    {
        $scheme = strtolower((string) parse_url($url, PHP_URL_SCHEME));
        if ($scheme !== 'http' && $scheme !== 'https') {
            throw new BlueprintException(sprintf('Unsupported URL scheme "%s"; only http/https are allowed.', $scheme));
        }

        $context = stream_context_create([
            'http' => [
                'method' => 'GET',
                'follow_location' => 1,
                'max_redirects' => 5,
                'timeout' => 60,
                'user_agent' => 'alpine-moodle-blueprint/1.0',
            ],
            'https' => [
                'timeout' => 60,
                'user_agent' => 'alpine-moodle-blueprint/1.0',
            ],
        ]);

        $stream = @fopen($url, 'rb', false, $context);
        if ($stream === false) {
            return self::downloadWithCurl($url, $maxBytes, $workDir);
        }

        $contents = '';
        while (!feof($stream)) {
            $chunk = fread($stream, 8192);
            if ($chunk === false) {
                break;
            }
            $contents .= $chunk;
            if (strlen($contents) > $maxBytes) {
                fclose($stream);
                throw new BlueprintException(sprintf(
                    'Resource "%s" exceeds the %d byte limit (MOODLE_BLUEPRINT_MAX_RESOURCE_SIZE).',
                    $url,
                    $maxBytes
                ));
            }
        }
        fclose($stream);

        if ($contents === '') {
            throw new BlueprintException(sprintf('Failed to download "%s" (empty response).', $url));
        }
        return $contents;
    }

    /**
     * Fallback download via the curl binary, bounded by --max-filesize.
     */
    private static function downloadWithCurl(string $url, int $maxBytes, string $workDir): string
    {
        $tmp = $workDir . '/dl_' . substr(sha1($url), 0, 16) . '.bin';
        $cmd = sprintf(
            'curl --silent --show-error --location --fail --max-time 60 --max-filesize %d --output %s %s 2>&1',
            $maxBytes,
            escapeshellarg($tmp),
            escapeshellarg($url)
        );
        exec($cmd, $output, $status);
        if ($status !== 0 || !is_file($tmp)) {
            throw new BlueprintException(sprintf(
                'Failed to download "%s": %s',
                $url,
                trim(implode("\n", $output))
            ));
        }
        $contents = file_get_contents($tmp);
        @unlink($tmp);
        if ($contents === false) {
            throw new BlueprintException(sprintf('Failed to read downloaded file from "%s".', $url));
        }
        if (strlen($contents) > $maxBytes) {
            throw new BlueprintException(sprintf('Resource "%s" exceeds the %d byte limit.', $url, $maxBytes));
        }
        return $contents;
    }
}
