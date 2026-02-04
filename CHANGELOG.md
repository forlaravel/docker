# Changelog

## Version 1.3.3 (2026-02-04)

### Registry & Branding
- Rebrand from `jonaaix/laravel-aio-docker` to `ghcr.io/forlaravel/docker`
- Build scripts and CI now produce both versioned tags (e.g. `1.3-php8.4-fpm`) and `latest` tags (e.g. `latest-php8.4-fpm`)

### Security Hardening
- Add `HEALTHCHECK` on all image variants
- Add Nginx security headers: `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `X-XSS-Protection`, `Permissions-Policy`
- PHP session cookie hardening
- Add `NGINX_RESTRICT_PHP_EXECUTION` env var to only allow `index.php` execution
- Add runtime `PHP_DISABLE_FUNCTIONS` and `PHP_OPEN_BASEDIR` hardening env vars
- Restrict `/basic_status` endpoint to localhost only

### New Features
- Self-signed SSL certificate on port 8443 for reverse-proxy and local HTTPS use cases
- Chromium is now optional; default images ship without it (~200MB savings)
- New `-chromium` tagged variants (e.g. `1.3-php8.4-fpm-chromium`) for Puppeteer/Browsershot PDF generation
- Build scripts and CI produce both standard and chromium variants

### Logging Improvements
- Add `set_real_ip_from` directives to FPM Nginx config so logs show real client IPs instead of Docker internal IPs
- Silence `/basic_status` health check access logging on all variants
- Disable PHP-FPM access log to remove duplicate log lines (Nginx already logs with more detail)

### Other
- Inline maintenance page CSS (remove Tailwind CDN dependency)
- Improve `.env` parsing in entrypoint
- Add CI version tag validation
- Add `.dockerignore` and `CLAUDE.md`
- Add SSL/HTTPS documentation to README

## Version 1.3.2 (PHP 8.4 and PHP 8.5)
- Moved image registry to GitHub (ghcr.io)
- Automatically generate `APP_KEY` on first run if not set to prevent boot errors

## Version 1.3.1 (PHP 8.4)
- Replace Laravel Scheduler cron with Supervisor task
- Install supercronic instead of cron, config via /etc/supercronic.txt
- Supervisor log output to stdout/stderr


## Version 1.3 (PHP 8.3, PHP 8.4)
- Add `jq` package to the Docker image for JSON processing.
- Check for `laravel/octane` package in `composer.json` instead of running `php artisan`.
- Add `chromium` and dependencies for painless puppeteer PDF generation.
- Make OCTANE_SERVER in `.env` optional, read from `config/octane.php` if not set.
- Run container as `laravel` user with UID 1000 and GID 1000 by default.
- BREAKING: Default port changed from `80` to `8000` due to reduction of privileges.
- Added a permission fixer script to reset file and dir permissions correctly.

## Version 1.2 (PHP 8.3, PHP 8.4)

- Removed `ENABLE_SUPERVISOR` flag. It will be enabled by default.
- Booting `roadrunner/frankenphp/swoole` will require having a matching `OCTANE_SERVER` set in `.env`
- Laravel Octane will be automatically handled by supervisor
- Storage and cache permissions are now set to `root:www-data`. This will fix bidirectional issues when using a directory mount.
  However, it requires your host user (only on Linux) to be in www-data group `sudo usermod -aG www-data $USERNAME`.
- Removed `fii/vips` driver in favor of `zend.max_allowed_stack_size` to enhance security. ImageMagick would have just slightly worse performance.
- Added `ll` alias for `ls -lsah`

```shell
# Dynamically insert the current user into the Docker configuration
echo "{\"userns-remap\": \"${USER}\"}" > /etc/docker/daemon.json

# Restart Docker service to apply changes
systemctl restart docker
```

