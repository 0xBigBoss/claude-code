#!/usr/bin/env bash
# Sync Claude Code assets to Codex runtime directories.
# - Skills: claude-code/.claude/skills + plugin skills -> codex/.codex/skills
# - Commands: claude-code/commands/*.md -> codex/.codex/prompts/*.md

set -euo pipefail
shopt -s nullglob

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_SKILLS_DIR="$REPO_DIR/.claude/skills"
CLAUDE_COMMANDS_DIR="$REPO_DIR/commands"
PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"

# Options
DRY_RUN=false
VERBOSE=false
DO_SKILLS=true
DO_COMMANDS=true
PRUNE_SKILLS=true
PRUNE_COMMANDS=true

# Track synced entries for prune (Bash 3.2 compatible newline-delimited sets)
SYNCED_SKILLS=""
SYNCED_PROMPTS=""

mark_synced_skill() {
    local skill_name="$1"
    if ! is_synced_skill "$skill_name"; then
        SYNCED_SKILLS="${SYNCED_SKILLS}${skill_name}"$'\n'
    fi
}

is_synced_skill() {
    local skill_name="$1"
    printf '%s' "$SYNCED_SKILLS" | grep -Fxq -- "$skill_name"
}

mark_synced_prompt() {
    local prompt_name="$1"
    if ! is_synced_prompt "$prompt_name"; then
        SYNCED_PROMPTS="${SYNCED_PROMPTS}${prompt_name}"$'\n'
    fi
}

is_synced_prompt() {
    local prompt_name="$1"
    printf '%s' "$SYNCED_PROMPTS" | grep -Fxq -- "$prompt_name"
}

resolve_codex_dir() {
    if [[ -n "${DOTFILES_DIR:-}" && -d "$DOTFILES_DIR/codex/.codex" ]]; then
        echo "$DOTFILES_DIR/codex/.codex"
        return 0
    fi

    local repo_root
    repo_root="$(cd "$REPO_DIR/.." && pwd)"
    if [[ -d "$repo_root/codex/.codex" ]]; then
        echo "$repo_root/codex/.codex"
        return 0
    fi

    if [[ -d "$HOME/.codex" ]]; then
        echo "$HOME/.codex"
        return 0
    fi

    echo "Error: Unable to locate Codex directory." >&2
    echo "Set DOTFILES_DIR to your dotfiles repo root or create ~/.codex." >&2
    return 1
}

CODEX_DIR="$(resolve_codex_dir)"
CODEX_SKILLS_DIR="$CODEX_DIR/skills"
CODEX_PROMPTS_DIR="$CODEX_DIR/prompts"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Sync Claude Code assets to Codex.

Options:
    --skills                Sync skills only
    --commands              Sync commands/prompts only
    --no-prune-skills       Do not remove stale skills from target
    --no-prune-commands     Do not remove stale prompts from target
    -n, --dry-run           Show planned changes without writing
    -v, --verbose           Show detailed output
    -h, --help              Show this help message

Behavior:
    - If neither --skills nor --commands is given, both are synced.
    - Skills sync order is user skills first, then plugin skills (plugin wins on name collision).
    - Pruning skips hidden entries (e.g. .system).

