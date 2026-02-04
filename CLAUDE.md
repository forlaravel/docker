# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Laravel AIO (All-In-One) Docker image for running Laravel applications. Provides a complete runtime with PHP, Nginx, Supervisor, and optional workers in a single container. Published to `ghcr.io/forlaravel/docker`.

Current version: **1.3** | Supported PHP: **8.3, 8.4, 8.5** | Supported Laravel: **10, 11, 12, 13**

## Build Commands

```bash
# Build a single image locally (auto-detects platform)
./build-image.sh <phpVersion> <imageType>
# e.g.: ./build-image.sh 8.4 fpm

# Build and push to registry
./build-image.sh 8.4 fpm --push

# Cross-platform build
./build-image.sh 8.4 fpm --platform=linux/arm64

# Build with Chromium (appends -chromium to tags)
./build-image.sh 8.4 fpm --chromium

# Build and push all variants (with and without chromium) for PHP 8.4 and 8.3
./build-push-all.sh
```

Image types: `fpm`, `frankenphp`, `roadrunner`, `openswoole`

Image tag format: `ghcr.io/forlaravel/docker:{version}-php{X.Y}-{type}` (without Chromium) or `ghcr.io/forlaravel/docker:{version}-php{X.Y}-{type}-chromium` (with Chromium)

CI/CD is via GitHub Actions (manual `workflow_dispatch`) in `.github/workflows/build-and-push.yml`. It builds multi-arch images (amd64 + arm64) in parallel per variant.

## Architecture

### Image Variants

Each variant has its own Dockerfile in `src/php-{variant}/Dockerfile`:

- **FPM** (`src/php-fpm/`): Traditional PHP-FPM + Nginx. Base: `php:X.Y-fpm-alpine`.
- **FrankenPHP** (`src/php-frankenphp/`): Modern PHP runtime + Nginx. Base: `dunglas/frankenphp:phpX.Y-alpine`. Uses Octane.
- **RoadRunner** (`src/php-roadrunner/`): High-performance async + Nginx. Base: `php:X.Y-cli-alpine` + RoadRunner binary. Uses Octane.
- **OpenSwoole** (`src/php-openswoole/`): Async PHP + Nginx. Base: `php:X.Y-cli-alpine`. Uses Octane. PHP 8.4 only.

All Dockerfiles follow the same pattern: create `laravel` user (UID 1000), install system deps + PHP extensions, copy shared configs, set entrypoint.

### Shared Configuration (`src/shared/`)

All variants share these configs:

- **`scripts/entrypoint.sh`** (~500 lines): The main container bootstrap. Handles: graceful shutdown, custom pre/post-boot scripts, Xdebug toggling, PHP-FPM/Nginx startup, Laravel key generation, composer install, Octane setup (non-FPM), npm build, migrations/seeding, Laravel optimization, Supervisor config assembly, and maintenance mode. This is the most complex file in the repo.
- **`scripts/fix-laravel-project-permissions.sh`**: Resets ownership to `laravel:laravel` and sets correct directory/file modes, with special handling for `storage/` and `bootstrap/cache/`.
- **`supervisor/`**: Modular Supervisor configs. The entrypoint dynamically concatenates `supervisor-header.conf` with enabled worker configs based on env vars (`ENABLE_QUEUE_WORKER`, `ENABLE_HORIZON_WORKER`, etc.).
- **`nginx/`**: Nginx configs: `nginx.base.conf` (shared settings, 2GB body limit, WebSocket support), `nginx.fpm.conf` (FastCGI upstream on port 9000, includes `php-fpm-handler.conf`), `nginx.octane.conf` (Octane upstream on port 8080, includes `php-restriction.conf`). Maintenance page served on 502/504. `/basic_status` restricted to localhost for Docker HEALTHCHECK.
- **`php.ini`**: 2GB memory limit, 1800s max execution, OPcache enabled with 1GB memory.
- **`xdebug.ini`**: Disabled by default, enabled via `DEV_ENABLE_XDEBUG=true` in dev mode.

### Key Environment Variables

The entrypoint behavior is controlled by env vars:

- `ENV_DEV=true/false` - Switches between dev mode (clear caches, hot reload) and prod mode (optimize, cache)
- `DEV_ENABLE_XDEBUG`, `DEV_NPM_RUN_DEV`, `DEV_FORCE_NPM_INSTALL` - Dev-only features
- `PROD_RUN_ARTISAN_MIGRATE`, `PROD_RUN_ARTISAN_DBSEED`, `PROD_SKIP_OPTIMIZE` - Prod automation
- `ENABLE_QUEUE_WORKER`, `ENABLE_HORIZON_WORKER` - Background service toggles
- `ENABLE_MAINTENANCE_BOOT` - Maintenance mode during container boot
- `SKIP_LARAVEL_BOOT` - Skip Laravel-specific boot steps (for non-Laravel apps)
- `NGINX_RESTRICT_PHP_EXECUTION=true` - Only allow index.php execution, deny all other PHP files
- `PHP_DISABLE_FUNCTIONS` - Comma-separated list of PHP functions to disable (applied after composer install)
- `PHP_OPEN_BASEDIR` - Restrict PHP filesystem access to specified paths (applied after composer install)

### Container Runtime Flow (entrypoint.sh)

1. Register shutdown handler (graceful termination)
2. Run custom scripts from `/custom-scripts/before-boot/`
3. Toggle Xdebug if dev mode
4. Apply PHP execution restriction if `NGINX_RESTRICT_PHP_EXECUTION=true`
5. Start PHP-FPM + Nginx (or just Nginx for Octane variants)
5. Generate APP_KEY if missing, create cache/storage dirs, fix permissions
6. Enable maintenance mode if configured
7. Run `composer install` (with dev/prod-specific flags)
8. Install Octane if non-FPM variant
9. Run npm install + build (or `npm run dev` in dev mode)
10. Run migrations/seeding if configured (prod only)
11. Apply PHP hardening (`PHP_DISABLE_FUNCTIONS`, `PHP_OPEN_BASEDIR`) if configured
12. Optimize Laravel (prod) or clear caches (dev)
12. Assemble and start Supervisor with enabled workers
13. Run custom scripts from `/custom-scripts/after-boot/`
14. Disable maintenance mode

## Code Style

Per `.editorconfig`:
- **Default**: 3-space indentation, UTF-8, LF line endings
- **YAML/conf files**: 4-space indentation
- **Line length**: 130 max
