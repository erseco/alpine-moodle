#!/bin/sh

set -e

if [ -z "$PLUGINS" ]; then
  echo "No plugins to install."
  exit 0
fi

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Cleanup function to ensure we don't leave temporary files
cleanup() {
  echo "Cleaning up temporary files..."
  rm -rf "$TEMP_DIR"
}

# Set trap to ensure cleanup happens even on error
trap cleanup EXIT

# Convert PLUGINS to a list
for entry in $PLUGINS; do
  # Validate format
  if ! echo "$entry" | grep -q "="; then
    echo "Error: Invalid plugin format. Expected 'type_name=url', got '$entry'"
    exit 1
  fi

  plugin_name=$(echo "$entry" | cut -d '=' -f 1)
  plugin_url=$(echo "$entry" | cut -d '=' -f 2)
  plugin_type=$(echo "$plugin_name" | cut -d '_' -f 1)
  plugin_subdir=$(echo "$plugin_name" | cut -d '_' -f 2-)

  echo "Installing plugin $plugin_name from $plugin_url"

  # Download with error handling
  if ! curl -L -s -S -f "$plugin_url" -o "$plugin_name.zip"; then
    echo "Error: Failed to download plugin from $plugin_url"
    exit 1
  fi

  # Unzip with error handling
  if ! unzip -q "$plugin_name.zip"; then
    echo "Error: Failed to unzip $plugin_name.zip"
    exit 1
  fi

  # Move to the corresponding path
  case "$plugin_type" in
    mod)      target="/var/www/html/mod/$plugin_subdir" ;;
    block)    target="/var/www/html/blocks/$plugin_subdir" ;;
    theme)    target="/var/www/html/theme/$plugin_subdir" ;;
    local)    target="/var/www/html/local/$plugin_subdir" ;;
    report)   target="/var/www/html/report/$plugin_subdir" ;;
    auth)     target="/var/www/html/auth/$plugin_subdir" ;;
    enrol)    target="/var/www/html/enrol/$plugin_subdir" ;;
    filter)   target="/var/www/html/filter/$plugin_subdir" ;;
    tool)     target="/var/www/html/admin/tool/$plugin_subdir" ;;
    qtype)    target="/var/www/html/question/type/$plugin_subdir" ;;
    qformat)  target="/var/www/html/question/format/$plugin_subdir" ;;
    qbehaviour) target="/var/www/html/question/behaviour/$plugin_subdir" ;;
    *)        
      echo "Warning: Unknown plugin type: $plugin_type"
      echo "Attempting to install in /var/www/html/$plugin_type/$plugin_subdir"
      target="/var/www/html/$plugin_type/$plugin_subdir" 
      mkdir -p "$(dirname "$target")"
      ;;
  esac

  if [ -d "$plugin_subdir" ]; then
    # Ensure target directory exists
    mkdir -p "$(dirname "$target")"
    
    # Remove existing plugin if it exists
    if [ -d "$target" ]; then
      echo "Removing existing plugin at $target"
      rm -rf "$target"
    fi
    
    # Move plugin to target location
    mv "$plugin_subdir" "$target"
    
    # Set appropriate permissions
    chown -R www-data:www-data "$target" 2>/dev/null || true
    
    echo "Successfully installed $plugin_name to $target"
  else
    echo "Error: the ZIP does not contain the expected folder '$plugin_subdir'"
    echo "Contents of the ZIP:"
    ls -la
    exit 1
  fi
done

echo "All plugins installed successfully"
