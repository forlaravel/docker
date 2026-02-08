#!/bin/bash

echo "Running entrypoint.sh..."

echo "

██╗      █████╗ ██████╗  █████╗ ██╗   ██╗███████╗██╗          █████╗   ██╗   ██████╗
██║     ██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔════╝██║         ██╔══██╗  ██║  ██╔═══██╗
██║     ███████║██████╔╝███████║██║   ██║█████╗  ██║         ███████║  ██║  ██║   ██║
██║     ██╔══██║██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝  ██║         ██╔══██║  ██║  ██║   ██║
███████╗██║  ██║██║  ██║██║  ██║ ╚████╔╝ ███████╗███████╗    ██║  ██║  ██║  ╚██████╔╝
╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚══════╝    ╚═╝  ╚═╝  ╚═╝   ╚═════╝

"
echo
echo "User: $(whoami), UID: $(id -u)"
echo


apply_php_hardening() {
   if [ -z "$PHP_DISABLE_FUNCTIONS" ] && [ -z "$PHP_OPEN_BASEDIR" ]; then
      return 0
   fi

   echo "Applying PHP security hardening..."

   if [ "$PHP_RUNTIME_CONFIG" = "fpm" ]; then
      # FPM: use php_admin_value in pool config (web requests only, CLI unaffected)
      # This allows Horizon/artisan/queue workers to use proc_open, pcntl_*, etc.
      HARDENING_FILE="/usr/local/etc/php-fpm.d/zzz-security-hardening.conf"

      if ! : > "$HARDENING_FILE" 2>/dev/null; then
         echo "ERROR: Cannot write to $HARDENING_FILE (permission denied)"
         echo "PHP security hardening FAILED - container is NOT hardened!"
         return 1
      fi

      echo "[www]" >> "$HARDENING_FILE"

      if [ -n "$PHP_DISABLE_FUNCTIONS" ]; then
         echo "php_admin_value[disable_functions] = $PHP_DISABLE_FUNCTIONS" >> "$HARDENING_FILE"
         echo "  disable_functions = $PHP_DISABLE_FUNCTIONS (FPM only)"
      fi

      if [ -n "$PHP_OPEN_BASEDIR" ]; then
         echo "php_admin_value[open_basedir] = $PHP_OPEN_BASEDIR" >> "$HARDENING_FILE"
         echo "  open_basedir = $PHP_OPEN_BASEDIR (FPM only)"
      fi

      # Reload PHP-FPM to pick up new settings
      if pgrep "php-fpm" > /dev/null; then
         echo "Reloading PHP-FPM to apply hardening..."
         kill -USR2 "$(pgrep -o php-fpm)" || true
      fi

      # Lock down the file after writing
      chmod 444 "$HARDENING_FILE"

      # Verify the file was actually written
      if [ -s "$HARDENING_FILE" ]; then
         echo "============================"
         echo "=== PHP hardening applied ==="
         echo "============================"
      else
         echo "ERROR: $HARDENING_FILE is empty after write attempt"
         echo "PHP security hardening FAILED - container is NOT hardened!"
         return 1
      fi
   else
      # Octane: build -d flags to inject into the Octane supervisor command only
      # Horizon/queue workers remain unrestricted (they need proc_open, pcntl_*, etc.)
      PHP_HARDENING_CLI_ARGS=""

      if [ -n "$PHP_DISABLE_FUNCTIONS" ]; then
         # Warn if proc_open is disabled on runtimes that need it to start
         if [ "$PHP_RUNTIME_CONFIG" != "swoole" ]; then
            if echo "$PHP_DISABLE_FUNCTIONS" | grep -q "proc_open"; then
               echo "WARNING: proc_open is in PHP_DISABLE_FUNCTIONS but $PHP_RUNTIME_CONFIG needs it to start."
               echo "         Removing proc_open from the Octane process restrictions."
               echo "         (proc_open is still disabled for FPM web requests if using FPM runtime)"
               PHP_DISABLE_FUNCTIONS_OCTANE=$(echo "$PHP_DISABLE_FUNCTIONS" | sed 's/proc_open//;s/,,/,/g;s/^,//;s/,$//')
            else
               PHP_DISABLE_FUNCTIONS_OCTANE="$PHP_DISABLE_FUNCTIONS"
            fi
         else
            PHP_DISABLE_FUNCTIONS_OCTANE="$PHP_DISABLE_FUNCTIONS"
         fi
         if [ -n "$PHP_DISABLE_FUNCTIONS_OCTANE" ]; then
            PHP_HARDENING_CLI_ARGS="$PHP_HARDENING_CLI_ARGS -d disable_functions=$PHP_DISABLE_FUNCTIONS_OCTANE"
            echo "  disable_functions = $PHP_DISABLE_FUNCTIONS_OCTANE (Octane process only)"
         else
            echo "  disable_functions = (none — all functions were needed by $PHP_RUNTIME_CONFIG)"
         fi
      fi

      if [ -n "$PHP_OPEN_BASEDIR" ]; then
         PHP_HARDENING_CLI_ARGS="$PHP_HARDENING_CLI_ARGS -d open_basedir=$PHP_OPEN_BASEDIR"
         echo "  open_basedir = $PHP_OPEN_BASEDIR (Octane process only)"
      fi

      echo "============================"
      echo "=== PHP hardening staged  ==="
      echo "============================"
      echo "  (will be injected into Octane supervisor command)"
   fi
}

