<?php

namespace MoodleBlueprint;

/**
 * Safe ZIP extraction.
 *
 * Extraction is performed entry-by-entry, writing only regular files and
 * directories whose destination has been validated to stay inside the target
 * directory. Symlink entries are never honoured, which — combined with the
 * SecurityPolicy path checks — defeats ZIP slip and symlink-escape attacks.
 */
class Archive
{
    /** Maximum number of entries an archive may contain (inode-exhaustion guard). */
    private const MAX_ENTRIES = 20000;

    /**
     * Return true if $path is a readable ZIP archive.
     */
    public static function isZip(string $path): bool
    {
        if (!class_exists('ZipArchive')) {
            return false;
        }
        $zip = new \ZipArchive();
        $opened = $zip->open($path);
        if ($opened === true) {
            $zip->close();
            return true;
        }
        return false;
    }

    /**
     * Safely extract a ZIP archive into $destDir.
     *
     * @throws BlueprintException on any unsafe entry or extraction failure.
     */
    public static function extract(SecurityPolicy $policy, string $zipPath, string $destDir): void
    {
        if (!class_exists('ZipArchive')) {
            throw new BlueprintException('The PHP zip extension (ZipArchive) is required to extract archives.');
        }

        $zip = new \ZipArchive();
        if ($zip->open($zipPath) !== true) {
            throw new BlueprintException(sprintf('Unable to open ZIP archive "%s".', $zipPath));
        }

        if (!is_dir($destDir) && !mkdir($destDir, 0775, true) && !is_dir($destDir)) {
            $zip->close();
            throw new BlueprintException(sprintf('Unable to create extraction directory "%s".', $destDir));
        }

        // Guard against zip bombs and inode exhaustion. The cumulative byte
        // counter during extraction is authoritative; the up-front declared-size
        // check below rejects obvious bombs before any bytes are written.
        $maxBytes = $policy->maxArchiveSize();
        if ($zip->numFiles > self::MAX_ENTRIES) {
            $zip->close();
            throw new BlueprintException(sprintf('Archive has too many entries (%d > %d).', $zip->numFiles, self::MAX_ENTRIES));
        }

        $declaredTotal = 0;
        $writtenTotal = 0;

        try {
            for ($i = 0; $i < $zip->numFiles; $i++) {
                $name = $zip->getNameIndex($i);
                if ($name === false || $name === '') {
                    continue;
                }

                // The macOS archiver adds a __MACOSX metadata tree; ignore it.
                if ($name === '__MACOSX' || strncmp($name, '__MACOSX/', 9) === 0) {
                    continue;
                }

                $isDir = substr($name, -1) === '/';
                $clean = rtrim($name, '/');
                $policy->assertSafeArchiveEntry($clean);
                $target = $policy->safeJoin($destDir, $clean);

                if ($isDir) {
                    if (!is_dir($target) && !mkdir($target, 0775, true) && !is_dir($target)) {
                        throw new BlueprintException(sprintf('Unable to create directory "%s".', $clean));
                    }
                    continue;
                }

                // Reject obvious bombs using the declared uncompressed size.
                $stat = $zip->statIndex($i);
                if (is_array($stat) && isset($stat['size'])) {
                    $declaredTotal += (int) $stat['size'];
                    if ($declaredTotal > $maxBytes) {
                        throw new BlueprintException(sprintf(
                            'Archive decompresses to more than the %d byte limit (possible zip bomb).',
                            $maxBytes
                        ));
                    }
                }

                $parent = dirname($target);
                if (!is_dir($parent) && !mkdir($parent, 0775, true) && !is_dir($parent)) {
                    throw new BlueprintException(sprintf('Unable to create directory "%s".', $parent));
                }

                $in = $zip->getStream($name);
                if ($in === false) {
                    throw new BlueprintException(sprintf('Unable to read archive entry "%s".', $name));
                }
                $out = fopen($target, 'wb');
                if ($out === false) {
                    fclose($in);
                    throw new BlueprintException(sprintf('Unable to write extracted file "%s".', $clean));
                }

                // Copy in bounded chunks, enforcing the cumulative cap so a lying
                // header cannot bypass the declared-size check above.
                while (!feof($in)) {
                    $chunk = fread($in, 65536);
                    if ($chunk === false) {
                        break;
                    }
                    $writtenTotal += strlen($chunk);
                    if ($writtenTotal > $maxBytes) {
                        fclose($in);
                        fclose($out);
                        @unlink($target);
                        throw new BlueprintException(sprintf(
                            'Archive decompresses to more than the %d byte limit (possible zip bomb).',
                            $maxBytes
                        ));
                    }
                    if (fwrite($out, $chunk) === false) {
                        fclose($in);
                        fclose($out);
                        throw new BlueprintException(sprintf('Unable to write extracted file "%s".', $clean));
                    }
                }
                fclose($in);
                fclose($out);
            }
        } finally {
            $zip->close();
        }
    }
}
