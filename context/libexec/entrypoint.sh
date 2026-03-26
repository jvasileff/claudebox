#!/bin/bash
# Bare-minimum entrypoint for Codespaces boot debugging.
# Everything commented out to establish a working baseline.
echo "=== [entrypoint.sh] exec-ing: $* ==="
exec "$@"
