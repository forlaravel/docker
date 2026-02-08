<p align="center">
  <a href="https://github.com/forlaravel/docker">
    <img src="./assets/logo.png" alt="Laravel AIO Docker Logo" width="150">
  </a>
</p>

<h1 align="center">Laravel Docker Image</h1>

<p align="center">
All-in-one Docker runtime for Laravel. Nginx, PHP, Supervisor, Cron, SSL — zero config.
</p>

<p align="center">
   <a href="https://github.com/forlaravel/docker/pkgs/container/docker"><img src="https://img.shields.io/badge/variants-fpm | roadrunner | frankenphp | openswoole-blue?style=flat-square" alt="Variants"></a>
   <a href="https://github.com/forlaravel/docker/actions/workflows/build-and-push.yml"><img src="https://img.shields.io/github/actions/workflow/status/forlaravel/docker/build-and-push.yml?style=flat-square&label=build" alt="Build Status"></a>
   <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-white?style=flat-square" alt="License"></a>
</p>

---

## Quick Start

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

Mount your Laravel project to `/app` and you're done. HTTP on `:8000`, HTTPS on `:8443`.

---

## Available Images

All images are multi-arch (`amd64` + `arm64`) and rebuilt weekly.

#### PHP 8.5 (Laravel 12+)
| Runtime | Image |
| :--- | :--- |
| FPM | `ghcr.io/forlaravel/docker:latest-php8.5-fpm` |
| FrankenPHP | `ghcr.io/forlaravel/docker:latest-php8.5-frankenphp` |
| RoadRunner | `ghcr.io/forlaravel/docker:latest-php8.5-roadrunner` |

#### PHP 8.4 (Laravel 10+)
| Runtime | Image |
| :--- | :--- |
| FPM | `ghcr.io/forlaravel/docker:latest-php8.4-fpm` |
| FrankenPHP | `ghcr.io/forlaravel/docker:latest-php8.4-frankenphp` |
| RoadRunner | `ghcr.io/forlaravel/docker:latest-php8.4-roadrunner` |
| OpenSwoole | `ghcr.io/forlaravel/docker:latest-php8.4-openswoole` |

> OpenSwoole is not compatible with PHP 8.5 yet.

#### With Chromium (PDF generation)
Add `-chromium` to any tag for Puppeteer/Browsershot support:
```
ghcr.io/forlaravel/docker:latest-php8.4-fpm-chromium
```

#### Pinned versions
Replace `latest` with a version number (e.g. `1.3`) to pin:
```
ghcr.io/forlaravel/docker:1.3-php8.4-fpm
```

---

### Difference to Laravel Sail

This image relies exclusively on **native Docker tooling** and intentionally avoids additional abstraction layers or custom APIs. It gives developers **full control over build, runtime, and configuration**, without being constrained by predefined conventions. Development and production setups are based on the same image and are fully reproducible.

> When switching to a Laravel Octane based image (roadrunner/frankenphp/openswoole) for the first time,
> the entrypoint will automatically set up all requirements if not already available.
> You can commit the changes to your repository.

---

## Configuration

Configuration is managed via environment variables. All flags are **opt-in** (default: `false`).

### 1. Operation Mode
The system runs in **Production Mode** by default.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ENV_DEV` | `false` | Set to `true` to enable **Development Mode**. |

### 2. Development Features
> **Requirement:** Active only when `ENV_DEV=true`.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DEV_FORCE_NPM_INSTALL` | `false` | Forces `npm install` on every container start. |
| `DEV_NPM_RUN_DEV` | `false` | Runs `npm run dev` (Vite) on container start. |
| `DEV_ENABLE_XDEBUG` | `false` | Enables Xdebug extension. |

