# Reverse Proxy

Most deployments run `alpine-moodle` behind a reverse proxy that terminates TLS. This page documents how to wire that up correctly and how to avoid the recurring pitfalls reported in issues like [#15](https://github.com/erseco/alpine-moodle/issues/15), [#21](https://github.com/erseco/alpine-moodle/issues/21), [#51](https://github.com/erseco/alpine-moodle/issues/51), [#57](https://github.com/erseco/alpine-moodle/issues/57), [#61](https://github.com/erseco/alpine-moodle/issues/61), [#101](https://github.com/erseco/alpine-moodle/issues/101), [#127](https://github.com/erseco/alpine-moodle/issues/127) and [#137](https://github.com/erseco/alpine-moodle/issues/137).

## How Moodle sees the world

Moodle builds every URL from `$CFG->wwwroot`. That value is derived from `SITE_URL` at first start. If `wwwroot` does not exactly match the URL the browser uses, you will see:

- **Broken CSS / JS** — assets are generated against a different origin, triggering mixed content or 404s.
- **`ERR_TOO_MANY_REDIRECTS`** — Moodle keeps redirecting to its canonical `wwwroot` because the incoming request looks different.
- **Login loops** — session cookies are set on a host Moodle does not recognise.

To use a reverse proxy correctly you need to tell Moodle two things:

1. The **public URL** users type in the browser → `SITE_URL`
2. Whether the public connection is **HTTPS even though the container speaks HTTP** → `SSLPROXY=true`

## The correct settings

```yaml
environment:
  SITE_URL: https://moodle.example.com
  SSLPROXY: "true"
  REVERSEPROXY: "false"
```

| Variable       | Value                         | Purpose |
|----------------|-------------------------------|---------|
| `SITE_URL`     | Full **public** URL with scheme | Becomes `$CFG->wwwroot`. Must match what users type in the browser. |
| `SSLPROXY`     | `true`                        | Trusts `X-Forwarded-Proto` so Moodle treats the request as HTTPS. |
| `REVERSEPROXY` | `false` in most cases         | Only set to `true` if the same site is intentionally accessed under multiple base URLs (multi-tenant / multi-host). See [Moodle docs on reverse proxies](https://docs.moodle.org/en/Server_cluster). |

!!! warning "`REVERSEPROXY=true` is rarely what you want"
    Setting `REVERSEPROXY=true` on a single-URL deployment triggers *"Reverse proxy enabled so the server cannot be accessed directly"* errors (issue [#137](https://github.com/erseco/alpine-moodle/issues/137)). Leave it at `false` unless you actually serve the same site from several hostnames.

## Required proxy headers

Whatever proxy you use, it must forward these headers:

- `Host` — the public hostname
- `X-Forwarded-Proto` — `https`
- `X-Forwarded-For` — the real client IP

Without `X-Forwarded-Proto: https` the `SSLPROXY` flag has nothing to trust and Moodle will keep redirecting to HTTP.

## Traefik (v2 / v3)

Label-based configuration, no file changes required on the Traefik side.

```yaml
services:
  moodle:
    image: erseco/alpine-moodle
    restart: unless-stopped
    environment:
      SITE_URL: https://moodle.example.com
      SSLPROXY: "true"
      DB_HOST: postgres
      DB_USER: moodle
      DB_PASS: moodle
      DB_NAME: moodle
      MOODLE_USERNAME: admin
      MOODLE_PASSWORD: ChangeMe123!
    volumes:
      - moodledata:/var/www/moodledata
      - moodlehtml:/var/www/html
    networks:
      - proxy
      - default
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
      - "traefik.http.routers.moodle.rule=Host(`moodle.example.com`)"
      - "traefik.http.routers.moodle.entrypoints=websecure"
      - "traefik.http.routers.moodle.tls=true"
      - "traefik.http.routers.moodle.tls.certresolver=letsencrypt"
      - "traefik.http.services.moodle.loadbalancer.server.port=8080"

networks:
  proxy:
    external: true
```

Traefik forwards `X-Forwarded-Proto` automatically when the entry point terminates TLS, so nothing else is needed.

!!! tip "502 Bad Gateway with Traefik"
    A 502 from Traefik (issue [#61](https://github.com/erseco/alpine-moodle/issues/61)) usually means the service port is wrong. The container listens on **8080**, not 80. Set `traefik.http.services.moodle.loadbalancer.server.port=8080`.

## Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name moodle.example.com;

    ssl_certificate     /etc/letsencrypt/live/moodle.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/moodle.example.com/privkey.pem;

    client_max_body_size 100M;

    location / {
        proxy_pass         http://moodle:8080;
        proxy_http_version 1.1;

        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_set_header   X-Forwarded-Host  $host;

        proxy_read_timeout 300s;
    }
}

server {
    listen 80;
    server_name moodle.example.com;
    return 301 https://$host$request_uri;
}
```

Set `client_max_body_size` high enough to allow large course uploads. Also raise the matching PHP variables (`post_max_size`, `upload_max_filesize`) on the Moodle container.

## Nginx Proxy Manager

NPM is popular for homelab deployments and is the source of several support questions ([#51](https://github.com/erseco/alpine-moodle/issues/51)).

1. Expose the container on an internal Docker network that NPM can reach (no host port required).
2. In NPM, create a **Proxy Host**:
    - **Domain Names**: `moodle.example.com`
    - **Scheme**: `http`
    - **Forward Hostname / IP**: the container name (e.g. `moodle`)
    - **Forward Port**: `8080`
    - Toggle **Block Common Exploits**: off (NPM's WAF can break some Moodle paths)
    - Toggle **Websockets Support**: on
3. On the **SSL** tab, request a Let's Encrypt certificate and enable **Force SSL** and **HTTP/2**.
4. Under **Advanced**, add:

    ```nginx
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host  $host;
    client_max_body_size 100M;
    ```

5. In your `docker-compose.yml` for Moodle, set `SITE_URL=https://moodle.example.com` and `SSLPROXY=true`.

## Apache (mod_proxy)

```apache
<VirtualHost *:443>
    ServerName moodle.example.com

    SSLEngine on
    SSLCertificateFile      /etc/letsencrypt/live/moodle.example.com/fullchain.pem
    SSLCertificateKeyFile   /etc/letsencrypt/live/moodle.example.com/privkey.pem

    ProxyPreserveHost On
    ProxyRequests Off

    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port  "443"

    ProxyPass        / http://moodle:8080/
    ProxyPassReverse / http://moodle:8080/

    <Proxy *>
        Require all granted
    </Proxy>
</VirtualHost>

<VirtualHost *:80>
    ServerName moodle.example.com
    Redirect permanent / https://moodle.example.com/
</VirtualHost>
```

Enable the required modules once:

```bash
a2enmod proxy proxy_http ssl headers rewrite
```

## Caddy

```caddy
moodle.example.com {
    reverse_proxy moodle:8080 {
        header_up Host              {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-For   {remote}
    }
}
```

With `SITE_URL=https://moodle.example.com` and `SSLPROXY=true` on the Moodle container this is all you need — Caddy will obtain and renew TLS automatically.

## Cloudflare / Cloudflared

If you front Moodle with Cloudflare (proxied DNS or `cloudflared` tunnel), Cloudflare already injects `X-Forwarded-Proto: https`. You only need:

```yaml
environment:
  SITE_URL: https://moodle.example.com
  SSLPROXY: "true"
  REVERSEPROXY: "false"
```

To log the real visitor IP instead of the Cloudflare edge IP, enable the `CF-Connecting-IP` header in your front proxy (or use Cloudflare's *True-Client-IP*) and ensure the next proxy hop copies it into `X-Forwarded-For`.

## Reverse proxy with a URL prefix

Moodle does **not** support being served from a subpath such as `https://example.com/mylms/` (issue [#127](https://github.com/erseco/alpine-moodle/issues/127)). Upstream Moodle requires its own hostname or subdomain. If you need path-based routing, use a dedicated subdomain (`moodle.example.com`) instead.

## Checklist

Before opening a support issue, verify:

- [ ] `SITE_URL` is the **public** URL, starts with `https://`, no trailing slash.
- [ ] `SSLPROXY=true` is set when the proxy terminates TLS.
- [ ] `REVERSEPROXY=false` (unless you really use multiple base URLs).
- [ ] The proxy forwards `Host`, `X-Forwarded-Proto` and `X-Forwarded-For`.
- [ ] The upstream port is `8080`, not `80`.
- [ ] You restarted the container after changing `SITE_URL` on an existing installation and, if necessary, manually updated `wwwroot` in `config.php`.
