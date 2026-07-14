#!/bin/bash
set -euo pipefail

# -- This script runs as coder ----------------------------------------
# If any step fails, the container dies - there is no state where
# Claude Code runs without a working firewall.
#
# Exception: in Codespaces, the firewall is skipped entirely because the
# standard ruleset blocks Codespaces' internal communication, causing
# the container to hang. A Codespaces-specific ruleset may be possible
# (see TODO.md).

# -- Logging helpers (color on tty, plain text otherwise) -------------
_log() {
    local color="$1" label="$2"; shift 2
    if [ -t 2 ]; then
        echo -e "\033[${color}m${label}:\033[0m $*" >&2
    else
        echo "${label}: $*" >&2
    fi
}
log_info()  { _log "1;32" "INFO"    "$@"; }
log_warn()  { _log "1;33" "WARNING" "$@"; }
log_error() { _log "1;31" "ERROR"   "$@"; }

# -- Detect Codespaces ------------------------------------------------
is_codespaces() {
    [ "${CODESPACES:-}" = "true" ]
}

# -- Firewall setup ---------------------------------------------------
if is_codespaces; then
    log_warn "Codespaces detected — skipping firewall (network access will be unrestricted)"
else
    sudo /usr/local/libexec/init-firewall.sh
fi

# -- Seed default config from /etc/skel -------------------------------
# Copy any missing skel file into $HOME, preserving modes (so the
# statusline script keeps its exec bit). This is volume-agnostic: it
# does not need to know which paths are volume mounts — whatever a fresh
# mount leaves empty gets seeded, while existing files are left untouched
# so user edits are never overwritten.
#
# Exception: in a dev container, VS Code injects its own .gitconfig (host
# credentials, signing config, etc), so never install our default there.
while IFS= read -r -d '' src; do
    rel=${src#/etc/skel/}
    dest="$HOME/$rel"
    if [ "$rel" = ".gitconfig" ] && [ -n "${DEVCONTAINER:-}" ]; then
        continue
    fi
    [ -e "$dest" ] && continue
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
done < <(find /etc/skel -type f -print0)

# -- Reconcile settings.json with updated skel defaults ---------------
# The seed loop only fills MISSING files, so an existing volume never picks up
# changed or added skel defaults. Three-way merge the live file against the
# current defaults, using a baseline (the skel defaults as of the last sync,
# stored in the volume): adopt new/changed defaults where the user has not
# diverged, always keep genuine user edits. Fail closed — on any invalid JSON
# or jq error, leave the user's file untouched.
SKEL_SETTINGS=/etc/skel/.claude/settings.json
LIVE_SETTINGS="$HOME/.claude/settings.json"
BASELINE="$HOME/.claude/.settings-baseline.json"
# shellcheck disable=SC2016  # jq program: $b/$n/$c/$k are jq vars, not shell
M3='
def m3($b; $n; $c):
  reduce ([$b, $n, $c] | add | keys_unsorted[]) as $k ({};
    if ($b[$k]|type) == "object" and ($n[$k]|type) == "object" and ($c[$k]|type) == "object"
    then .[$k] = m3($b[$k]; $n[$k]; $c[$k])
    elif (($c|has($k)) == ($b|has($k))) and $c[$k] == $b[$k]
    then if ($n|has($k)) then .[$k] = $n[$k] else . end
    else if ($c|has($k)) then .[$k] = $c[$k] else . end
    end);
m3(($b[0] // {}); ($n[0] // {}); ($c[0] // {}))
'
if [ -f "$SKEL_SETTINGS" ] && [ -f "$LIVE_SETTINGS" ]; then
    base_tmp=$(mktemp "$HOME/.claude/.settings-base.XXXXXX")
    if [ -f "$BASELINE" ]; then
        cp "$BASELINE" "$base_tmp"
    else
        echo '{}' > "$base_tmp"          # first run: no baseline yet
    fi
    # Skip unless the defaults actually changed since the last sync.
    if ! cmp -s "$SKEL_SETTINGS" "$base_tmp"; then
        merged_tmp=$(mktemp "$HOME/.claude/.settings-merge.XXXXXX")
        if jq -n --slurpfile b "$base_tmp" --slurpfile n "$SKEL_SETTINGS" \
                --slurpfile c "$LIVE_SETTINGS" "$M3" > "$merged_tmp" 2>/dev/null \
           && [ -s "$merged_tmp" ]; then
            mv "$merged_tmp" "$LIVE_SETTINGS"   # atomic (same dir); merged first,
            cp "$SKEL_SETTINGS" "$BASELINE"     # then advance the baseline
            log_info "settings.json reconciled with updated defaults"
        else
            log_warn "settings merge failed; leaving settings.json untouched"
            rm -f "$merged_tmp"
        fi
    fi
    rm -f "$base_tmp"
fi

# -- Java version selection -------------------------------------------
JAVA_VERSION_FILE="/workspaces/project/.java-version"
if [ -f "$JAVA_VERSION_FILE" ]; then
    JAVA_MAJOR=$(tr -d '[:space:]' < "$JAVA_VERSION_FILE")
    set +u
    BEST=$(sdk list java | grep '| installed' | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-[a-z]+" | grep "^${JAVA_MAJOR}\." | sort -V | tail -1 || true)
    if [ -n "$BEST" ]; then
        sdk default java "$BEST" > /dev/null
    else
        log_warn "Java $JAVA_MAJOR requested in .java-version but not installed; using image default"
    fi
    set -u
fi

# -- Memory sync symlink (Claude only) ---------------------------------
# Skip when ~/.claude is not a volume mount (e.g. when running codex)
if mountpoint -q "$HOME/.claude" 2>/dev/null; then
    MEMORY_SYNC="/workspaces/project/.claude/memory-sync"
    MEMORY_DIR="/home/coder/.claude/projects/-workspaces-project/memory"

    if [ -d "$MEMORY_SYNC" ]; then
        if [ -L "$MEMORY_DIR" ]; then
            : # already set up
        elif [ -d "$MEMORY_DIR" ] && [ -n "$(ls -A "$MEMORY_DIR")" ]; then
            log_warn "both $MEMORY_DIR and $MEMORY_SYNC exist; skipping symlink"
            log_warn "  run claudebox-memory-init to resolve"
        else
            mkdir -p "$(dirname "$MEMORY_DIR")"
            [ -d "$MEMORY_DIR" ] && rmdir "$MEMORY_DIR"
            ln -s "$MEMORY_SYNC" "$MEMORY_DIR"
            log_info "memory sync enabled via symlink"
        fi
    else
        log_info "memory sync not configured; run claudebox-memory-init to enable"
    fi
fi