apply_php_performance() {
   local has_opcache=false
   local has_fpm=false

   # --- OPcache tuning (global PHP ini, applies to all SAPIs) ---
   # Base defaults are in php.ini; env vars here override for runtime tuning.
   # In production (non-dev), disable timestamp validation for best performance.
   OPCACHE_INI="/usr/local/etc/php/conf.d/zzz-performance.ini"

   if ! : > "$OPCACHE_INI" 2>/dev/null; then
      echo "WARNING: Cannot write to $OPCACHE_INI — skipping OPcache tuning"
   else
      # Production default: disable timestamp checking (env var overrides)
      if [ "$ENV_DEV" != "true" ] && [ -z "$PHP_OPCACHE_VALIDATE_TIMESTAMPS" ]; then
         PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
         PHP_OPCACHE_REVALIDATE_FREQ=${PHP_OPCACHE_REVALIDATE_FREQ:-0}
      fi

      # --- PHP runtime overrides ---
      if [ -n "$PHP_MEMORY_LIMIT" ]; then
         echo "memory_limit=$PHP_MEMORY_LIMIT" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_MAX_EXECUTION_TIME" ]; then
         echo "max_execution_time=$PHP_MAX_EXECUTION_TIME" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_POST_MAX_SIZE" ]; then
         echo "post_max_size=$PHP_POST_MAX_SIZE" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_UPLOAD_MAX_FILESIZE" ]; then
         echo "upload_max_filesize=$PHP_UPLOAD_MAX_FILESIZE" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      # --- OPcache overrides ---
      if [ -n "$PHP_OPCACHE_VALIDATE_TIMESTAMPS" ]; then
         echo "opcache.validate_timestamps=$PHP_OPCACHE_VALIDATE_TIMESTAMPS" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_REVALIDATE_FREQ" ]; then
         echo "opcache.revalidate_freq=$PHP_OPCACHE_REVALIDATE_FREQ" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_MEMORY" ]; then
         echo "opcache.memory_consumption=$PHP_OPCACHE_MEMORY" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_MAX_FILES" ]; then
         echo "opcache.max_accelerated_files=$PHP_OPCACHE_MAX_FILES" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_INTERNED_STRINGS" ]; then
         echo "opcache.interned_strings_buffer=$PHP_OPCACHE_INTERNED_STRINGS" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_JIT" ]; then
         echo "opcache.jit=$PHP_OPCACHE_JIT" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_JIT_BUFFER" ]; then
         echo "opcache.jit_buffer_size=$PHP_OPCACHE_JIT_BUFFER" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ -n "$PHP_OPCACHE_PRELOAD" ]; then
         echo "opcache.preload=$PHP_OPCACHE_PRELOAD" >> "$OPCACHE_INI"
         echo "opcache.preload_user=laravel" >> "$OPCACHE_INI"
         has_opcache=true
      fi

      if [ "$has_opcache" = true ]; then
         chmod 444 "$OPCACHE_INI"
         echo "PHP tuning applied:"
         sed 's/^/  /' "$OPCACHE_INI"
      fi
   fi

   # --- FPM pool tuning (FPM only) ---
   # Stock www.conf ships with pm.max_children=5 which is far too low.
   # Apply sensible defaults for a typical container; env vars override any value.
   if [ "$PHP_RUNTIME_CONFIG" = "fpm" ]; then
      FPM_PERF="/usr/local/etc/php-fpm.d/zzz-performance.conf"

      if ! : > "$FPM_PERF" 2>/dev/null; then
         echo "WARNING: Cannot write to $FPM_PERF — skipping FPM tuning"
      else
         echo "[www]" >> "$FPM_PERF"

         # Defaults: dynamic pool sized for a typical 2GB container (~100MB per child)
         echo "pm = ${PHP_FPM_PM:-dynamic}" >> "$FPM_PERF"
         echo "pm.max_children = ${PHP_FPM_MAX_CHILDREN:-20}" >> "$FPM_PERF"
         echo "pm.start_servers = ${PHP_FPM_START_SERVERS:-6}" >> "$FPM_PERF"
         echo "pm.min_spare_servers = ${PHP_FPM_MIN_SPARE:-3}" >> "$FPM_PERF"
         echo "pm.max_spare_servers = ${PHP_FPM_MAX_SPARE:-10}" >> "$FPM_PERF"
         # Recycle workers after N requests to prevent memory leaks (0 = never)
         echo "pm.max_requests = ${PHP_FPM_MAX_REQUESTS:-500}" >> "$FPM_PERF"

         chmod 444 "$FPM_PERF"
         echo "FPM pool tuning applied:"
         sed 's/^/  /' "$FPM_PERF"

         # Reload FPM to pick up new settings
         if pgrep "php-fpm" > /dev/null; then
            echo "Reloading PHP-FPM to apply performance tuning..."
            kill -USR2 "$(pgrep -o php-fpm)" || true
         fi
      fi
      has_fpm=true
   fi

   if [ "$has_opcache" = true ] || [ "$has_fpm" = true ]; then
      echo "============================"
      echo "=== Performance tuned    ==="
      echo "============================"
   fi
}

