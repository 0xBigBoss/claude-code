#!/usr/bin/env bash
# Sync Claude Code skills to Codex skills directory
# Copies user-level skills and discovers plugin/marketplace skills

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_SKILLS_DIR="$REPO_DIR/.claude/skills"
PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"

# Options
DRY_RUN=false
VERBOSE=false

resolve_codex_skills_dir() {
    if [[ -n "${DOTFILES_DIR:-}" && -d "$DOTFILES_DIR/codex/.codex/skills" ]]; then
        echo "$DOTFILES_DIR/codex/.codex/skills"
        return 0
    fi

    local repo_root
    repo_root="$(cd "$REPO_DIR/.." && pwd)"
    if [[ -d "$repo_root/codex/.codex/skills" ]]; then
        echo "$repo_root/codex/.codex/skills"
        return 0
    fi

    if [[ -d "$HOME/.codex/skills" ]]; then
        echo "$HOME/.codex/skills"
        return 0
    fi

    if [[ -d "$HOME/.codex" ]]; then
        echo "$HOME/.codex/skills"
        return 0
    fi

    echo "Error: Unable to locate Codex skills directory." >&2
    echo "Set DOTFILES_DIR to your dotfiles repo root or create ~/.codex/skills." >&2
    return 1
}

CODEX_SKILLS_DIR="$(resolve_codex_skills_dir)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Sync Claude Code skills to Codex skills directory.

Options:
    -n, --dry-run    Show what would be copied without copying
    -v, --verbose    Show detailed output
    -h, --help       Show this help message

Sources:
    - User skills from: $USER_SKILLS_DIR
    - Plugin skills from: ~/.claude/plugins/installed_plugins.json

Target:
    $CODEX_SKILLS_DIR
EOF
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$@"
    fi
}

info() {
    echo "$@"
}

copy_skill() {
    local src="$1"
    local dest="$2"
    local skill_name
    skill_name="$(basename "$src")"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would copy: $skill_name"
        log "  from: $src"
        log "  to:   $dest"
    else
        log "Copying: $skill_name"
        log "  from: $src"
        log "  to:   $dest"
        rm -rf "$dest"
        cp -R "$src" "$dest"
        info "Copied: $skill_name"
    fi
}

sync_user_skills() {
    info "=== Syncing user skills ==="

    if [[ ! -d "$USER_SKILLS_DIR" ]]; then
        info "No user skills directory found at $USER_SKILLS_DIR"
        return 0
    fi

    local count=0
    for skill_dir in "$USER_SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"

        # Skip node_modules and hidden directories
        [[ "$skill_name" == "node_modules" ]] && continue
        [[ "$skill_name" == .* ]] && continue

        copy_skill "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
        count=$((count + 1))
    done

    info "User skills synced: $count"
}

sync_plugin_skills() {
    info "=== Syncing plugin skills ==="

    if [[ ! -f "$PLUGINS_JSON" ]]; then
        info "No installed plugins found at $PLUGINS_JSON"
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed" >&2
        echo "Install with: brew install jq" >&2
        return 1
    fi

    local count=0

    # Parse each plugin from installed_plugins.json
    local plugin_names
    plugin_names=$(jq -r '.plugins | keys[]' "$PLUGINS_JSON")

    for plugin_key in $plugin_names; do
        log "Processing plugin: $plugin_key"

        # Get the install path for the first (active) installation
        local install_path
        install_path=$(jq -r ".plugins[\"$plugin_key\"][0].installPath // empty" "$PLUGINS_JSON")

        if [[ -z "$install_path" ]] || [[ ! -d "$install_path" ]]; then
            log "  Install path not found or invalid: $install_path"
            continue
        fi

        log "  Install path: $install_path"

        # Check for skills in <installPath>/skills/ subdirectory first
        if [[ -d "$install_path/skills" ]]; then
            log "  Found skills/ subdirectory"
            for skill_dir in "$install_path/skills"/*/; do
                [[ -d "$skill_dir" ]] || continue
                local skill_name
                skill_name="$(basename "$skill_dir")"

                # Skip hidden directories
                [[ "$skill_name" == .* ]] && continue

                # Verify it contains SKILL.md
                if [[ -f "$skill_dir/SKILL.md" ]] || [[ -f "$skill_dir/skill.md" ]]; then
                    copy_skill "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
                    count=$((count + 1))
                else
                    log "  Skipping $skill_name (no SKILL.md)"
                fi
            done
        else
            # Look for skill directories directly in installPath
            log "  Looking for skills in root directory"
            for skill_dir in "$install_path"/*/; do
                [[ -d "$skill_dir" ]] || continue
                local skill_name
                skill_name="$(basename "$skill_dir")"

                # Skip common non-skill directories
                [[ "$skill_name" == "node_modules" ]] && continue
                [[ "$skill_name" == ".claude" ]] && continue
                [[ "$skill_name" == ".claude-plugin" ]] && continue
                [[ "$skill_name" == ".github" ]] && continue
                [[ "$skill_name" == ".git" ]] && continue
                [[ "$skill_name" == "src" ]] && continue
                [[ "$skill_name" == "npm" ]] && continue
                [[ "$skill_name" == "scripts" ]] && continue
                [[ "$skill_name" == "plugins" ]] && continue
                [[ "$skill_name" == .* ]] && continue

                # Check if it contains SKILL.md (indicating it's a skill)
                if [[ -f "$skill_dir/SKILL.md" ]] || [[ -f "$skill_dir/skill.md" ]]; then
                    copy_skill "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
                    count=$((count + 1))
                fi
            done
        fi
    done

    info "Plugin skills synced: $count"
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Ensure target directory exists
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$CODEX_SKILLS_DIR"
    fi

    info "Syncing Claude Code skills to Codex..."
    if [[ "$DRY_RUN" == "true" ]]; then
        info "(dry-run mode - no changes will be made)"
    fi
    echo

    sync_user_skills
    echo

    sync_plugin_skills
    echo

    info "Done!"
}

main "$@"
