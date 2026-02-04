#!/usr/bin/env bash
#
# Claude Code configuration installer
# Creates direct symlinks from ~/.claude/ to this repository
#
# Usage:
#   ./install.sh           # Install symlinks
#   ./install.sh --check   # Check status without changes
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ONLY=false

[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

print_info() { echo "[INFO] $1"; }
print_warn() { echo "[WARN] $1"; }
print_ok()   { echo "[OK] $1"; }

# Create symlink idempotently
# Args: $1=target (source file in repo), $2=link path (destination)
ensure_symlink() {
    local target="$1"
    local link="$2"
    local link_name
    link_name="$(basename "$link")"

    if [[ ! -e "$target" ]]; then
        print_warn "$link_name: target does not exist: $target"
        return 1
    fi

    if [[ -L "$link" ]]; then
        local current
        current="$(readlink "$link")"

        local resolved_target
        local resolved_link
        resolved_target="$(python3 -c "import os; print(os.path.realpath('${target}'))" 2>/dev/null || true)"
        resolved_link="$(python3 -c "import os; print(os.path.realpath('${link}'))" 2>/dev/null || true)"

        if [[ "$current" == "$target" || ( -n "$resolved_target" && -n "$resolved_link" && "$resolved_target" == "$resolved_link" ) ]]; then
            print_ok "$link_name: symlink correct"
            return 0
        else
            if [[ "$CHECK_ONLY" == true ]]; then
                print_warn "$link_name: symlink points to wrong target: $current"
                return 1
            fi
            print_info "$link_name: updating symlink..."
            rm "$link"
            ln -s "$target" "$link"
            print_ok "$link_name: symlink updated"
        fi
    elif [[ -e "$link" ]]; then
        if [[ "$CHECK_ONLY" == true ]]; then
            print_warn "$link_name: regular file exists (not a symlink)"
            return 1
        fi
        local backup="${link}.backup.$(date +%Y%m%d%H%M%S)"
        print_warn "$link_name: backing up regular file to $backup"
        mv "$link" "$backup"
        ln -s "$target" "$link"
        print_ok "$link_name: symlink created (old file backed up)"
    else
        if [[ "$CHECK_ONLY" == true ]]; then
            print_warn "$link_name: does not exist"
            return 1
        fi
        ln -s "$target" "$link"
        print_ok "$link_name: symlink created"
    fi
}

main() {
    echo "Claude Code install.sh"
    echo "Repository: $SCRIPT_DIR"
    echo ""

    # Ensure ~/.claude exists
    mkdir -p "$HOME/.claude"

    # CLAUDE.md - user-level instructions (open-source, editable)
    ensure_symlink "$SCRIPT_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

    # codex.json - centralized Codex CLI configuration for all plugins
    ensure_symlink "$SCRIPT_DIR/../codex/codex.json" "$HOME/.claude/codex.json"

    echo ""
    if [[ "$CHECK_ONLY" == true ]]; then
        echo "Check complete. Run without --check to apply changes."
    else
        echo "Done."
    fi
}

main "$@"
