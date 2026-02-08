#!/usr/bin/env bash
# Sync Claude skills into Codex skills with deterministic precedence.
# Precedence: plugin skills first, user skills override on name collision.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_SKILLS_DIR="$REPO_DIR/.claude/skills"
PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
MANIFEST_NAME=".dotfiles-skill-sync-manifest.txt"

DRY_RUN=false
VERBOSE=false
CHECK_MODE=false
PRUNE=false
DRIFT_FOUND=false
ERROR_FOUND=false

TMP_DIR=""
CANDIDATES_FILE=""
SORTED_FILE=""
WINNERS_FILE=""
COLLISIONS_FILE=""
DESIRED_SKILLS_FILE=""
CODEX_SKILLS_DIR=""
MANIFEST_PATH=""

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

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Sync Claude skills to the Codex skills directory.

Options:
  -n, --dry-run   Show what would change without changing files
  -v, --verbose   Print detailed diagnostics
      --check     Non-mutating drift check (exit 0 clean, 2 drift, 1 error)
      --prune     Remove stale skills listed in sync manifest
  -h, --help      Show this help
EOF
}

info() {
    echo "$@"
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$@"
    fi
}

warn() {
    echo "[WARN] $@" >&2
}

err() {
    echo "[ERROR] $@" >&2
    ERROR_FOUND=true
}

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

contains_line() {
    local file="$1"
    local needle="$2"
    [[ -f "$file" ]] || return 1
    grep -Fxq -- "$needle" "$file"
}

is_protected_skill() {
    local skill="$1"
    [[ "$skill" == ".system" ]]
}

append_candidate() {
    local priority="$1"
    local skill_name="$2"
    local source_dir="$3"
    local origin="$4"

    [[ -d "$source_dir" ]] || return 0

    if [[ "$skill_name" == .* ]] || [[ "$skill_name" == "node_modules" ]]; then
        return 0
    fi

    if is_protected_skill "$skill_name"; then
        log "Skipping protected skill name: $skill_name"
        return 0
    fi

    if [[ ! -f "$source_dir/SKILL.md" && ! -f "$source_dir/skill.md" ]]; then
        log "Skipping $skill_name from $origin (missing SKILL.md)"
        return 0
    fi

    printf '%s\t%s\t%s\t%s\n' "$priority" "$skill_name" "$source_dir" "$origin" >> "$CANDIDATES_FILE"
}

