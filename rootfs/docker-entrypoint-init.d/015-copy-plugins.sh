#!/bin/sh

set -e

if [ -z "$PLUGINS" ]; then
  echo "No plugins to install."
  exit 0
fi

mkdir -p /var/www/html/tmp_plugins
cd /var/www/html/tmp_plugins

# Convertir PLUGINS en lista
for entry in $PLUGINS; do
  plugin_name=$(echo "$entry" | cut -d '=' -f 1)
  plugin_url=$(echo "$entry" | cut -d '=' -f 2)
  plugin_type=$(echo "$plugin_name" | cut -d '_' -f 1)
  plugin_subdir=$(echo "$plugin_name" | cut -d '_' -f 2-)

  echo "Installing plugin $plugin_name from $plugin_url"

  curl -L "$plugin_url" -o "$plugin_name.zip"
  unzip -q "$plugin_name.zip"

  # Mover a la ruta correspondiente
  case "$plugin_type" in
    mod)    target="/var/www/html/mod/$plugin_subdir" ;;
    block)  target="/var/www/html/blocks/$plugin_subdir" ;;
    theme)  target="/var/www/html/theme/$plugin_subdir" ;;
    local)  target="/var/www/html/local/$plugin_subdir" ;;
    report) target="/var/www/html/report/$plugin_subdir" ;;
    *)      echo "Tipo desconocido: $plugin_type" && exit 1 ;;
  esac

  if [ -d "$plugin_subdir" ]; then
    mv "$plugin_subdir" "$target"
  else
    echo "Error: el ZIP no contiene la carpeta esperada '$plugin_subdir'"
    exit 1
  fi
done

rm -rf /var/www/html/tmp_plugins
