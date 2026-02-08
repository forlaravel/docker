<p align="center">
  <a href="https://github.com/forlaravel/docker">
    <img src="./assets/logo.png" alt="Laravel Docker image with PHP, Nginx, and Supervisor" width="150">
  </a>
</p>

# Laravel Docker image

<p align="center">
   <a href="https://github.com/forlaravel/docker/pkgs/container/docker"><img src="https://img.shields.io/badge/variants-fpm | roadrunner | frankenphp | openswoole-blue?style=flat-square" alt="FPM, RoadRunner, FrankenPHP, OpenSwoole"></a>
   <a href="https://github.com/forlaravel/docker/actions/workflows/scheduled-rebuild.yml"><img src="https://img.shields.io/github/actions/workflow/status/forlaravel/docker/scheduled-rebuild.yml?style=flat-square&label=build" alt="Build status"></a>
   <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-white?style=flat-square" alt="MIT license"></a>
</p>

A Docker image that runs Laravel applications. One container gives you PHP, Nginx, Supervisor, Cron, and SSL. Mount your project to `/app` and it works.

Supports PHP 8.4 and 8.5, Laravel 10 through 13. You pick the PHP runtime: PHP-FPM for standard setups, or FrankenPHP, RoadRunner, OpenSwoole for [Laravel Octane](https://laravel.com/docs/octane). All images are multi-arch (amd64 + arm64), Alpine-based, and rebuilt weekly.

The same image works for development and production. If you're looking for a Laravel Sail alternative that uses plain Docker Compose, this is it.

Fork of [jonaaix/laravel-aio-docker](https://github.com/jonaaix/laravel-aio-docker) with security hardening, OPcache/FPM tuning, HEALTHCHECK, Chromium split, and more config options.

What you get:
- PHP-FPM, FrankenPHP, RoadRunner, or OpenSwoole
- Nginx with HTTPS, WebSocket support, and security headers
- Supervisor managing Horizon, queue workers, or Octane
- Xdebug, Vite dev server, Composer/NPM auto-install
- OPcache and PHP-FPM pool tuning via env vars
- Security hardening (disable PHP functions, restrict filesystem, lock down Nginx)
- Chromium variant for PDF generation with Puppeteer/Browsershot
- Docker HEALTHCHECK

---

## Quick start

```yaml
services:
   app:
      image: ghcr.io/forlaravel/docker:latest-php8.4-fpm
      volumes:
         - ./:/app
      ports:
         - "8000:8000"
         - "8443:8443"
```

HTTP on `:8000`, HTTPS on `:8443`.

---

## Available images

Published to `ghcr.io/forlaravel/docker`, rebuilt weekly.

### PHP 8.5 (Laravel 12, 13)

| Runtime | Image |
| :--- | :--- |
| PHP-FPM + Nginx | `ghcr.io/forlaravel/docker:latest-php8.5-fpm` |
| FrankenPHP + Nginx | `ghcr.io/forlaravel/docker:latest-php8.5-frankenphp` |
| RoadRunner + Nginx | `ghcr.io/forlaravel/docker:latest-php8.5-roadrunner` |

### PHP 8.4 (Laravel 10, 11, 12)

| Runtime | Image |
| :--- | :--- |
| PHP-FPM + Nginx | `ghcr.io/forlaravel/docker:latest-php8.4-fpm` |
| FrankenPHP + Nginx | `ghcr.io/forlaravel/docker:latest-php8.4-frankenphp` |
| RoadRunner + Nginx | `ghcr.io/forlaravel/docker:latest-php8.4-roadrunner` |
| OpenSwoole + Nginx | `ghcr.io/forlaravel/docker:latest-php8.4-openswoole` |

OpenSwoole doesn't support PHP 8.5 yet.

### Chromium variant (for PDF generation)

Add `-chromium` to any tag for Puppeteer/Browsershot:
```
ghcr.io/forlaravel/docker:latest-php8.4-fpm-chromium
```

### Pinned versions

Replace `latest` with a version number for reproducible builds:
```
ghcr.io/forlaravel/docker:1.3-php8.4-fpm
```

---

## How it compares to Laravel Sail

Sail wraps Docker behind its own CLI and spreads services across multiple containers. This image takes a different approach: everything PHP-related runs in one container, configured entirely through environment variables.

| | Laravel Sail | This image |
| :--- | :--- | :--- |
| Architecture | Separate containers for PHP, Nginx, etc. | Single container (PHP + Nginx + Supervisor) |
| Configuration | Sail CLI + docker-compose.yml | Environment variables |
| Production | Development only | Same image for dev and prod |
| Runtimes | PHP-FPM | FPM, FrankenPHP, RoadRunner, OpenSwoole |
| Octane | Manual setup | Pick an Octane image, it's automatic |

When you switch to an Octane image (RoadRunner/FrankenPHP/OpenSwoole) for the first time, the entrypoint installs the required packages automatically. Commit those changes to your repo.

---

## Configuration

Everything is configured through environment variables. All flags default to `false`.

### 1. Operation mode

The container runs in production mode by default.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ENV_DEV` | `false` | Set to `true` for development mode. |

### 2. Development features

Only active when `ENV_DEV=true`.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DEV_FORCE_NPM_INSTALL` | `false` | Force `npm install` on every start. |
| `DEV_NPM_RUN_DEV` | `false` | Run `npm run dev` (Vite) on start. |
| `DEV_ENABLE_XDEBUG` | `false` | Enable the Xdebug extension. |

### 3. Production automation

Only active when `ENV_DEV=false` (the default).

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PROD_RUN_ARTISAN_MIGRATE` | `false` | Run `php artisan migrate --force` on boot. |
| `PROD_RUN_ARTISAN_DBSEED` | `false` | Run `php artisan db:seed --force` on boot. |
| `PROD_SKIP_OPTIMIZE` | `false` | Skip Laravel caching/optimization commands. |

### 4. Background services

Supervisor always runs. These toggle specific workers.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_QUEUE_WORKER` | `false` | Start the Laravel queue worker. |
| `ENABLE_HORIZON_WORKER` | `false` | Start Laravel Horizon. |
| `SKIP_INSTALL` | `false` | Skip Composer install, NPM install, asset build, and optimization. For pre-built images. |
| `SKIP_LARAVEL_BOOT` | `false` | Skip all Laravel boot steps. FPM only. Useful for non-Laravel PHP apps. |
| `SKIP_PERMISSION_FIX` | `false` | Skip the `chown`/`chmod` fix on `storage/` and `bootstrap/cache/`. |

### 5. Security hardening

All disabled by default.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `NGINX_RESTRICT_PHP_EXECUTION` | `false` | Only allow `index.php` to execute. Other `.php` requests get a 404. |
| `PHP_DISABLE_FUNCTIONS` | _(unset)_ | Comma-separated list of PHP functions to disable (e.g. `exec,shell_exec,system,passthru,proc_open,popen`). |
| `PHP_OPEN_BASEDIR` | _(unset)_ | Restrict PHP filesystem access (e.g. `/app:/tmp`). |

How these get applied depends on the runtime:

| Runtime | Mechanism | Web requests | CLI (Horizon, artisan, queue) |
| :--- | :--- | :--- | :--- |
| FPM | `php_admin_value` in FPM pool config | Restricted | Unrestricted |
| Octane | `-d` flags on Octane supervisor command | Restricted | Unrestricted |

Horizon and queue workers keep full access to `proc_open`, `pcntl_fork`, etc. Only the web-facing process is restricted.

For RoadRunner and FrankenPHP, `proc_open` is automatically removed from the disable list since they need it to start. Swoole doesn't need it.

`open_basedir` disables PHP's realpath cache, which can hurt performance. If you use it, set `PHP_OPCACHE_VALIDATE_TIMESTAMPS=0` (see below).

### 6. Performance tuning (OPcache and PHP-FPM)

These let you tune OPcache and PHP-FPM pool settings at runtime.

#### OPcache

| Variable | Maps to | Default | Description |
| :--- | :--- | :--- | :--- |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `opcache.validate_timestamps` | `1` | Set to `0` in production to stop checking if files changed. Biggest single performance improvement. |
| `PHP_OPCACHE_REVALIDATE_FREQ` | `opcache.revalidate_freq` | `2` | Seconds between file checks. Irrelevant when `validate_timestamps=0`. |
| `PHP_OPCACHE_MEMORY` | `opcache.memory_consumption` | `1024` | OPcache memory in MB. |
| `PHP_OPCACHE_MAX_FILES` | `opcache.max_accelerated_files` | `20000` | Max cached scripts. |
| `PHP_OPCACHE_INTERNED_STRINGS` | `opcache.interned_strings_buffer` | `16` | Interned strings memory in MB. |
| `PHP_OPCACHE_JIT` | `opcache.jit` | `disable` | JIT mode. `tracing` gives best results on PHP 8.0+. |
| `PHP_OPCACHE_JIT_BUFFER` | `opcache.jit_buffer_size` | `64M` | Memory for JIT compiled code. |
| `PHP_OPCACHE_PRELOAD` | `opcache.preload` | _(unset)_ | Path to a preload script (e.g. `/app/vendor/preload.php`). |

#### PHP-FPM pool (FPM only)

| Variable | Maps to | Default | Description |
| :--- | :--- | :--- | :--- |
| `PHP_FPM_PM` | `pm` | `dynamic` | Process manager: `static`, `dynamic`, or `ondemand`. |
| `PHP_FPM_MAX_CHILDREN` | `pm.max_children` | `5` | Max worker processes. |
| `PHP_FPM_START_SERVERS` | `pm.start_servers` | `2` | Workers on boot (dynamic mode). |
| `PHP_FPM_MIN_SPARE` | `pm.min_spare_servers` | `1` | Min idle workers (dynamic mode). |
| `PHP_FPM_MAX_SPARE` | `pm.max_spare_servers` | `3` | Max idle workers (dynamic mode). |
| `PHP_FPM_MAX_REQUESTS` | `pm.max_requests` | `0` | Recycle workers after N requests. Prevents memory leaks. |

#### Example production settings

```yaml
environment:
   - PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
   - PHP_FPM_PM=static
   - PHP_FPM_MAX_CHILDREN=30
   - PHP_FPM_MAX_REQUESTS=1000
```

To estimate `max_children`: divide your container memory by ~50MB per worker. A 2GB container can handle about 40 workers, but leave room for Nginx and Supervisor, so 30 is a reasonable starting point.

### 7. Maintenance mode

Controls Laravel's maintenance mode during boot, useful during deployments.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_MAINTENANCE_BOOT` | `false` | Enable maintenance mode during boot. Skipped if `vendor/` doesn't exist. |
| `MAINTENANCE_SECRET` | _(auto-generated)_ | Secret for bypassing maintenance mode. |
| `MAINTENANCE_RENDER` | `errors::503` | View to render during maintenance. |
| `MAINTENANCE_RETRY` | `10` | Retry-After header in seconds. |

---

## Docker Compose examples

### Development

```yaml
services:
   app:
      image: ghcr.io/forlaravel/docker:latest-php8.5-fpm
      volumes:
         - ./:/app
      environment:
         ENV_DEV: true
         DEV_NPM_RUN_DEV: true
         DEV_ENABLE_XDEBUG: true
         ENABLE_HORIZON_WORKER: true
      ports:
         - "8000:8000"
         - "8443:8443"
         - "5173:5173"
      restart: unless-stopped
      depends_on:
         - mysql
      networks:
         - app

   mysql:
      image: mariadb:lts
      command:
         - '--character-set-server=utf8mb4'
         - '--collation-server=utf8mb4_unicode_ci'
         - '--skip-name-resolve'
      volumes:
         - db_volume:/var/lib/mysql/:delegated
      environment:
         MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
         MYSQL_USER: ${DB_USERNAME}
         MYSQL_PASSWORD: ${DB_PASSWORD}
         MYSQL_DATABASE: ${DB_DATABASE}
      ports:
         - "3306:3306"
      restart: unless-stopped

volumes:
   db_volume:
```

### Production (hardened)

```yaml
services:
   app:
      image: ghcr.io/forlaravel/docker:1.3-php8.4-fpm
      volumes:
         - ./:/app:ro
         - ./storage/logs:/app/storage/logs
         - ./storage/framework:/app/storage/framework
         - ./bootstrap/cache:/app/bootstrap/cache
      environment:
         - SKIP_INSTALL=true
         - PROD_RUN_ARTISAN_MIGRATE=true
         - ENABLE_HORIZON_WORKER=true
         # Security
         - NGINX_RESTRICT_PHP_EXECUTION=true
         - PHP_DISABLE_FUNCTIONS=exec,shell_exec,system,passthru,proc_open,popen,pcntl_exec,pcntl_fork
         - PHP_OPEN_BASEDIR=/app:/tmp
         # Performance
         - PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
         - PHP_FPM_PM=static
         - PHP_FPM_MAX_CHILDREN=30
         - PHP_FPM_MAX_REQUESTS=1000
      mem_limit: 2g
      restart: unless-stopped
```

Mounting `/app:ro` with only `storage/logs`, `storage/framework`, and `bootstrap/cache` writable means a compromised app can't modify its own code.

---

## SSL / HTTPS

All variants serve HTTPS on port 8443 using a self-signed certificate generated on first boot. HTTP stays on port 8000.

This works well with reverse proxies (Traefik, Caddy, etc.) that terminate TLS. Forward to 8443 instead of 8000 and the app sees a real HTTPS connection without `X-Forwarded-Proto` headers or `TrustProxies` middleware.

```yml
ports:
   - "8000:8000"  # HTTP
   - "8443:8443"  # HTTPS (self-signed)
```

The cert lives at `/etc/nginx/ssl/selfsigned.{crt,key}`. To use your own:

```yml
volumes:
   - ./my-cert.crt:/etc/nginx/ssl/selfsigned.crt:ro
   - ./my-cert.key:/etc/nginx/ssl/selfsigned.key:ro
```

If a cert already exists there, auto-generation is skipped.

## Docker HEALTHCHECK

All variants include a HEALTHCHECK that polls `http://localhost:8000/basic_status` every 30s (start period: 120s for the boot sequence). The endpoint is localhost-only, not reachable from outside.

```bash
docker inspect --format='{{.State.Health.Status}}' <container>
```

## Nginx access logs

Access logs go to stdout in `combined` format, so they show up in `docker logs`. Requests for `/favicon.ico` and `/robots.txt` are suppressed.

## File permissions

The container runs as uid 1000 to match the default host user on most Linux systems.

To fix permissions:
```bash
docker compose exec --user root php sh -c "/scripts/fix-laravel-project-permissions.sh"
```

On macOS (where the default group is `staff`):
```bash
sudo chown -R $(whoami):staff /path/to/app
```

---

## Guides

### Xdebug

Set `DEV_ENABLE_XDEBUG=true` in your docker-compose.yml. Xdebug listens on port 9003.

<details>
<summary>PHPStorm setup (click to expand)</summary>

1. `Settings` -> `PHP` -> `Debug`
2. Disable `Break at first line in PHP scripts`
3. Disable `Force break at first line when no path mapping specified`
4. Disable `Force break at first line when a script is outside the project`
5. `Settings` -> `PHP` -> `Servers`
6. Add a server:
   - Name: `laravel`
   - Host: `localhost`
   - Port: `8000`
   - Debugger: `Xdebug`
   - Enable `Use path mappings`: `path/to/your/project` -> `/app`
7. Install the [browser extension](https://www.jetbrains.com/help/phpstorm/browser-debugging-extensions.html).
8. Click the phone icon in PHPStorm to start listening.
</details>

### Chromium for PDF generation

Chromium isn't in the default images (it adds ~200MB). Use the `-chromium` variant instead:

```yaml
image: ghcr.io/forlaravel/docker:latest-php8.4-fpm-chromium
```

When building locally:
```bash
./build-image.sh 8.4 fpm --chromium
```

Or with the build arg directly:
```bash
docker buildx build --build-arg INPUT_PHP=8.4 --build-arg INSTALL_CHROMIUM=true \
   --file ./src/php-fpm/Dockerfile --load .
```

Then install `spatie/laravel-pdf`:

```shell
composer require spatie/laravel-pdf
npm install -S puppeteer
```

```php
<?php

namespace App\Services;

use Spatie\Browsershot\Browsershot;
use Spatie\LaravelPdf\PdfBuilder;

class PDF {
   public static function getPrinter(): PdfBuilder {
      return \Spatie\LaravelPdf\Support\pdf()->withBrowsershot(function (Browsershot $browsershot) {
         $browsershot->setOption('executablePath', '/usr/bin/chromium-browser');
      });
   }
}
```

### Laravel Boost MCP

##### 1. Create a bridge script `mcp-boost.sh` in your project root
```bash
#!/bin/bash
cd "$(dirname "$0")"
$(which docker) compose exec -T php php artisan boost:mcp
```
Make it executable: `chmod +x mcp-boost.sh`

##### 2. Add to your MCP configuration
```json
{
  "mcpServers": {
    "laravel-boost": {
      "command": "./mcp-boost.sh",
      "args": []
    }
  }
}
```

##### 3. Set the working directory to your project root
For JetBrains AI Assistant:
```
Settings -> Tools -> AI Assistant -> MCP -> Edit Laravel Boost -> Working Directory
```

### Redis
```yml
volumes:
   redis_volume:
      driver: local

redis:
   image: redis:8-alpine
   volumes:
      - redis_volume:/data
   command: [ "redis-server", "--requirepass", "${REDIS_PASSWORD}" ]
   ports:
      - "6379:6379"
   restart: unless-stopped
   networks:
      - app
```

### PhpMyAdmin
```yaml
pma:
   image: phpmyadmin:latest
   environment:
      PMA_HOST: mysql
      PMA_PORT: 3306
      APACHE_PORT: 8080
      UPLOAD_LIMIT: 1G
   restart: unless-stopped
   depends_on:
      - mysql
```

### Serving a JavaScript app through Nginx

Mount a custom nginx.conf and your JS app:
```yml
services:
   php:
      volumes:
         - ./nginx.conf:/etc/nginx/http.d/default.conf
         - ../my-app:/js-app
```

Then add a location block after `/basic_status`:

<details>
<summary>Nginx config for JS app (click to expand)</summary>

```nginx
####################################
####### Start serving JS app #######
####################################
location = / {
    return 301 $real_scheme://$http_host/app/;
}

location = /app {
    return 301 $real_scheme://$http_host/app/;
}

location ^~ /app/ {
    alias /js-app/;
    index index.html;
    try_files $uri $uri/ /app/index.html;

    location ~* \.(?:manifest|appcache|html?|xml|json)$ {
        expires -1;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|woff2?|otf|ttf|js|svg|css|txt|wav|mp3|aff|dic)$ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        access_log off;
    }
}
####################################
####### End serving JS app #########
####################################
```
</details>

### Custom boot scripts

Mount script directories to hook into the boot process. Scripts run in alphabetical order.

```yml
services:
   php:
      volumes:
         - ./docker/before-boot:/custom-scripts/before-boot
         - ./docker/after-boot:/custom-scripts/after-boot
```

### Debugging Nginx

Add this location block to dump all Nginx variables:
<details>
<summary>Debug location block (click to expand)</summary>

```nginx
 location /debug_status {
     default_type text/plain;
     return 200 "
         scheme: $scheme
         host: $host
         server_addr: $server_addr
         remote_addr: $remote_addr
         remote_port: $remote_port
         request_method: $request_method
         request_uri: $request_uri
         document_uri: $document_uri
         query_string: $query_string
         status: $status
         http_user_agent: $http_user_agent
         http_referer: $http_referer
         http_x_forwarded_for: $http_x_forwarded_for
         http_x_forwarded_proto: $http_x_forwarded_proto
         request_time: $request_time
         upstream_response_time: $upstream_response_time
         request_filename: $request_filename
         content_type: $content_type
         body_bytes_sent: $body_bytes_sent
         bytes_sent: $bytes_sent
         connection: $connection
         connection_requests: $connection_requests
         server_protocol: $server_protocol
         server_port: $server_port
         request: $request
         args: $args
         time_iso8601: $time_iso8601
         msec: $msec
         uri: $uri
     ";
 }
```
</details>
