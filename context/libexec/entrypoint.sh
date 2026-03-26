#!/bin/bash
set -euxo pipefail

echo "=== [entrypoint.sh] Starting ==="
echo "=== [entrypoint.sh] whoami=$(whoami) uid=$(id -u) gid=$(id -g) ==="
echo "=== [entrypoint.sh] CODESPACES=${CODESPACES:-unset} DEVCONTAINER=${DEVCONTAINER:-unset} ==="
echo "=== [entrypoint.sh] Running container-init.sh ==="

/usr/local/libexec/container-init.sh

echo "=== [entrypoint.sh] container-init.sh completed, exec-ing: $* ==="
exec "$@"
