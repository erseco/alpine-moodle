# FAQ

Short answers to recurring questions from the issue tracker.

## Which database should I use?

PostgreSQL. It is the default, it is the combination that receives the most CI coverage in this repository, and it is the best supported database by upstream Moodle. MariaDB works too, SQLite is development-only.

## Which port does the container listen on?

**8080**, inside the container. Always map or proxy to `8080`, not `80`. Publishing on the host with `-p 80:8080` exposes the public port 80 bound to the container's 8080.

## Can I serve Moodle from a sub-path like `https://example.com/mylms/`?

No. Moodle does not support subpath deployment without patching. Use a subdomain such as `moodle.example.com`. Related: [#127](https://github.com/erseco/alpine-moodle/issues/127).

## How do I change the admin password after installation?

The container re-applies `MOODLE_USERNAME` / `MOODLE_PASSWORD` on every start via `admin/cli/update_admin_user.php`. Change the environment variable and restart:

```bash
docker compose up -d --force-recreate moodle
```

Or do it manually:

```bash
docker compose exec moodle php admin/cli/reset_password.php --username=admin --password=NewPass123!
```

## Can I run multiple Moodle instances on the same host?

Yes. Give each stack its own project directory (so `docker compose` namespaces the volumes) and map different host ports — for example `8080:8080` and `8081:8080`. Use one reverse proxy to terminate TLS and route by hostname.

## How do I install a plugin?

Use Moosh, either interactively:

```bash
docker compose exec moodle moosh plugin-install --delete mod_attendance
```

or declaratively via `POST_CONFIGURE_COMMANDS` so the plugin is (re)installed on every start.

The `--delete` flag is recommended because of a [known Moosh bug](https://github.com/tmuras/moosh/issues/520) where the first install can silently fail.

## Can I disable the internal cron?

Yes — set `RUN_CRON_TASKS=false`. You are then responsible for running `admin/cli/cron.php` externally. Related: [#98](https://github.com/erseco/alpine-moodle/issues/98).

## Can I skip the automatic Moodle upgrade on boot?

Yes — set `AUTO_UPDATE_MOODLE=false`. The container will start without running `admin/cli/upgrade.php`; you must run it yourself before letting users back in.

## Which architectures are supported?

`amd64`, `arm64`, `arm/v7`, `arm/v6`, `386`, `ppc64le`, `s390x`. Pull `erseco/alpine-moodle` on any of them and Docker will fetch the right variant.

## Does the image include Redis / PostgreSQL / MariaDB?

No. The image only contains Moodle, PHP 8.3, Nginx, Moosh and supporting tools. External services (database, Redis) must run in their own containers. See [Docker Compose](docker-compose.md) for ready-made stacks.

## Can I mount my own `config.php`?

You can, but the startup script will try to update its managed keys (wwwroot, dbtype, dbhost, proxy flags, Redis handler) in place. Mount a writable `config.php` and don't add anything to keys the container owns. For custom `$CFG` flags, add them near the bottom of the file.

## How do I enable developer debug output?

Set `DEBUG=true`. This flips `debug` and `debugdisplay` to the `DEVELOPER` preset. Related: [#25](https://github.com/erseco/alpine-moodle/issues/25).

## Why doesn't the image auto-detect the public hostname?

Because there is no reliable way to do it. Browser requests can come through any number of proxies, tunnels, or load balancers. Moodle needs to know its canonical URL up front, which is why `SITE_URL` is the most important variable in this image.

## What's the default admin login?

`moodleuser` / `PLEASE_CHANGEME`. **You must override both** on first boot. The defaults exist only so the installer has something to pass to the CLI.

## Where do logs go?

To `stdout` / `stderr`, so `docker logs` and `docker compose logs` just work. Nginx access logs, PHP-FPM logs, and the Moodle bootstrap scripts all converge on the container's standard output.

## Where are uploads stored?

In `/var/www/moodledata/`. Mount a volume there to persist them. See [Persistence & Volumes](persistence.md).

## What happens on the first boot?

1. The container waits for the database (unless SQLite).
2. It runs any `PRE_CONFIGURE_COMMANDS`.
3. It generates a fresh `config.php` and calls `admin/cli/install.php --skip-database`.
4. For Moodle 5.1+, it runs `composer install` against `/var/www/html`.
5. It writes the database schema with `admin/cli/install_database.php` (unless the database is already installed — in that case it upgrades instead).
6. It applies all the Moodle `cfg.php` tweaks (SMTP, paths, debug).
7. It runs any `POST_CONFIGURE_COMMANDS`.
8. It starts Nginx, PHP-FPM and the cron loop under `runit`.

## Can I contribute?

Yes — open an issue or a PR at <https://github.com/erseco/alpine-moodle>. Documentation PRs are very welcome; the docs site lives under `docs/` and is built with Zensical.
