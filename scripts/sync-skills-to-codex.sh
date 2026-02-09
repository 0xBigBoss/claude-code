#!/usr/bin/env bash
# Backward-compatible wrapper for skill-only sync.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/sync-codex.sh" --skills "$@"
