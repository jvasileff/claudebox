#!/bin/bash
set -uxo pipefail

echo "=== [entrypoint.sh] Starting ==="
echo "=== [entrypoint.sh] whoami=$(whoami) uid=$(id -u) gid=$(id -g) ==="
echo "=== [entrypoint.sh] CODESPACES=${CODESPACES:-unset} DEVCONTAINER=${DEVCONTAINER:-unset} ==="
echo "=== [entrypoint.sh] env vars:" && env | sort
echo "=== [entrypoint.sh] /etc/passwd:" && cat /etc/passwd
echo "=== [entrypoint.sh] id:" && id

# In devcontainer/Codespaces mode, postStartCommand handles init AFTER
# environment variables (like CODESPACES=true) are injected. During
# docker start, those env vars aren't available yet, so container-init.sh
# can't detect the environment correctly. We make init best-effort here
# and let postStartCommand do the authoritative run.
echo "=== [entrypoint.sh] Running container-init.sh (best-effort) ==="
if /usr/local/libexec/container-init.sh; then
    echo "=== [entrypoint.sh] container-init.sh succeeded ==="
else
    rc=$?
    echo "=== [entrypoint.sh] container-init.sh failed (exit code: $rc) ==="
    echo "=== [entrypoint.sh] continuing — postStartCommand will retry with full env ==="
fi

echo "=== [entrypoint.sh] exec-ing: $* ==="
exec "$@"
