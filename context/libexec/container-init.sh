#!/bin/bash
set -euo pipefail

# -- This script runs as coder ----------------------------------------
# Outside of Codespaces: if the firewall fails, the container dies —
# there is no state where Claude Code runs without network isolation.
# In Codespaces: the firewall is skipped entirely. Codespaces does not
# reliably block NET_ADMIN, so if the capability is silently granted,
# iptables would succeed and block internal communication (causing a
# hang). The firewall is unnecessary in Codespaces anyway — there's no
# local LAN, Docker host, or metadata endpoint to protect against.

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
# In Codespaces, skip the firewall entirely. Codespaces does not reliably
# block NET_ADMIN — if the capability is silently granted, iptables
# succeeds and blocks Codespaces' internal communication (causing a hang).
# The firewall protects against local-network threats that don't apply in
# Codespaces (no LAN, no Docker host, no local metadata endpoint).
if is_codespaces; then
    log_info "Codespaces detected — skipping firewall setup (not needed here)"
else
    sudo /usr/local/libexec/init-firewall.sh
fi

# -- Git config -------------------------------------------------------
if [ -z "${DEVCONTAINER:-}" ] && [ ! -f "$HOME/.gitconfig" ]; then
    cp /etc/skel/.gitconfig "$HOME/.gitconfig"
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
