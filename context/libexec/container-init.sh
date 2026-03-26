#!/bin/bash
set -euxo pipefail

echo "=== [container-init.sh] Starting ==="
echo "=== [container-init.sh] whoami=$(whoami) uid=$(id -u) gid=$(id -g) ==="
echo "=== [container-init.sh] HOME=$HOME PWD=$PWD ==="
echo "=== [container-init.sh] CODESPACES=${CODESPACES:-unset} DEVCONTAINER=${DEVCONTAINER:-unset} ==="

# -- This script runs as coder ----------------------------------------
# Outside of Codespaces: if the firewall fails, the container dies —
# there is no state where Claude Code runs without network isolation.
# In Codespaces: the firewall is best-effort (NET_ADMIN is unavailable).

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

# -- Firewall setup ---------------------------------------------------
echo "=== [container-init.sh] Firewall setup ==="
if [ "${CODESPACES:-}" = "true" ]; then
    echo "=== [container-init.sh] Codespaces detected, firewall is best-effort ==="
    if sudo /usr/local/libexec/init-firewall.sh 2>/dev/null; then
        log_info "firewall initialized"
    else
        log_warn "firewall setup failed (Codespaces does not grant NET_ADMIN)"
        log_warn "network isolation is NOT active — this is expected in Codespaces"
    fi
else
    echo "=== [container-init.sh] Non-Codespaces, firewall is mandatory ==="
    sudo /usr/local/libexec/init-firewall.sh
fi
echo "=== [container-init.sh] Firewall setup done ==="

# -- Git config -------------------------------------------------------
echo "=== [container-init.sh] Git config ==="
if [ -z "${DEVCONTAINER:-}" ] && [ ! -f "$HOME/.gitconfig" ]; then
    cp /etc/skel/.gitconfig "$HOME/.gitconfig"
fi

# -- Java version selection (skipped — SDKs not installed) ------------
echo "=== [container-init.sh] Skipping Java version selection (SDKs not installed) ==="
# JAVA_VERSION_FILE="/workspaces/project/.java-version"
# if [ -f "$JAVA_VERSION_FILE" ]; then
#     JAVA_MAJOR=$(tr -d '[:space:]' < "$JAVA_VERSION_FILE")
#     set +u
#     BEST=$(sdk list java | grep '| installed' | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-[a-z]+" | grep "^${JAVA_MAJOR}\." | sort -V | tail -1 || true)
#     if [ -n "$BEST" ]; then
#         sdk default java "$BEST" > /dev/null
#     else
#         log_warn "Java $JAVA_MAJOR requested in .java-version but not installed; using image default"
#     fi
#     set -u
# fi

# -- Memory sync symlink ----------------------------------------------
echo "=== [container-init.sh] Memory sync symlink ==="
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

echo "=== [container-init.sh] Complete ==="