shutdown_handler() {
   # NOTE: In the most recent Docker version, logging is disabled once stop signal received :( However it still works.
   echo "STOP signal received..."
   # Add any cleanup or graceful shutdown tasks here

   if pgrep supervisord > /dev/null; then
       echo "Killing Supervisor..."
       killall supervisord || true
   fi

   if php artisan | grep -q "octane"; then
       echo "Stopping Laravel Octane..."
       php artisan octane:stop || true
   fi

   if php artisan | grep -q "horizon"; then
       echo "Terminating Laravel Horizon..."
       php artisan horizon:terminate || true
   fi

   exit 0
}
trap 'shutdown_handler' SIGINT SIGQUIT SIGTERM

# Run any custom scripts that are mounted to /custom-scripts/before-boot
if [ -d "/custom-scripts/before-boot" ]; then
   echo "Running custom scripts..."
   for f in /custom-scripts/before-boot/*.sh; do
      echo "Running $f..."
      bash "$f" || true
   done
fi

# Enable xdebug if needed
if [ "$DEV_ENABLE_XDEBUG" = "true" ]; then
   if [ "$ENV_DEV" = "true" ]; then
      echo "Enabling Xdebug..."
      mv /usr/local/etc/php/conf.d/xdebug.ini.disabled /usr/local/etc/php/conf.d/xdebug.ini || true
   else
      echo "Disabling Xdebug..."
      if [ -f /usr/local/etc/php/conf.d/xdebug.ini ]; then
          mv /usr/local/etc/php/conf.d/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini.disabled
      fi
      echo "ERROR: Xdebug can only be enabled in DEV environment."
   fi
else
   echo "Disabling Xdebug..."
   if [ -f /usr/local/etc/php/conf.d/xdebug.ini ]; then
       mv /usr/local/etc/php/conf.d/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini.disabled
   fi
fi

# Generate self-signed SSL certificate if not already present (allows user-mounted certs)
if [ ! -f "/etc/nginx/ssl/selfsigned.crt" ]; then
   echo "Generating self-signed SSL certificate..."
   mkdir -p /etc/nginx/ssl
   openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/selfsigned.key \
      -out /etc/nginx/ssl/selfsigned.crt \
      -subj "/CN=localhost" 2>/dev/null
   echo "============================"
   echo "=== SSL cert generated   ==="
   echo "============================"
else
   echo "SSL certificate already exists, skipping generation."
fi

# Restrict PHP execution to index.php only (security hardening)
if [ "$NGINX_RESTRICT_PHP_EXECUTION" = "true" ]; then
   echo "Restricting PHP execution to index.php only..."
   if [ "$PHP_RUNTIME_CONFIG" = "fpm" ]; then
      # For FPM: replace the handler with index.php-only + deny all other PHP files
      cat > /etc/nginx/php-fpm-handler.conf << 'NGINX_CONF'
location = /index.php {
   include fastcgi_params;
   fastcgi_pass localhost:9000;
   fastcgi_index index.php;
   fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
   fastcgi_read_timeout 600s;
   fastcgi_send_timeout 600s;
}

location ~ \.php$ {
   deny all;
   return 404;
}
NGINX_CONF
   else
      # For Octane: add deny block for direct PHP file access and use exact match for index.php
      cat > /etc/nginx/php-restriction.conf << 'NGINX_CONF'
location ~ \.php$ {
   deny all;
   return 404;
}
NGINX_CONF
      # Change prefix match to exact match for /index.php so deny block doesn't intercept it
      sed -i 's|location /index.php {|location = /index.php {|g' /etc/nginx/http.d/default.conf
   fi
   echo "============================"
   echo "=== PHP exec restricted  ==="
   echo "============================"
fi

# Starting earlier to allow hosting non-Laravel apps
if [ "$PHP_RUNTIME_CONFIG" = "fpm" ]; then
   # Start PHP-FPM if not running
   if ! pgrep "php-fpm" > /dev/null; then
      echo "Starting PHP-FPM..."
      php-fpm &
   else
       echo "PHP-FPM is already running."
   fi
fi

# Apply Nginx client_max_body_size override if set
if [ -n "$NGINX_CLIENT_MAX_BODY_SIZE" ]; then
   echo "Setting Nginx client_max_body_size to $NGINX_CLIENT_MAX_BODY_SIZE..."
   sed -i "s|client_max_body_size 128M;|client_max_body_size $NGINX_CLIENT_MAX_BODY_SIZE;|" /etc/nginx/nginx.conf
fi

# Start Nginx if not running
if ! pgrep "nginx" > /dev/null; then
   echo "Starting Nginx..."
   nginx &
else
    echo "Nginx is already running."
fi

# Skip Laravel boot
if [ "$SKIP_LARAVEL_BOOT" = "true" ]; then
   echo "Skipping Laravel boot..."

   # Apply PHP security hardening if configured
   apply_php_hardening

   # Apply PHP performance tuning if configured
   apply_php_performance

   # Start cron (generic, not Laravel-specific)
   crond start -f -l 1 &
   echo "============================"
   echo "=== Cron service started ==="
   echo "============================"

   # Run any custom scripts that are mounted to /custom-scripts/after-boot
   if [ -d "/custom-scripts/after-boot" ]; then
      echo "Running custom scripts..."
      for f in /custom-scripts/after-boot/*.sh; do
         echo "Running $f..."
         bash "$f" || true
      done
   fi

   # wait forever
   while true; do
      tail -f /dev/null &
      wait ${!}
   done
fi

cd /app || exit 1

echo "alias pa=\"php artisan\"; alias ll=\"ls -lsah\"" > ~/.bashrc

# Check if the Laravel application is not present in /app
if [ ! -f "/app/artisan" ]; then
    echo "No Laravel application found in /app. Exiting..."
    exit 1
else
    echo "Laravel application found in /app."
fi

# Check and generate APP_KEY if needed
if [ -f "/app/.env" ]; then
    APP_KEY=$(grep -E "^APP_KEY=" /app/.env | cut -d '=' -f2- | xargs)
    if [ -z "$APP_KEY" ]; then
        echo "APP_KEY is empty. Generating new application key..."
        if php artisan key:generate; then
            echo "============================"
            echo "===  APP_KEY generated   ==="
            echo "============================"
        else
            echo "ERROR: Failed to generate APP_KEY. Please check your Laravel installation."
            exit 1
        fi
    else
        echo "APP_KEY is already set."
    fi
else
    echo "No .env file found. Skipping APP_KEY generation."
fi

# Create cache paths: mkdir -p storage/framework/{sessions,views,cache}
echo "Creating cache paths..."
mkdir -p storage/framework/sessions
mkdir -p storage/framework/views
mkdir -p storage/framework/cache

echo "============================"
echo "===  Cache paths created ==="
echo "============================"


# Fix storage permissions
if [ "$SKIP_PERMISSION_FIX" = "true" ]; then
   echo "Skipping permission fix (SKIP_PERMISSION_FIX=true)..."
else
   echo "Fixing storage and cache permissions to allow writing for www-data..."
   chown -R "$USER":www-data storage bootstrap/cache
   find storage bootstrap/cache -type d -exec chmod 775 {} \;
   find storage bootstrap/cache -type f -exec chmod 664 {} \;

   if [ -f "database/database.sqlite" ]; then
       chown "$USER":www-data database/database.sqlite
       chmod 664 database/database.sqlite
   fi

   echo "============================"
   echo "===  Permissions fixed   ==="
   echo "============================"
fi


# Enable maintenance mode if requested
MAINTENANCE_MODE_ENABLED=false
if [ "$ENABLE_MAINTENANCE_BOOT" = "true" ]; then
   # Only enable maintenance mode if vendor directory exists (skip on initial deployment)
   if [ -f "vendor/autoload.php" ]; then
      echo "Enabling maintenance mode..."
      
      # Build the maintenance command arguments array
      MAINTENANCE_ARGS=("down")
      
      # Add render option (use custom or default)
      if [ -n "$MAINTENANCE_RENDER" ]; then
         MAINTENANCE_ARGS+=("--render=$MAINTENANCE_RENDER")
      else
         MAINTENANCE_ARGS+=("--render=errors::503")
      fi
      
      # Add secret option (use custom or generate automatically)
      if [ -n "$MAINTENANCE_SECRET" ]; then
         MAINTENANCE_ARGS+=("--secret=$MAINTENANCE_SECRET")
      else
         MAINTENANCE_ARGS+=("--with-secret")
      fi
      
      # Add retry option (use custom or default)
      if [ -n "$MAINTENANCE_RETRY" ]; then
         # Validate that MAINTENANCE_RETRY is a number
         if [[ "$MAINTENANCE_RETRY" =~ ^[0-9]+$ ]]; then
            MAINTENANCE_ARGS+=("--retry=$MAINTENANCE_RETRY")
         else
            echo "WARNING: MAINTENANCE_RETRY must be a number. Using default value of 10."
            MAINTENANCE_ARGS+=("--retry=10")
         fi
      else
         MAINTENANCE_ARGS+=("--retry=10")
      fi
      
      # Execute the maintenance command
      if php artisan "${MAINTENANCE_ARGS[@]}"; then
         MAINTENANCE_MODE_ENABLED=true
         echo "============================"
         echo "=== Maintenance enabled  ==="
         echo "============================"
      else
         echo "WARNING: Failed to enable maintenance mode"
      fi
   else
      echo "vendor/autoload.php not found. Skipping maintenance mode (initial deployment)."
   fi
fi

if [ "$SKIP_INSTALL" = "true" ]; then
   echo "Skipping dependency installation (SKIP_INSTALL=true)..."
else
   echo "Installing Composer..."
   if [ "$ENV_DEV" = "true" ]; then
      if [ ! -d "vendor" ]; then
         composer install --optimize-autoloader --no-interaction --prefer-dist
      else
         echo "vendor already exists. Skipping composer install."
      fi
   else
      composer install --optimize-autoloader --no-interaction --no-progress --prefer-dist
   fi
   echo "=========================="
   echo "=== Composer installed ==="
   echo "=========================="
   echo
   echo "PHP runtime configuration: $PHP_RUNTIME_CONFIG"
   echo

   if [ "$PHP_RUNTIME_CONFIG" = "frankenphp" ]; then
      # check if laravel/octane is installed
      if ! jq -e '.require["laravel/octane"] // .["require-dev"]?["laravel/octane"]' composer.json; then
          echo "Laravel Octane/FrankenPHP is not installed. Installing..."
          composer require laravel/octane --no-interaction --prefer-dist
          php artisan octane:install --server=frankenphp --no-interaction
      else
          echo "Laravel Octane is already installed."
      fi

      npm install --save-dev chokidar

      echo "=========================="
      echo "===  Octane installed  ==="
      echo "=========================="
   fi

   if [ "$PHP_RUNTIME_CONFIG" = "roadrunner" ]; then
      # check if laravel/octane is installed
      if ! jq -e '.require["laravel/octane"] // .["require-dev"]?["laravel/octane"]' composer.json; then
         echo "Laravel Octane/Roadrunner is not installed. Installing..."
         composer require laravel/octane --no-interaction --prefer-dist
         php artisan octane:install --server=roadrunner --no-interaction
      else
          echo "Laravel Octane is already installed."
      fi

      npm install --save-dev chokidar

      echo "=========================="
      echo "===  Octane installed  ==="
      echo "=========================="
   fi

   if [ "$PHP_RUNTIME_CONFIG" = "swoole" ]; then
      # check if laravel/octane is installed
      if ! jq -e '.require["laravel/octane"] // .["require-dev"]?["laravel/octane"]' composer.json; then
         echo "Laravel Octane/Swoole is not installed. Installing..."
         composer require laravel/octane --no-interaction --prefer-dist
         php artisan octane:install --server=swoole --no-interaction
      else
          echo "Laravel Octane is already installed."
      fi

      npm install --save-dev chokidar

      echo "=========================="
      echo "===  Octane installed  ==="
      echo "=========================="
   fi


   echo "Installing NPM..."
   if [ "$ENV_DEV" = "true" ]; then
      if [ ! -d "node_modules" ]; then
         npm install --no-audit
      elif [ "$DEV_FORCE_NPM_INSTALL" = "true" ]; then
         npm install --no-audit
      else
         echo "node_modules already exists. Skipping npm install."
      fi
   else
      npm install --no-audit
   fi

   echo "=========================="
   echo "===   NPM installed    ==="
   echo "=========================="


   echo "Building NPM..."
   if [ "$ENV_DEV" = "true" ]; then
      if [ "$DEV_NPM_RUN_DEV" = "true" ]; then
         npm run dev -- --host &
      else
         echo "Skipping DEV-Server..."
      fi
   else
      npm run build
   fi
   echo "=========================="
   echo "===     NPM built      ==="
   echo "=========================="
fi


echo "Migrating database..."
if [ "$ENV_DEV" = "true" ]; then
   echo "No automatic migrations will run with ENV_DEV=true."
else
   if [ "$PROD_RUN_ARTISAN_MIGRATE" = "true" ]; then
      php artisan migrate --force
   else
      echo "Automatic migrations are disabled..."
   fi
fi
echo "============================"
echo "=== Migrations completed ==="
echo "============================"


echo "Seeding database..."
if [ "$ENV_DEV" = "true" ]; then
   echo "No automatic seeding will run with ENV_DEV=true."
else
   if [ "$PROD_RUN_ARTISAN_DBSEED" = "true" ]; then
      php artisan db:seed --force
   else
      echo "Automatic seeding is disabled..."
   fi
fi
echo "============================"
echo "===   Seeding completed  ==="
echo "============================"


# Apply PHP security hardening if configured
apply_php_hardening

# Apply PHP performance tuning if configured
apply_php_performance

if [ "$SKIP_INSTALL" = "true" ]; then
   echo "Skipping optimization (SKIP_INSTALL=true)..."
else
   echo "Optimizing Laravel..."
   if [ "$ENV_DEV" = "true" ]; then
      php artisan optimize:clear
      php artisan view:clear
      php artisan config:clear
      php artisan route:clear
   else
      if [ "$PROD_SKIP_OPTIMIZE" = "true" ]; then
         echo "Skipping Laravel optimization..."
      else
         php artisan optimize
         php artisan view:cache
         php artisan config:cache
         php artisan route:cache
      fi
   fi
   echo "============================"
   echo "===  Laravel optimized   ==="
   echo "============================"

   echo "Optimizing Laravel Filament..."
   if php artisan | grep -q "filament"; then
      if [ "$ENV_DEV" = "true" ]; then
         php artisan filament:optimize-clear
      else
         php artisan filament:optimize
      fi
   fi
   echo "============================"
   echo "===  Filament optimized  ==="
   echo "============================"
fi

# Start cron in foreground with minimal logging (level 1)
crond start -f -l 1 &
echo "============================"
echo "=== Cron service started ==="
echo "============================"


# Read laravel .env file
if [ -f "/app/.env" ]; then
   declare -A LARAVEL_ENV
   while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip empty lines and comments
      [[ -z "$line" || "$line" == \#* ]] && continue
      # Split on first '=' only
      key="${line%%=*}"
      value="${line#*=}"
      # Strip surrounding quotes from value
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
      if [[ -n "$key" ]]; then
         LARAVEL_ENV[$key]=$value
      fi
   done < "/app/.env"
fi

cat /etc/supervisor/conf.d/supervisor-header.conf > /etc/supervisor/conf.d/laravel-worker-compiled.conf

echo "Adding supercronic supervisor config..."
echo "" >> /etc/supervisor/conf.d/laravel-worker-compiled.conf
cat /etc/supervisor/conf.d/supercronic-worker.conf >> /etc/supervisor/conf.d/laravel-worker-compiled.conf

echo "============================"
echo "=== Supercronic added    ==="
echo "============================"

echo "Adding schedule supervisor config..."
echo "" >> /etc/supervisor/conf.d/laravel-worker-compiled.conf
cat /etc/supervisor/conf.d/schedule-worker.conf >> /etc/supervisor/conf.d/laravel-worker-compiled.conf

echo "=================================="
echo "===   Schedule Worker added    ==="
echo "=================================="

if [ "$ENABLE_QUEUE_WORKER" = "true" ]; then
   echo "Adding queue supervisor config..."
   echo "" >> /etc/supervisor/conf.d/laravel-worker-compiled.conf
   cat /etc/supervisor/conf.d/queue-worker.conf >> /etc/supervisor/conf.d/laravel-worker-compiled.conf

   echo "============================"
   echo "===  Queue Worker added  ==="
   echo "============================"
fi

if [ "$ENABLE_HORIZON_WORKER" = "true" ]; then
   echo "Adding horizon supervisor config..."
   echo "" >> /etc/supervisor/conf.d/laravel-worker-compiled.conf
   cat /etc/supervisor/conf.d/horizon-worker.conf >> /etc/supervisor/conf.d/laravel-worker-compiled.conf

   echo "============================"
   echo "===    Horizon added     ==="
   echo "============================"
fi

if [ "$PHP_RUNTIME_CONFIG" != "fpm" ]; then
   OCTANE_SERVER=${LARAVEL_ENV[OCTANE_SERVER]}

   if [ -z "$OCTANE_SERVER" ]; then
      # Try to read from config/octane.php
      OCTANE_SERVER=$(grep -E 'env\(\s*["'"'"']OCTANE_SERVER["'"'"']\s*,\s*["'"'"'][^"'"'"']+["'"'"']' config/octane.php | sed -E 's/.*OCTANE_SERVER["'"'"']\s*,\s*["'"'"']([^"'"'"']+)["'"'"'].*/\1/')
   fi

   if [ -z "$OCTANE_SERVER" ]; then
      echo "ERROR: Could not <OCTANE_SERVER> in .env or config/octane.php."
      exit 1
   fi

   if [ "$PHP_RUNTIME_CONFIG" != "$OCTANE_SERVER" ]; then
      echo "ERROR: Mismatch between PHP_RUNTIME_CONFIG ($PHP_RUNTIME_CONFIG) and LARAVEL_ENV[OCTANE_SERVER] ($OCTANE_SERVER)."
      echo "Please ensure they are consistent."
      exit 1
   fi

   echo "Adding Octane supervisor config..."
   if [ "$ENV_DEV" = "true" ]; then
      cat /etc/supervisor/conf.d/octane-worker-dev.conf >> /etc/supervisor/conf.d/laravel-worker-compiled.conf
   else
      cat /etc/supervisor/conf.d/octane-worker-prod.conf >> /etc/supervisor/conf.d/laravel-worker-compiled.conf
   fi
   echo "============================"
   echo "===     Octane added     ==="
   echo "============================"
