#!/bin/bash
set -euo pipefail

# -- This script runs as coder ----------------------------------------
# If any step fails, the container dies - there is no state where
# Claude Code runs without a working firewall.
#
# Exception: in Codespaces, the firewall is skipped entirely. Codespaces
# does not reliably block NET_ADMIN, so if the capability is silently
# granted, iptables would succeed and block internal communication
# (causing a hang). The firewall is unnecessary in Codespaces anyway —
# there's no local LAN, Docker host, or metadata endpoint to protect.

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
# CODESPACES env var is the canonical check, but during docker start it
# may not be injected yet (devcontainer CLI injects it later). We also
# check for the /workspaces/.codespaces directory as a file marker.
is_codespaces() {
    [ "${CODESPACES:-}" = "true" ] || [ -d "/workspaces/.codespaces" ]
}

# -- Firewall setup ---------------------------------------------------
if is_codespaces; then
    log_info "Codespaces detected — skipping firewall setup (not needed here)"
else
    sudo /usr/local/libexec/init-firewall.sh
fi

# -- Git config -------------------------------------------------------
# In a dev container, VS Code injects its own .gitconfig (host credentials,
# signing config, etc). Only install our default when not in that context.
if [ -z "${DEVCONTAINER:-}" ] && [ ! -f "$HOME/.gitconfig" ]; then
    cp /etc/skel/.gitconfig "$HOME/.gitconfig"
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

# -- Memory sync symlink ----------------------------------------------
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
    fi
else
    log_info "memory sync not configured; run claudebox-memory-init to enable"
fi
