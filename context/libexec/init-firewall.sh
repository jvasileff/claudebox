#!/bin/bash
set -euo pipefail

# -- Flush any existing rules before changing default policies --------
# Flushing first ensures no existing rules interfere mid-setup.
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# -- Loopback ---------------------------------------------------------
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# -- DNS: allow only the container's configured resolver --------------
DNS_SERVER=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
DNS_SERVER="${DNS_SERVER:-127.0.0.11}"

iptables -A OUTPUT -p udp -d "$DNS_SERVER" --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp -d "$DNS_SERVER" --dport 53 -j ACCEPT
iptables -A INPUT  -p udp -s "$DNS_SERVER" --sport 53 -j ACCEPT
iptables -A INPUT  -p tcp -s "$DNS_SERVER" --sport 53 -j ACCEPT

# -- Allowed private destinations (user-opted holes) ------------------
# FIREWALL_ALLOWED_DEST lists HOST:PORT entries separated by commas or
# whitespace, e.g. "ollama-box:11434, 192.168.1.20:5432". Each host is
# resolved to its IPv4 addresses (IPv6 is blocked below) and a TCP
# ACCEPT rule per address is added ahead of the private-range block.
# A malformed or unresolvable entry aborts the script, so the container
# fails to start rather than silently running without the hole asked
# for.
#
# The list is honored only on the first run, when it is saved to a
# root-only file; later runs (a manual `sudo init-firewall.sh`) re-apply
# the saved list and ignore the environment. sudo passes the variable
# through (env_keep in /etc/sudoers) so the container engine can set it,
# and without this step anything running as coder could reuse that
# channel to open the firewall to whatever it liked. /run is writable
# only by root, so coder cannot plant the file first.
STATE_DIR=/run/claudebox
STATE_FILE=$STATE_DIR/firewall-allowed-dest
if [ -e "$STATE_FILE" ]; then
    ALLOWED=$(cat "$STATE_FILE")
    if [ "${FIREWALL_ALLOWED_DEST-$ALLOWED}" != "$ALLOWED" ]; then
        echo "init-firewall: ignoring FIREWALL_ALLOWED_DEST; the list saved at first run applies" >&2
    fi
else
    ALLOWED=${FIREWALL_ALLOWED_DEST:-}
    (umask 077 && mkdir -p "$STATE_DIR" && printf '%s\n' "$ALLOWED" > "$STATE_FILE")
fi
if [ "$(stat -c '%u' "$STATE_DIR")" != 0 ]; then
    echo "init-firewall: $STATE_DIR is not owned by root; refusing to continue" >&2
    exit 1
fi

for ENTRY in ${ALLOWED//,/ }; do
    if ! [[ $ENTRY =~ ^([^:]+):([0-9]+)$ ]] \
        || [ "${BASH_REMATCH[2]}" -lt 1 ] || [ "${BASH_REMATCH[2]}" -gt 65535 ]; then
        echo "init-firewall: bad FIREWALL_ALLOWED_DEST entry '$ENTRY' (want HOST:PORT)" >&2
        exit 1
    fi
    HOST=${BASH_REMATCH[1]} PORT=${BASH_REMATCH[2]}
    IPS=$({ getent ahostsv4 "$HOST" || true; } | awk '{print $1}' | sort -u)
    if [ -z "$IPS" ]; then
        echo "init-firewall: cannot resolve '$HOST' (FIREWALL_ALLOWED_DEST)" >&2
        exit 1
    fi
    for IP in $IPS; do
        iptables -A OUTPUT -p tcp -d "$IP" --dport "$PORT" -j ACCEPT
    done
done

# -- Block all private/local IP ranges --------------------------------
# This prevents access to: the Docker host, other containers,
# LAN services, and cloud metadata endpoints (169.254.169.254).
for RANGE in \
    "10.0.0.0/8" \
    "172.16.0.0/12" \
    "192.168.0.0/16" \
    "169.254.0.0/16" \
    "100.64.0.0/10" \
; do
    iptables -A OUTPUT -d "$RANGE" -j REJECT --reject-with icmp-admin-prohibited
done

# -- Allow all other outbound traffic (public internet) ---------------
iptables -A OUTPUT -j ACCEPT

# -- Allow established/related inbound --------------------------------
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# -- Default policies -------------------------------------------------
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# -- Block IPv6 -------------------------------------------------------
# sysctl writes are blocked inside containers, so we rely on ip6tables.
# If ip6tables is unavailable the container must not start (fail-closed).
# REJECT before DROP so failures are fast rather than timing out.
ip6tables -A INPUT  -j REJECT
ip6tables -A OUTPUT -j REJECT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
