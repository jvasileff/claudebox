#!/bin/bash
set -euo pipefail

/usr/local/libexec/container-init.sh

# Podman puts --cap-add capabilities in the ambient set of a non-root
# USER, so coder would otherwise hold NET_ADMIN and could rewrite the
# firewall with plain iptables. Clear the inheritable and ambient sets
# before handing off; the bounding set stays, and that is all sudo
# needs to run the firewall script as root. Docker/runc leaves these
# sets empty already, so this is a no-op there.
exec setpriv --inh-caps=-all --ambient-caps=-all -- "$@"