### 3. Production Automation
> **Requirement:** Active only when `ENV_DEV=false` (default).

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PROD_RUN_ARTISAN_MIGRATE` | `false` | Runs `php artisan migrate --force` on boot. |
| `PROD_RUN_ARTISAN_DBSEED` | `false` | Runs `php artisan db:seed --force` on boot. |
| `PROD_SKIP_OPTIMIZE` | `false` | Skips standard Laravel caching/optimization commands. |

### 4. Background Services & System
Supervisor always runs, but specific workers are optional.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_QUEUE_WORKER` | `false` | Starts the standard Laravel Queue Worker. |
| `ENABLE_HORIZON_WORKER` | `false` | Starts the Laravel Horizon process. |
| `SKIP_INSTALL` | `false` | Skips Composer install, NPM install, asset build, and Laravel/Filament optimization. Use when dependencies and assets are pre-built into the image. |
| `SKIP_LARAVEL_BOOT` | `false` | **FPM only.** Skips Laravel boot entirely (useful for non-Laravel PHP apps). |
| `SKIP_PERMISSION_FIX` | `false` | Skips the `chown`/`chmod` permission fix on `storage/` and `bootstrap/cache/`. |

### 5. Security Hardening
Optional settings for tightening the runtime. All disabled by default.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `NGINX_RESTRICT_PHP_EXECUTION` | `false` | Only allow `index.php` to be executed by PHP. All other `.php` requests return 404. |
| `PHP_DISABLE_FUNCTIONS` | _(unset)_ | Comma-separated list of PHP functions to disable (e.g. `exec,shell_exec,system,passthru,proc_open,popen`). |
| `PHP_OPEN_BASEDIR` | _(unset)_ | Restrict PHP filesystem access to these paths (e.g. `/app:/tmp`). |

**How restrictions are applied per runtime:**

| Runtime | Mechanism | Web requests | CLI (Horizon, artisan, queue) |
| :--- | :--- | :--- | :--- |
| **FPM** | `php_admin_value` in FPM pool config | Restricted | Unrestricted |
| **Octane** | `-d` flags on Octane supervisor command | Restricted | Unrestricted |

This means Horizon and queue workers always have full access to `proc_open`, `pcntl_fork`, etc. — only the web-facing process is locked down.

> **Note:** For RoadRunner and FrankenPHP, `proc_open` is automatically removed from the disable list (they need it to start). A warning is logged. Swoole does not need `proc_open`.

> **Note:** `open_basedir` disables PHP's realpath cache, which can impact performance. See [Performance Tuning](#6-performance-tuning) to mitigate this with OPcache settings.

### 6. Performance Tuning

Optional environment variables for tuning OPcache and PHP-FPM. When unset, the image defaults apply.

#### OPcache

| Variable | Maps to | Image default | Description |
| :--- | :--- | :--- | :--- |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `opcache.validate_timestamps` | `1` | Set to `0` in production to skip file modification checks. **Biggest performance win**, especially with `open_basedir`. |
| `PHP_OPCACHE_REVALIDATE_FREQ` | `opcache.revalidate_freq` | `2` | Seconds between timestamp checks. Irrelevant when `validate_timestamps=0`. |
| `PHP_OPCACHE_MEMORY` | `opcache.memory_consumption` | `1024` | OPcache memory in MB. |
| `PHP_OPCACHE_MAX_FILES` | `opcache.max_accelerated_files` | `20000` | Max number of scripts to cache. |
| `PHP_OPCACHE_INTERNED_STRINGS` | `opcache.interned_strings_buffer` | `16` | Interned strings memory in MB. |
| `PHP_OPCACHE_JIT` | `opcache.jit` | `disable` | JIT mode (`tracing` for best performance, PHP 8.0+). |
| `PHP_OPCACHE_JIT_BUFFER` | `opcache.jit_buffer_size` | `64M` | Memory allocated for JIT compiled code. |
| `PHP_OPCACHE_PRELOAD` | `opcache.preload` | _(unset)_ | Path to preload script (e.g. `/app/vendor/preload.php`). |

#### PHP-FPM Pool (FPM runtime only)

