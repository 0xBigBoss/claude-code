#!/usr/bin/env bash
# check-plugin-versions.sh — Verify plugin.json and marketplace.json versions are in sync.
# Optionally accepts a file list (from lefthook) to warn about missing version bumps.
#
# Usage:
#   check-plugin-versions.sh [changed-file ...]
#
# Exit codes:
#   0  All versions consistent
#   1  Version mismatch or missing version bump detected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKETPLACE="$CLAUDE_CODE_DIR/.claude-plugin/marketplace.json"

if [[ ! -f "$MARKETPLACE" ]]; then
  echo "error: marketplace.json not found at $MARKETPLACE" >&2
  exit 1
fi

errors=0

# --- Check 1: Version consistency between marketplace.json and each plugin.json ---

plugin_count=$(jq '.plugins | length' "$MARKETPLACE")

for ((i = 0; i < plugin_count; i++)); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE")
  marketplace_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE")

  plugin_json="$CLAUDE_CODE_DIR/$source/.claude-plugin/plugin.json"

  if [[ ! -f "$plugin_json" ]]; then
    echo "error: plugin.json not found for '$name' at $plugin_json" >&2
    errors=$((errors + 1))
    continue
  fi

  plugin_version=$(jq -r '.version' "$plugin_json")

  if [[ "$marketplace_version" != "$plugin_version" ]]; then
    echo "error: version mismatch for '$name'" >&2
    echo "  marketplace.json: $marketplace_version" >&2
    echo "  plugin.json:      $plugin_version" >&2
    errors=$((errors + 1))
  fi
done

# --- Check 2: Changed plugin source files without a plugin.json bump ---

if [[ $# -gt 0 ]]; then
  for ((i = 0; i < plugin_count; i++)); do
    name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
    source=$(jq -r ".plugins[$i].source" "$MARKETPLACE")
    source_prefix="${source#./}"

    has_source_change=false
    has_plugin_json_change=false

    for file in "$@"; do
      if [[ "$file" == *"$source_prefix"* ]]; then
        has_source_change=true
        if [[ "$file" == *"$source_prefix/.claude-plugin/plugin.json" ]]; then
          has_plugin_json_change=true
        fi
      fi
    done

    if $has_source_change && ! $has_plugin_json_change; then
      echo "warning: plugin '$name' has source changes but plugin.json version was not bumped" >&2
      errors=$((errors + 1))
    fi
  done
fi

if [[ $errors -gt 0 ]]; then
  echo "" >&2
  echo "Plugin version check failed. Update versions in both:" >&2
  echo "  1. claude-code/plugins/<name>/.claude-plugin/plugin.json" >&2
  echo "  2. claude-code/.claude-plugin/marketplace.json" >&2
  echo "Then run: claude plugin marketplace update 0xbigboss-plugins" >&2
  exit 1
fi