collect_user_skills() {
    info "=== Discovering user skills ==="
    if [[ ! -d "$USER_SKILLS_DIR" ]]; then
        info "No user skills found at $USER_SKILLS_DIR"
        return 0
    fi

    local count=0
    local skill_dir
    while IFS= read -r skill_dir; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        append_candidate "200" "$skill_name" "$skill_dir" "user"
        count=$((count + 1))
    done < <(find "$USER_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

    info "User skill directories scanned: $count"
}

collect_plugin_skills() {
    info "=== Discovering plugin skills ==="

    if [[ ! -f "$PLUGINS_JSON" ]]; then
        info "No plugin registry found at $PLUGINS_JSON"
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found; skipping plugin skill discovery"
        return 0
    fi

    local plugin_count=0
    local plugin_key
    while IFS= read -r plugin_key; do
        [[ -n "$plugin_key" ]] || continue
        plugin_count=$((plugin_count + 1))

        local install_path
        install_path="$(jq -r ".plugins[\"$plugin_key\"][0].installPath // empty" "$PLUGINS_JSON")"
        if [[ -z "$install_path" || ! -d "$install_path" ]]; then
            log "Skipping plugin $plugin_key (invalid installPath: $install_path)"
            continue
        fi

        log "Scanning plugin $plugin_key at $install_path"

        if [[ -d "$install_path/skills" ]]; then
            local skill_dir
            while IFS= read -r skill_dir; do
                [[ -d "$skill_dir" ]] || continue
                local skill_name
                skill_name="$(basename "$skill_dir")"
                append_candidate "100" "$skill_name" "$skill_dir" "plugin:$plugin_key"
            done < <(find "$install_path/skills" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
            continue
        fi

        # Fallback for plugins exposing skills at root.
        local root_skill_dir
        while IFS= read -r root_skill_dir; do
            [[ -d "$root_skill_dir" ]] || continue
            local root_skill_name
            root_skill_name="$(basename "$root_skill_dir")"
            case "$root_skill_name" in
                node_modules|.claude|.claude-plugin|.github|.git|src|npm|scripts)
                    continue
                    ;;
            esac
            append_candidate "100" "$root_skill_name" "$root_skill_dir" "plugin:$plugin_key"
        done < <(find "$install_path" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
    done < <(jq -r '.plugins | keys[]' "$PLUGINS_JSON" | LC_ALL=C sort)

    info "Plugins scanned: $plugin_count"
}

select_winners() {
    if [[ ! -s "$CANDIDATES_FILE" ]]; then
        : > "$SORTED_FILE"
        : > "$WINNERS_FILE"
        : > "$COLLISIONS_FILE"
        : > "$DESIRED_SKILLS_FILE"
        info "No skills discovered from user/plugins; nothing to sync"
        return 0
    fi

    sort -t $'\t' -k2,2 -k1,1n -k4,4 "$CANDIDATES_FILE" > "$SORTED_FILE"

    # Last candidate per skill wins (user priority 200 overrides plugin priority 100).
    awk -F'\t' '
        { selected[$2] = $0 }
        END { for (skill in selected) print selected[skill] }
    ' "$SORTED_FILE" | sort -t $'\t' -k2,2 > "$WINNERS_FILE"

    awk -F'\t' '
        {
            count[$2]++
            seen[$2] = seen[$2] (seen[$2] == "" ? "" : "; ") $4 " (priority " $1 ")"
        }
        END {
            for (skill in count) {
                if (count[skill] > 1) {
                    print skill "\t" count[skill] "\t" seen[skill]
                }
            }
        }
    ' "$SORTED_FILE" | sort -t $'\t' -k1,1 > "$COLLISIONS_FILE"

    cut -f2 "$WINNERS_FILE" > "$DESIRED_SKILLS_FILE"

    if [[ -s "$COLLISIONS_FILE" ]]; then
        info "Detected skill name collisions:"
        while IFS=$'\t' read -r skill_name collision_count sources; do
            local winner_origin
            winner_origin="$(awk -F'\t' -v skill="$skill_name" '$2 == skill { print $4 }' "$WINNERS_FILE")"
            info "  - $skill_name ($collision_count candidates) -> winner: $winner_origin"
            log "      candidates: $sources"
        done < "$COLLISIONS_FILE"
    fi
}

check_drift_for_skill() {
    local skill_name="$1"
    local source_dir="$2"
    local target_dir="$3"

    if [[ ! -d "$target_dir" ]]; then
        info "[DRIFT] Missing skill: $skill_name"
        DRIFT_FOUND=true
        return 0
    fi

    if ! diff -qr "$source_dir" "$target_dir" >/dev/null 2>&1; then
        info "[DRIFT] Skill differs: $skill_name"
        DRIFT_FOUND=true
        return 0
    fi

    log "[OK] Skill in sync: $skill_name"
}

write_manifest() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[dry-run] Would write manifest: $MANIFEST_PATH"
        return 0
    fi

    cp "$DESIRED_SKILLS_FILE" "$MANIFEST_PATH"
    info "Updated sync manifest: $MANIFEST_PATH"
}

prune_from_manifest() {
    if [[ "$PRUNE" != "true" ]]; then
        return 0
    fi

    if [[ ! -f "$MANIFEST_PATH" ]]; then
        warn "Prune requested, but no manifest exists at $MANIFEST_PATH (skipping prune)"
        return 0
    fi

    local pruned=0
    local skill_name
    while IFS= read -r skill_name || [[ -n "$skill_name" ]]; do
        [[ -n "$skill_name" ]] || continue
        if contains_line "$DESIRED_SKILLS_FILE" "$skill_name"; then
            continue
        fi
        if is_protected_skill "$skill_name"; then
            continue
        fi
        local target_dir="$CODEX_SKILLS_DIR/$skill_name"
        if [[ ! -e "$target_dir" && ! -L "$target_dir" ]]; then
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[dry-run] Would prune stale skill: $skill_name"
        else
            rm -rf "$target_dir"
            info "Pruned stale skill: $skill_name"
        fi
        pruned=$((pruned + 1))
    done < "$MANIFEST_PATH"

    info "Prune complete: $pruned stale skill(s)"
}

apply_sync() {
    info "=== Applying skill sync ==="

    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$CODEX_SKILLS_DIR"
    fi

    local copied=0
    while IFS=$'\t' read -r _priority skill_name source_dir _origin; do
        [[ -n "$skill_name" ]] || continue
        local target_dir="$CODEX_SKILLS_DIR/$skill_name"
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[dry-run] Would sync skill: $skill_name"
            log "  from: $source_dir"
            log "  to:   $target_dir"
        else
            rm -rf "$target_dir"
            cp -R "$source_dir" "$target_dir"
            info "Synced skill: $skill_name"
        fi
        copied=$((copied + 1))
    done < "$WINNERS_FILE"

    prune_from_manifest
    write_manifest
    info "Skills synced: $copied"
}

check_sync() {
    info "=== Checking skill sync drift ==="

    local skill_name source_dir target_dir
    while IFS=$'\t' read -r _priority skill_name source_dir _origin; do
        [[ -n "$skill_name" ]] || continue
        target_dir="$CODEX_SKILLS_DIR/$skill_name"
        check_drift_for_skill "$skill_name" "$source_dir" "$target_dir"
    done < "$WINNERS_FILE"

    if [[ -f "$MANIFEST_PATH" ]]; then
        while IFS= read -r skill_name || [[ -n "$skill_name" ]]; do
            [[ -n "$skill_name" ]] || continue
            if contains_line "$DESIRED_SKILLS_FILE" "$skill_name"; then
                continue
            fi
            if is_protected_skill "$skill_name"; then
                continue
            fi
            info "[DRIFT] Stale managed skill listed in manifest: $skill_name"
            DRIFT_FOUND=true
        done < "$MANIFEST_PATH"
    else
        info "[INFO] Sync manifest not found at $MANIFEST_PATH (stale-skill detection skipped)"
    fi
}

main() {
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
            --check)
                CHECK_MODE=true
                shift
                ;;
            --prune)
                PRUNE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    CODEX_SKILLS_DIR="$(resolve_codex_skills_dir)" || exit 1
    MANIFEST_PATH="$CODEX_SKILLS_DIR/$MANIFEST_NAME"

    TMP_DIR="$(mktemp -d)"
    trap cleanup EXIT
    CANDIDATES_FILE="$TMP_DIR/candidates.tsv"
    SORTED_FILE="$TMP_DIR/sorted.tsv"
    WINNERS_FILE="$TMP_DIR/winners.tsv"
    COLLISIONS_FILE="$TMP_DIR/collisions.tsv"
    DESIRED_SKILLS_FILE="$TMP_DIR/desired_skills.txt"
    : > "$CANDIDATES_FILE"

    info "Codex skills dir: $CODEX_SKILLS_DIR"
    collect_user_skills
    collect_plugin_skills
    select_winners

    if [[ "$ERROR_FOUND" == "true" ]]; then
        exit 1
    fi

    if [[ "$CHECK_MODE" == "true" ]]; then
        check_sync
    else
        apply_sync
    fi

    if [[ "$ERROR_FOUND" == "true" ]]; then
        exit 1
    fi

    if [[ "$DRIFT_FOUND" == "true" ]]; then
        exit 2
    fi

    info "Done."
}

main "$@"