| Variable | Maps to | Image default | Description |
| :--- | :--- | :--- | :--- |
| `PHP_FPM_PM` | `pm` | `dynamic` | Process manager mode: `static`, `dynamic`, or `ondemand`. |
| `PHP_FPM_MAX_CHILDREN` | `pm.max_children` | `5` | Max number of FPM worker processes. |
| `PHP_FPM_START_SERVERS` | `pm.start_servers` | `2` | Workers started on boot (dynamic mode). |
| `PHP_FPM_MIN_SPARE` | `pm.min_spare_servers` | `1` | Minimum idle workers (dynamic mode). |
| `PHP_FPM_MAX_SPARE` | `pm.max_spare_servers` | `3` | Maximum idle workers (dynamic mode). |
| `PHP_FPM_MAX_REQUESTS` | `pm.max_requests` | `0` | Recycle workers after N requests. Prevents memory leaks. |

#### Recommended production settings

```yaml
environment:
   # Don't check if files changed on disk (opcache serves from memory)
   - PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
   # Fixed pool of workers, sized for available memory (~50MB per worker)
   - PHP_FPM_PM=static
   - PHP_FPM_MAX_CHILDREN=30
   - PHP_FPM_MAX_REQUESTS=1000
```

> **Tip:** To estimate `max_children`, divide your container memory limit by ~50MB per worker. For a 2GB container: `2048 / 50 ≈ 40`. Leave headroom for Nginx, Supervisor, and other processes — `30` is a safe starting point.

### 7. Maintenance Mode
Control Laravel's maintenance mode during container boot (e.g., for deployments).

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_MAINTENANCE_BOOT` | `false` | Enables maintenance mode during boot. Skipped if `vendor/` doesn't exist. |
| `MAINTENANCE_SECRET` | _(auto-generated)_ | Custom secret for bypassing maintenance mode. |
| `MAINTENANCE_RENDER` | `errors::503` | Custom view to render during maintenance. |
| `MAINTENANCE_RETRY` | `10` | Retry-After header value in seconds. |

---

## Examples

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

> Mount `/app:ro` and only make writable the directories Laravel needs (`storage/logs`, `storage/framework`, `bootstrap/cache`). This prevents a compromised app from modifying its own code.

---

## SSL / HTTPS (Port 8443)

All image variants serve HTTPS on port **8443** using a self-signed certificate that is generated automatically on first boot. HTTP continues to be served on port **8000**.

This is useful when a reverse proxy (Traefik, Nginx, Caddy, etc.) terminates TLS and forwards traffic to the container. By forwarding to port **8443** instead of 8000, the application sees a genuine HTTPS connection without any code changes, `X-Forwarded-Proto` headers, or `TrustProxies` middleware configuration.

```yml
ports:
   - "8000:8000"  # HTTP
   - "8443:8443"  # HTTPS (self-signed)
```

The certificate is stored at `/etc/nginx/ssl/selfsigned.{crt,key}`. To use your own certificate, mount it into the container:

```yml
volumes:
   - ./my-cert.crt:/etc/nginx/ssl/selfsigned.crt:ro
   - ./my-cert.key:/etc/nginx/ssl/selfsigned.key:ro
```

When a certificate already exists at that path, the automatic generation is skipped.

## Docker HEALTHCHECK

All image variants include a `HEALTHCHECK` instruction that polls `http://localhost:8000/basic_status` every 30s (start-period: 120s to allow the full boot sequence). The `/basic_status` endpoint is restricted to localhost only, so it is not reachable from outside the container.

Check health status:
```bash
docker inspect --format='{{.State.Health.Status}}' <container>
```

## Nginx Access Logging

Nginx access logs are enabled and sent to stdout in `combined` format, so they appear in `docker logs`. Per-request logs for `/favicon.ico` and `/robots.txt` are suppressed to reduce noise.

## Project Directory Ownership
- The container runs as uid 1000, to match the host user on most systems.
- Your local project permissions may need to be reset to the correct defaults (1000:1000).

For a full reset of permissions, you can run the following command in your project directory:
```bash
docker compose exec --user root php sh -c "/scripts/fix-laravel-project-permissions.sh"
```
But on macOS the default group is `staff`, so you might need to run the following command afterwards:
```bash
sudo chown -R $(whoami):staff /path/to/app
```

---

## Additional Guides

