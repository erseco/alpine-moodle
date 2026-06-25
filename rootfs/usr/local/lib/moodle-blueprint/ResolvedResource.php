<?php

namespace MoodleBlueprint;

/**
 * A resolved resource: the bytes a step needs, available either as an in-memory
 * string or as a path to a real file (materialised on demand).
 */
class ResolvedResource
{
    /** @var string|null In-memory contents, when known. */
    private $contents;

    /** @var string|null Path to a file holding the contents, when known. */
    private $path;

    /** @var string Directory used to materialise temporary files. */
    private $workDir;

    /** @var string A label used for nicer log/error messages. */
    private $label;

    private function __construct(string $workDir, string $label)
    {
        $this->workDir = $workDir;
        $this->label = $label;
    }

    public static function fromContents(string $contents, string $workDir, string $label = 'resource'): self
    {
        $resource = new self($workDir, $label);
        $resource->contents = $contents;
        return $resource;
    }

    public static function fromPath(string $path, string $workDir, string $label = 'resource'): self
    {
        $resource = new self($workDir, $label);
        $resource->path = $path;
        return $resource;
    }

    public function label(): string
    {
        return $this->label;
    }

    /**
     * Return the resource contents as a string, reading the backing file if the
     * resource was provided as a path.
     */
    public function contents(): string
    {
        if ($this->contents !== null) {
            return $this->contents;
        }
        if ($this->path !== null) {
            $data = file_get_contents($this->path);
            if ($data === false) {
                throw new BlueprintException(sprintf('Unable to read resource "%s".', $this->label));
            }
            return $data;
        }
        throw new BlueprintException(sprintf('Resource "%s" has no contents.', $this->label));
    }

    /**
     * Return a filesystem path to a file holding the resource bytes, writing a
     * temporary file when the resource only exists in memory.
     */
    public function path(): string
    {
        if ($this->path !== null) {
            return $this->path;
        }
        if ($this->contents !== null) {
            $tmp = $this->workDir . '/' . 'res_' . substr(sha1($this->label . $this->contents), 0, 16) . '.bin';
            if (file_put_contents($tmp, $this->contents) === false) {
                throw new BlueprintException(sprintf('Unable to materialise resource "%s".', $this->label));
            }
            $this->path = $tmp;
            return $this->path;
        }
        throw new BlueprintException(sprintf('Resource "%s" has no path.', $this->label));
    }
}
