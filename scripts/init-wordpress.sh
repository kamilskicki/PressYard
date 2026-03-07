#!/usr/bin/env bash
set -euo pipefail

WP_PATH="/var/www/html"
WP_STATE_DIR="${WP_STATE_DIR:-/var/www/state}"
WP_PACKAGE_DIRS="${WP_PACKAGE_DIRS:-/workspace/packages /workspace}"
ZIP_FINGERPRINT_FILE="${WP_STATE_DIR}/zip-packages.fingerprint"
WP_RUNTIME_UID="${WP_RUNTIME_UID:-33}"
WP_RUNTIME_GID="${WP_RUNTIME_GID:-33}"

wp_cmd() {
  wp --allow-root --path="$WP_PATH" "$@"
}

ensure_runtime_dirs() {
  local runtime_dir

  for runtime_dir in \
    "$WP_PATH/wp-content/upgrade" \
    "$WP_PATH/wp-content/languages" \
    "$WP_PATH/wp-content/cache"
  do
    mkdir -p "$runtime_dir"
    chown "$WP_RUNTIME_UID:$WP_RUNTIME_GID" "$runtime_dir" 2>/dev/null || true
    chmod 775 "$runtime_dir" 2>/dev/null || true
  done
}

collect_zip_files() {
  local dir
  local zip
  local collected=()

  for dir in $WP_PACKAGE_DIRS; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' zip; do
      collected+=("$zip")
    done < <(find "$dir" -maxdepth 1 -type f -name '*.zip' -print0 | sort -z)
  done

  printf '%s\n' "${collected[@]}"
}

zip_fingerprint() {
  local zip
  local lines=()

  while IFS= read -r zip; do
    [ -n "$zip" ] || continue
    if command -v sha256sum >/dev/null 2>&1; then
      lines+=("$(sha256sum "$zip" | awk '{print $1}')  ${zip}")
    else
      lines+=("${zip}")
    fi
  done < <(collect_zip_files)

  if [ "${#lines[@]}" -eq 0 ]; then
    echo "none"
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s\n' "${lines[@]}" | sort | sha256sum | awk '{print $1}'
  elif command -v cksum >/dev/null 2>&1; then
    printf '%s\n' "${lines[@]}" | sort | cksum | awk '{print $1}'
  else
    printf '%s\n' "${lines[@]}" | sort | tr '\n' '|'
  fi
}

echo "Waiting for WordPress runtime files..."
until [ -f "$WP_PATH/wp-load.php" ]; do
  sleep 2
done

echo "Waiting for DB connectivity..."
until wp_cmd db check >/dev/null 2>&1; do
  sleep 2
done

mkdir -p "$WP_STATE_DIR"
ensure_runtime_dirs

if ! wp_cmd core is-installed >/dev/null 2>&1; then
  echo "Installing WordPress..."
  wp_cmd core install \
    --url="${WP_URL}" \
    --title="${WP_SITE_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASSWORD}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --skip-email
else
  echo "WordPress already installed. Continuing with maintenance tasks..."
fi

for plugin in akismet hello; do
  if wp_cmd plugin is-installed "$plugin" >/dev/null 2>&1; then
    wp_cmd plugin delete "$plugin" || true
  fi
done

mapfile -t zip_files < <(collect_zip_files)
zip_count=${#zip_files[@]}
current_fingerprint="$(zip_fingerprint)"
previous_fingerprint="$(cat "$ZIP_FINGERPRINT_FILE" 2>/dev/null || true)"

current_permalink_structure="$(wp_cmd option get permalink_structure 2>/dev/null || true)"
if [ "$current_permalink_structure" != "/%postname%/" ]; then
  wp_cmd rewrite structure "/%postname%/" --hard >/dev/null
  echo "Permalinks set to post name."
fi

if [ "$zip_count" -gt 0 ] && [ "$current_fingerprint" != "$previous_fingerprint" ]; then
  for zip in "${zip_files[@]}"; do
    echo "Processing ZIP: $(basename "$zip")"

    if wp_cmd plugin install "$zip" --force --activate >/dev/null 2>&1; then
      echo "Installed and activated as plugin: $(basename "$zip")"
      continue
    fi

    if wp_cmd theme install "$zip" --force >/dev/null 2>&1; then
      echo "Installed as theme: $(basename "$zip")"
      continue
    fi

    echo "Skipped ZIP (not a valid plugin/theme package): $(basename "$zip")"
  done
  echo "$current_fingerprint" > "$ZIP_FINGERPRINT_FILE"
elif [ "$zip_count" -gt 0 ]; then
  echo "ZIP packages unchanged. Skipping reinstall."
fi

active_theme="$(wp_cmd theme list --status=active --field=name 2>/dev/null || true)"
if [ -z "$active_theme" ] && wp_cmd theme is-installed local-dev-theme >/dev/null 2>&1; then
  wp_cmd theme activate local-dev-theme || true
  active_theme="local-dev-theme"
fi

if [[ "$active_theme" == twenty* ]] && wp_cmd theme is-installed local-dev-theme >/dev/null 2>&1; then
  wp_cmd theme activate local-dev-theme || true
  active_theme="local-dev-theme"
fi

while IFS= read -r theme; do
  [ -n "$theme" ] || continue
  if [[ "$theme" == twenty* && "$theme" != "$active_theme" ]]; then
    wp_cmd theme delete "$theme" || true
  fi
done < <(wp_cmd theme list --field=name 2>/dev/null || true)

if [ "$zip_count" -eq 0 ]; then
  echo "No ZIP packages found in configured package directories."
fi

ensure_runtime_dirs

echo "WordPress initialization complete."