### Laravel Boost MCP
Using Laravel Boost with the docker container is totally possible with the following steps:
##### 1. Create a bridge script mcp-boost.sh in your project root directory
```bash
#!/bin/bash
# Bridge for Laravel Boost
cd "$(dirname "$0")"
$(which docker) compose exec -T php php artisan boost:mcp
```
Don't forget to make the script executable: `chmod +x mcp-boost.sh`

##### 2. Setup your MCP configuration to use the bridge script
```bash
{
  "mcpServers": {
    "laravel-boost": {
      "command": "./mcp-boost.sh",
      "args": []
    }
  }
}
```

##### 3. Make sure to set the working directory in the MCP settings to the project root directory
e.g. for **JetBrains AI Assistant**:
```
Settings -> Tools -> AI Assistant -> MCP -> Edit Laravel Boost -> Working Directory
```

### Xdebug
To enable xdebug, set `DEV_ENABLE_XDEBUG` to `true` in your `docker-compose.yml` file.
You can connect to the xdebug server on port `9003`.

<details>
<summary>PHPStorm Configuration (click to expand)</summary>

#### PHPStorm Configuration
1. Go to `Settings` -> `PHP` -> `Debug`
2. External Connections: **DISABLE** `Break at first line in PHP scripts`
3. Xdebug: **DISABLE** `Force break at first line when no path mapping specified`
4. Xdebug: **DISABLE** `Force break at first line when a script is outside the project`
5. Go to `Settings` -> `PHP` -> `Servers`
6. Add a new server with name "laravel" according to the docker-compose configuration:
   - Name: `laravel`
   - Host: `localhost`
   - Port: `8000`
   - Debugger: `Xdebug`
   - **ENABLE**: `Use path mappings`: `path/to/your/project` -> `/app`
7. Install [browser extension](https://www.jetbrains.com/help/phpstorm/browser-debugging-extensions.html) and enable it in the correct tab.
8. Activate telephone icon in PHPStorm to listen for incoming connections.
</details>


### Serving Javascript app with integrated nginx
Create a custom nginx.conf in your repository, and mount it in place of the default one.
Also, mount your javascript app in the `/my-app` directory.
```yml
services:
   php:
      volumes:
         - ./nginx.conf:/etc/nginx/http.d/default.conf
         - ../my-app:/js-app
```

In the config file, add the following location block (after `/basic_status`) to serve your javascript app.

<details>
<summary>nginx config for JS app serving (click to expand)</summary>

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

# Handle all SPA routes under /app/*
location ^~ /app/ {
    alias /js-app/;
    index index.html;

    # SPA fallback: this ensures /app/* routes always hit the frontend
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


### Adding Chromium for PDF generation

Chromium is **not** included in the default images to keep them smaller (~200MB savings). To use Chromium for PDF generation, use the `-chromium` image variant:

```yaml
image: ghcr.io/forlaravel/docker:latest-php8.4-fpm-chromium
```

When building locally, pass the `--chromium` flag:
```bash
./build-image.sh 8.4 fpm --chromium
```

Or use the `INSTALL_CHROMIUM` build arg directly:
```bash
docker buildx build --build-arg INPUT_PHP=8.4 --build-arg INSTALL_CHROMIUM=true \
   --file ./src/php-fpm/Dockerfile --load .
```

Install the package `spatie/laravel-pdf` and configure it to use the `chrome` driver.

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
   /**
    * Get printer instance
    */
   public static function getPrinter(): PdfBuilder {
      return \Spatie\LaravelPdf\Support\pdf()->withBrowsershot(function (Browsershot $browsershot) {
         $browsershot->setOption('executablePath', '/usr/bin/chromium-browser');
      });
   }
}

```

### Adding Redis
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

### Adding PhpMyAdmin
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

### Custom scripts
You can hook into the boot process by mounting your custom script directories.
The scripts will be executed in alphabetical order.

```yml
services:
   php:
      volumes:
         - ./docker/before-boot:/custom-scripts/before-boot
         - ./docker/after-boot:/custom-scripts/after-boot
```

### Debugging nginx configuration
You can print all variables by adding this location in your `nginx.conf` file.
<details>
<summary>nginx config (click to expand)</summary>

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
