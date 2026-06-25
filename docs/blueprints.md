# Moodle Playground Blueprints

!!! warning "Experimental"
    Blueprint support is **experimental** and currently implements a documented
    subset of steps. Unsupported steps fail clearly and unsafe steps are
    disabled by default. The blueprint runner never replaces the existing
    environment-variable configuration — it is an additional, declarative
    provisioning layer for repeatable development, QA, CI and demo scenarios.

`alpine-moodle` can apply [Moodle Playground](https://github.com/ateeducacion/moodle-playground)-compatible
`blueprint.json` files **after Moodle has been installed or upgraded**. A single
declarative blueprint can therefore describe one Moodle scenario and run in two
complementary, sibling runtimes:

- **[Moodle Playground](https://github.com/ateeducacion/moodle-playground)** — the
  browser/WASM runtime for **ephemeral QA, demos, shareable reproductions and
  fast validation**. No server required; perfect for sharing a link with a
  reviewer.
- **alpine-moodle** — this Docker runtime for **local development, CI, plugin
  development, integration testing, persistence and real server-side behaviour**
  (cron, mail, database, file system).

The two projects are **siblings**, not competitors: author a blueprint once, run
it in the browser for a quick look, and run the same file in Docker when you need
a real, persistent Moodle.

## How it works

A new startup hook, `rootfs/docker-entrypoint-init.d/03-apply-blueprint.sh`,
runs **after** `02-configure-moodle.sh` (i.e. after Moodle is installed or
upgraded). When any blueprint variable is set it calls the runner:

```text
/usr/local/bin/moodle-blueprint apply
```

The runner follows the same four phases as WordPress Playground: **declaration →
resource resolution → validation → step execution**, executing steps
sequentially and failing fast on the first error.

## Environment variables

| Variable                                  | Description                                        | Default |
| ----------------------------------------- | -------------------------------------------------- | ------- |
| `MOODLE_BLUEPRINT`                        | Path to a blueprint JSON file inside the container | empty   |
| `MOODLE_BLUEPRINT_URL`                    | Remote URL to a blueprint JSON file                | empty   |
| `MOODLE_BLUEPRINT_BUNDLE`                 | Path to a local bundle directory or ZIP            | empty   |
| `MOODLE_BLUEPRINT_FORCE`                  | Reapply even if already applied                    | `false` |
| `MOODLE_BLUEPRINT_ON_ERROR`               | `abort` or `warn`                                  | `abort` |
| `MOODLE_BLUEPRINT_ALLOW_REMOTE_RESOURCES` | Allow URL resources                                | `true`  |
| `MOODLE_BLUEPRINT_ALLOW_UNSAFE_STEPS`     | Allow unsafe steps if implemented                  | `false` |
| `MOODLE_BLUEPRINT_MAX_RESOURCE_SIZE`      | Max remote resource size                           | `50M`   |

- `MOODLE_BLUEPRINT_ON_ERROR=abort` fails container startup if blueprint
  application fails; `warn` prints a warning and continues startup.
- Secrets (passwords, tokens) are **never** written to the logs.

## Blueprint sources

Set one of the following. If several are set, this **precedence** applies:

1. `MOODLE_BLUEPRINT_BUNDLE`
2. `MOODLE_BLUEPRINT`
3. `MOODLE_BLUEPRINT_URL`

```sh
# 1. Local blueprint file
MOODLE_BLUEPRINT=/blueprints/demo.blueprint.json

# 2. Remote blueprint file (http/https only)
MOODLE_BLUEPRINT_URL=https://example.com/demo.blueprint.json

# 3. Local bundle directory
MOODLE_BLUEPRINT_BUNDLE=/blueprints/demo-bundle/

# 4. Local bundle ZIP
MOODLE_BLUEPRINT_BUNDLE=/blueprints/demo-bundle.zip
```

The selected source is printed in the logs.

## Blueprint format

```json
{
  "$schema": "https://raw.githubusercontent.com/ateeducacion/moodle-playground/main/assets/blueprints/blueprint-schema.json",
  "preferredVersions": {
    "php": "8.3",
    "moodle": "5.0"
  },
  "landingPage": "/course/view.php?id=2",
  "constants": {
    "ADMIN_USER": "admin"
  },
  "resources": {
    "pluginZip": {
      "url": "https://example.com/plugin.zip"
    }
  },
  "steps": [
    {
      "step": "setConfig",
      "name": "debug",
      "value": 32767
    }
  ]
}
```

The parser:

- loads JSON and fails clearly on syntax errors;
- requires `steps` to be an array, each entry carrying a non-empty `step` name;
- substitutes `{{KEY}}` placeholders from `constants` throughout the blueprint;
- resolves resource references like `@pluginZip`;
- **preserves unknown top-level fields** (e.g. `runtime`) without failing;
- fails clearly on unknown or unsupported step types, reporting the failing
  step index and name.

!!! note "`preferredVersions` and `landingPage` are advisory"
    The Docker image selects its Moodle/PHP version at build time, so
    `preferredVersions` is treated as a hint. `landingPage` is logged as a hint;
    the Docker runtime does not auto-navigate a browser.

## Resources

Declare named resources at the top level and reference them from steps with
`@name`, or inline a descriptor directly in a step. Supported descriptors:

```json
{ "url": "https://example.com/file.zip" }
{ "resource": "url", "url": "https://example.com/file.zip" }
{ "base64": "..." }
{ "data-url": "data:text/plain;base64,..." }
{ "literal": "text or JSON-compatible value" }
{ "bundled": "plugins/my-plugin.zip" }
{ "resource": "bundled", "path": "/plugins/my-plugin.zip" }
```

`bundled` paths are resolved relative to the extracted bundle directory. The
browser-only `vfs` resource type is rejected with a clear message. Resolved
resources are cached for the duration of a single run.

## Supported steps

| Step                  | Status      | Notes                                        |
| --------------------- | ----------- | -------------------------------------------- |
| `setConfig`           | supported   | Uses Moodle CLI (`admin/cli/cfg.php`)        |
| `setConfigs`          | supported   | Loops over `setConfig` (`values`/`configs`)  |
| `setAdminAccount`     | supported   | Password not logged                          |
| `installMoodlePlugin` | supported   | ZIP resources, safe extraction               |
| `installTheme`        | supported   | ZIP resources, enforces `theme_*`            |
| `setTheme`            | supported   | Sets Moodle theme config                     |
| `createCategory`      | supported   | Idempotent (by `idnumber` or name+parent)    |
| `createCourse`        | supported   | Idempotent by `shortname`                    |
| `createUser`          | supported   | Idempotent by `username`                     |
| `createUsers`         | supported   | Loops over `createUser`                      |
| `enrolUser`           | supported   | Manual enrolment, idempotent                 |
| `installMoodle`       | no-op       | Moodle is installed by the container startup |
| `login`               | no-op       | Browser-only; not applicable server-side     |
| `restoreCourse`       | planned     | Recognised; fails clearly until implemented  |
| `runPhpCode`          | disabled    | Unsafe                                        |
| `runPhpScript`        | disabled    | Unsafe                                        |
| `writeFile`           | disabled    | Unsafe by default                            |
| `unzip`               | disabled    | Unsafe by default                            |

Other recognised Moodle Playground steps (e.g. `addModule`, `createRole`,
`installLanguagePack`, bulk variants) are reported as **planned** and fail
clearly rather than being silently ignored. Truly unknown steps fail with an
"unknown step type" error.

### Step examples

=== "setConfig / setConfigs"

    ```json
    { "step": "setConfig", "name": "debug", "value": 32767 }
    ```

    ```json
    { "step": "setConfigs", "values": { "debug": 32767, "debugdisplay": 1 } }
    ```

=== "setAdminAccount"

    ```json
    {
      "step": "setAdminAccount",
      "username": "admin",
      "password": "ChangeMe123!",
      "email": "admin@example.com"
    }
    ```

=== "installMoodlePlugin"

    ```json
    { "step": "installMoodlePlugin", "source": "@pluginZip" }
    ```

    ```json
    { "step": "installMoodlePlugin", "zipUrl": "https://example.com/plugin.zip" }
    ```

=== "createCourse / enrolUser"

    ```json
    { "step": "createCourse", "fullname": "Demo course", "shortname": "DEMO101", "category": "Demo" }
    ```

    ```json
    { "step": "enrolUser", "username": "student1", "course": "DEMO101", "role": "student" }
    ```

## Idempotency

After a blueprint is applied successfully, a marker is written under:

```text
/var/www/moodledata/.blueprints/<sha256>.done
```

The hash is computed over the **normalised blueprint content** (key order and
whitespace independent). On the next start:

- if the marker exists and `MOODLE_BLUEPRINT_FORCE` is not `true`, the runner
  prints `Blueprint already applied: <hash>` and exits successfully without
  reapplying;
- if `MOODLE_BLUEPRINT_FORCE=true`, it reapplies.

!!! note "Hash limitation"
    The hash covers the declarative blueprint JSON only. It does **not** include
    the bytes of bundled or remote resources, so changing a referenced resource
    without editing the blueprint will not change the hash. Use
    `MOODLE_BLUEPRINT_FORCE=true` to force reapplication in that case.

Individual steps are also idempotent where it matters (categories by
`idnumber`/name, courses by `shortname`, users by `username`, enrolments are not
duplicated), so reapplying a blueprint converges rather than duplicating data.

## Security

The runner enforces safe defaults in a central `SecurityPolicy`:

- no `eval` and no arbitrary code execution;
- shelling out uses `escapeshellarg()` — no command interpolation of user input;
- passwords are never logged;
- remote resources respect `MOODLE_BLUEPRINT_ALLOW_REMOTE_RESOURCES` and are
  bounded by `MOODLE_BLUEPRINT_MAX_RESOURCE_SIZE` (http/https only);
- ZIP extraction is performed entry-by-entry with ZIP-slip protection; symlink
  entries are never honoured;
- bundle resource paths cannot escape the bundle directory (no `..`, no absolute
  paths, `__MACOSX` ignored);
- plugin installs are restricted to allowlisted Moodle directories;
- unsafe steps are disabled by default and are not implemented in this version.

## Bundles

A bundle is a self-contained directory or ZIP containing `blueprint.json` plus
the resources it references (inspired by WordPress Playground Blueprint
Bundles). `blueprint.json` may sit at the bundle root or exactly one directory
deep; the `__MACOSX` folder is ignored and multiple candidates are an error.

```text
my-moodle-blueprint/
├── blueprint.json
└── plugins/
    └── mod_example.zip
```

```json
{
  "resources": {
    "examplePlugin": {
      "bundled": "plugins/mod_example.zip"
    }
  },
  "steps": [
    {
      "step": "installMoodlePlugin",
      "source": "@examplePlugin"
    }
  ]
}
```

!!! note "Remote bundle URLs are future work"
    `MOODLE_BLUEPRINT_BUNDLE` accepts a **local** directory or ZIP only.
    Downloading a remote bundle ZIP is not implemented yet; use
    `MOODLE_BLUEPRINT_URL` for a remote single-file blueprint, or fetch the
    bundle into the container yourself.

## docker-compose example

```yaml
services:
  moodle:
    image: erseco/alpine-moodle:latest
    ports:
      - "8080:8080"
    environment:
      MOODLE_DATABASE_TYPE: sqlite3
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
      MOODLE_EMAIL: admin@example.com
      MOODLE_SITENAME: "Blueprint Demo"
      MOODLE_BLUEPRINT: /blueprints/demo.blueprint.json
    volumes:
      - moodledata:/var/www/moodledata
      - ./demo.blueprint.json:/blueprints/demo.blueprint.json:ro

volumes:
  moodledata:
```

A copy-pasteable [`demo.blueprint.json`](examples/demo.blueprint.json) lives in
`docs/examples/`.

## Manual validation

The blueprint runs after Moodle installation/upgrade. To try it end-to-end:

```sh
docker build -t alpine-moodle-blueprint-test .
docker run --rm \
  -p 8080:8080 \
  -e MOODLE_DATABASE_TYPE=sqlite3 \
  -e MOODLE_USERNAME=admin \
  -e MOODLE_PASSWORD=ChangeMe123! \
  -e MOODLE_EMAIL=admin@example.com \
  -e MOODLE_SITENAME="Blueprint Demo" \
  -e MOODLE_BLUEPRINT=/blueprints/demo.blueprint.json \
  -v "$PWD/docs/examples/demo.blueprint.json:/blueprints/demo.blueprint.json:ro" \
  alpine-moodle-blueprint-test
```

You can also validate a blueprint without applying it (no Moodle bootstrap):

```sh
docker run --rm \
  -e MOODLE_BLUEPRINT=/blueprints/demo.blueprint.json \
  -v "$PWD/docs/examples/demo.blueprint.json:/blueprints/demo.blueprint.json:ro" \
  alpine-moodle-blueprint-test moodle-blueprint validate
```

## Tests

The runner ships with dependency-free PHP unit tests plus lint/shell checks:

```sh
tests/blueprint/run.sh
```

This lints every PHP file, syntax-checks the entrypoint hook, and runs unit
tests for the parser, security policy, resource resolver, archive safety,
bundle detection, step registry and idempotency markers.
