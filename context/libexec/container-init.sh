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

# -- Git config -------------------------------------------------------
# In a dev container, VS Code injects its own .gitconfig (host credentials,
# signing config, etc). Only install our default when not in that context.
if [ -z "${DEVCONTAINER:-}" ] && [ ! -f "$HOME/.gitconfig" ]; then
    cp /etc/skel/.gitconfig "$HOME/.gitconfig"
fi

# -- Claude Code default settings -------------------------------------
if [ ! -f "$HOME/.claude/settings.json" ]; then
    cp /etc/skel/.claude/settings.json "$HOME/.claude/settings.json"
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
