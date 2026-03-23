#!/bin/bash
set -euo pipefail

/usr/local/libexec/container-init.sh

exec "$@"
