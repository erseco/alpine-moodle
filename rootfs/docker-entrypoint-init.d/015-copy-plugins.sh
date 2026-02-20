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
     mod) target="/var/www/html/mod/$plugin_subdir" ;;
    block) target="/var/www/html/blocks/$plugin_subdir" ;;
    theme) target="/var/www/html/theme/$plugin_subdir" ;;
    local) target="/var/www/html/local/$plugin_subdir" ;;
    report) target="/var/www/html/report/$plugin_subdir" ;;
    auth) target="/var/www/html/auth/$plugin_subdir" ;;
    filter) target="/var/www/html/filter/$plugin_subdir" ;;
    gradeexport) target="/var/www/html/grade/export/$plugin_subdir" ;;
    gradeimport) target="/var/www/html/grade/import/$plugin_subdir" ;;
    gradereport) target="/var/www/html/grade/report/$plugin_subdir" ;;
    message) target="/var/www/html/message/output/$plugin_subdir" ;;
    tool) target="/var/www/html/admin/tool/$plugin_subdir" ;;
    profilefield) target="/var/www/html/user/profile/field/$plugin_subdir" ;;
    quiz) target="/var/www/html/mod/quiz/report/$plugin_subdir" ;;
    plagiarism) target="/var/www/html/plagiarism/$plugin_subdir" ;;
    portfolio) target="/var/www/html/portfolio/$plugin_subdir" ;;
    repository) target="/var/www/html/repository/$plugin_subdir" ;;
    search) target="/var/www/html/search/$plugin_subdir" ;;
    reportbuilder) target="/var/www/html/reportbuilder/source/$plugin_subdir" ;;
    payment) target="/var/www/html/payment/gateway/$plugin_subdir" ;;
    enrol) target="/var/www/html/enrol/$plugin_subdir" ;;
    assignfeedback) target="/var/www/html/mod/assign/feedback/$plugin_subdir" ;;
    assignsubmission) target="/var/www/html/mod/assign/submission/$plugin_subdir" ;;
    quizaccess) target="/var/www/html/mod/quiz/accessrule/$plugin_subdir" ;;
    workshopallocation) target="/var/www/html/mod/workshop/allocation/$plugin_subdir" ;;
    workshopassessment) target="/var/www/html/mod/workshop/assessment/$plugin_subdir" ;;
    workshopform) target="/var/www/html/mod/workshop/form/$plugin_subdir" ;;
    question) target="/var/www/html/question/type/$plugin_subdir" ;;
    qbehaviour) target="/var/www/html/question/behaviour/$plugin_subdir" ;;
    qformat) target="/var/www/html/question/format/$plugin_subdir" ;;
    editor) target="/var/www/html/lib/editor/$plugin_subdir" ;;
    tiny) target="/var/www/html/lib/editor/tiny/plugins/$plugin_subdir" ;;
    atto) target="/var/www/html/lib/editor/atto/plugins/$plugin_subdir" ;;
    tinymce) target="/var/www/html/lib/editor/tinymce/plugins/$plugin_subdir" ;;
    availability) target="/var/www/html/availability/condition/$plugin_subdir" ;;
    datafield) target="/var/www/html/mod/data/field/$plugin_subdir" ;;
    dataprocessor) target="/var/www/html/mod/data/preset/$plugin_subdir" ;;
    scormreport) target="/var/www/html/mod/scorm/report/$plugin_subdir" ;;
    lti) target="/var/www/html/mod/lti/source/$plugin_subdir" ;;
    contenttype) target="/var/www/html/contentbank/contenttype/$plugin_subdir" ;;
    courseformat) target="/var/www/html/course/format/$plugin_subdir" ;;
    customfield) target="/var/www/html/customfield/field/$plugin_subdir" ;;
    paymentgateway) target="/var/www/html/payment/gateway/$plugin_subdir" ;;
    analytics) target="/var/www/html/analytics/indicator/$plugin_subdir" ;;
    aiprovider) target="/var/www/html/ai/provider/$plugin_subdir" ;;
    aiplacement) target="/var/www/html/ai/placement/$plugin_subdir" ;;
    cachelock) target="/var/www/html/cache/lock/$plugin_subdir" ;;
    cachestore) target="/var/www/html/cache/stores/$plugin_subdir" ;;
    coresearch) target="/var/www/html/search/engine/$plugin_subdir" ;;
    localcache) target="/var/www/html/local/cache/$plugin_subdir" ;;
    logstore) target="/var/www/html/admin/tool/log/store/$plugin_subdir" ;;
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
