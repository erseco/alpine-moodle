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
                stream_copy_to_stream($in, $out);
                fclose($in);
                fclose($out);
            }
        } finally {
            $zip->close();
        }
    }
}
