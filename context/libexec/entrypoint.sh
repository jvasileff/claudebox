#!/bin/bash
# No set -e: container-init.sh failure must not kill the container.
# In Codespaces, the CODESPACES env var isn't available at docker start
# time (injected later by devcontainer CLI). The container must stay
# alive so the shell server can connect. postStartCommand retries init.

if /usr/local/libexec/container-init.sh; then
    : # init succeeded
else
    echo "WARNING: container-init.sh failed (exit code: $?) — continuing" >&2
fi

exec "$@"