else
   echo "PHP_RUNTIME_CONFIG is set to <fpm>. Skipping Octane start."
fi

# Inject PHP hardening -d flags into Octane supervisor command (non-FPM only)
if [ -n "$PHP_HARDENING_CLI_ARGS" ]; then
   sed -i "s|command=php /app/artisan octane:start|command=php${PHP_HARDENING_CLI_ARGS} /app/artisan octane:start|" /etc/supervisor/conf.d/laravel-worker-compiled.conf
   echo "PHP hardening injected into Octane command:"
   grep "command=php" /etc/supervisor/conf.d/laravel-worker-compiled.conf | grep octane || true
   echo "============================"
   echo "=== PHP hardening applied ==="
   echo "============================"
fi

supervisord -n -c /etc/supervisor/conf.d/laravel-worker-compiled.conf &

echo "============================"
echo "===  Supervisor started  ==="
echo "============================"

echo "============================"
echo "===      PHP READY       ==="
echo "============================"

# Run any custom scripts that are mounted to /custom-scripts/after-boot
if [ -d "/custom-scripts/after-boot" ]; then
   echo "Running custom scripts..."
   for f in /custom-scripts/after-boot/*.sh; do
      echo "Running $f..."
      bash "$f" || true
   done
fi

# Disable maintenance mode if it was enabled
if [ "$MAINTENANCE_MODE_ENABLED" = "true" ]; then
   if [ -f "vendor/autoload.php" ]; then
      echo "Disabling maintenance mode..."
      if php artisan up; then
         echo "============================"
         echo "=== Maintenance disabled ==="
         echo "============================"
      else
         echo "WARNING: Failed to disable maintenance mode"
      fi
   else
      echo "WARNING: Cannot disable maintenance mode - vendor/autoload.php not found"
   fi
fi

# wait forever
while true; do
   tail -f /dev/null &
   wait ${!}
done