Sources:
    Skills:
      - User:   $USER_SKILLS_DIR
      - Plugin: $PLUGINS_JSON
    Commands:
      - Claude commands: $CLAUDE_COMMANDS_DIR/*.md

Targets:
    Skills:   $CODEX_SKILLS_DIR
    Prompts:  $CODEX_PROMPTS_DIR
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

remove_path() {
    local path="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would remove: $path"
        return 0
    fi

    rm -rf "$path"
    info "Removed: $path"
}

copy_dir() {
    local src="$1"
    local dest="$2"
    local name
    name="$(basename "$src")"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would copy dir: $name"
        log "  from: $src"
        log "  to:   $dest"
        return 0
    fi

    rm -rf "$dest"
    cp -R "$src" "$dest"
    info "Copied: $name"
}

copy_file() {
    local src="$1"
    local dest="$2"
    local name
    name="$(basename "$src")"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would copy file: $name"
        log "  from: $src"
        log "  to:   $dest"
        return 0
    fi

    cp "$src" "$dest"
    info "Copied: $name"
}

is_skill_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    [[ -f "$dir/SKILL.md" || -f "$dir/skill.md" ]]
}

sync_user_skills() {
    info "=== Syncing user skills ==="

    if [[ ! -d "$USER_SKILLS_DIR" ]]; then
        info "No user skills directory found at $USER_SKILLS_DIR"
        return 0
    fi

    local count=0
    local skill_dir skill_name
    for skill_dir in "$USER_SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name="$(basename "$skill_dir")"

        [[ "$skill_name" == "node_modules" ]] && continue
        [[ "$skill_name" == .* ]] && continue

        copy_dir "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
        mark_synced_skill "$skill_name"
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
    local plugin_key install_path skill_dir skill_name

    while IFS= read -r plugin_key; do
        [[ -n "$plugin_key" ]] || continue
        log "Processing plugin: $plugin_key"

        install_path="$(jq -r ".plugins[\"$plugin_key\"][0].installPath // empty" "$PLUGINS_JSON")"
        if [[ -z "$install_path" || ! -d "$install_path" ]]; then
            log "  Install path not found or invalid: $install_path"
            continue
        fi

        log "  Install path: $install_path"

        if [[ -d "$install_path/skills" ]]; then
            log "  Found skills/ subdirectory"
            for skill_dir in "$install_path/skills"/*/; do
                [[ -d "$skill_dir" ]] || continue
                skill_name="$(basename "$skill_dir")"

                [[ "$skill_name" == .* ]] && continue

                if is_skill_dir "$skill_dir"; then
                    copy_dir "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
                    mark_synced_skill "$skill_name"
                    count=$((count + 1))
                else
                    log "  Skipping $skill_name (no SKILL.md)"
                fi
            done
        else
            log "  Looking for skills in root directory"
            for skill_dir in "$install_path"/*/; do
                [[ -d "$skill_dir" ]] || continue
                skill_name="$(basename "$skill_dir")"

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

                if is_skill_dir "$skill_dir"; then
                    copy_dir "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
                    mark_synced_skill "$skill_name"
                    count=$((count + 1))
                fi
            done
        fi
    done < <(jq -r '.plugins | keys[]?' "$PLUGINS_JSON")

    info "Plugin skills synced: $count"
}

prune_stale_skills() {
    [[ "$PRUNE_SKILLS" == "true" ]] || return 0

    info "=== Pruning stale skills ==="

    if [[ ! -d "$CODEX_SKILLS_DIR" ]]; then
        info "No skills directory found at $CODEX_SKILLS_DIR"
        return 0
    fi

    local count=0
    local skill_dir skill_name
    for skill_dir in "$CODEX_SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name="$(basename "$skill_dir")"

        [[ "$skill_name" == .* ]] && continue

        if ! is_synced_skill "$skill_name"; then
            remove_path "$skill_dir"
            count=$((count + 1))
        fi
    done

    info "Stale skills pruned: $count"
}

sync_commands() {
    info "=== Syncing commands to prompts ==="

    if [[ ! -d "$CLAUDE_COMMANDS_DIR" ]]; then
        info "No commands directory found at $CLAUDE_COMMANDS_DIR"
        return 0
    fi

    local count=0
    local cmd_file prompt_name
    for cmd_file in "$CLAUDE_COMMANDS_DIR"/*.md; do
        [[ -f "$cmd_file" ]] || continue
        prompt_name="$(basename "$cmd_file")"

        copy_file "$cmd_file" "$CODEX_PROMPTS_DIR/$prompt_name"
        mark_synced_prompt "${prompt_name%.md}"
        count=$((count + 1))
    done

    info "Commands synced: $count"
}

prune_stale_prompts() {
    [[ "$PRUNE_COMMANDS" == "true" ]] || return 0

    info "=== Pruning stale prompts ==="

    if [[ ! -d "$CODEX_PROMPTS_DIR" ]]; then
        info "No prompts directory found at $CODEX_PROMPTS_DIR"
        return 0
    fi

    local count=0
    local prompt_file prompt_name
    for prompt_file in "$CODEX_PROMPTS_DIR"/*.md; do
        [[ -f "$prompt_file" ]] || continue
        prompt_name="$(basename "$prompt_file" .md)"

        if ! is_synced_prompt "$prompt_name"; then
            remove_path "$prompt_file"
            count=$((count + 1))
        fi
    done

    info "Stale prompts pruned: $count"
}

main() {
    local explicit_scope=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skills)
                if [[ "$explicit_scope" == "false" ]]; then
                    DO_SKILLS=false
                    DO_COMMANDS=false
                    explicit_scope=true
                fi
                DO_SKILLS=true
                shift
                ;;
            --commands)
                if [[ "$explicit_scope" == "false" ]]; then
                    DO_SKILLS=false
                    DO_COMMANDS=false
                    explicit_scope=true
                fi
                DO_COMMANDS=true
                shift
                ;;
            --no-prune-skills)
                PRUNE_SKILLS=false
                shift
                ;;
            --no-prune-commands)
                PRUNE_COMMANDS=false
                shift
                ;;
            --prune-skills)
                PRUNE_SKILLS=true
                shift
                ;;
            --prune-commands)
                PRUNE_COMMANDS=true
                shift
                ;;
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

    if [[ "$DRY_RUN" == "false" ]]; then
        [[ "$DO_SKILLS" == "false" ]] || mkdir -p "$CODEX_SKILLS_DIR"
        [[ "$DO_COMMANDS" == "false" ]] || mkdir -p "$CODEX_PROMPTS_DIR"
    fi

    info "Syncing Claude Code assets to Codex..."
    info "  Codex dir: $CODEX_DIR"
    info "  Skills:    $DO_SKILLS (prune=$PRUNE_SKILLS)"
    info "  Commands:  $DO_COMMANDS (prune=$PRUNE_COMMANDS)"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "  Mode:      dry-run"
    fi
    echo

    if [[ "$DO_SKILLS" == "true" ]]; then
        sync_user_skills
        echo
        sync_plugin_skills
        echo
        prune_stale_skills
        echo
    fi

    if [[ "$DO_COMMANDS" == "true" ]]; then
        sync_commands
        echo
        prune_stale_prompts
        echo
    fi

    info "Done!"
}

main "$@"
