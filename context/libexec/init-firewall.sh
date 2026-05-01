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

# -- Allow specific destination (e.g., OLLAMA) -------------------------
# Format: HOSTNAME_OR_IP:PORT (e.g., ollama-server:11434)
if [ -n "${FIREWALL_ALLOWED_DEST:-}" ]; then
    DEST_HOST=$(echo "$FIREWALL_ALLOWED_DEST" | cut -d':' -f1)
    DEST_PORT=$(echo "$FIREWALL_ALLOWED_DEST" | cut -d':' -f2)

    if [ -n "$DEST_HOST" ] && [ -n "$DEST_PORT" ]; then
        # Resolve hostname to IP
        DEST_IP=$(getent hosts "$DEST_HOST" | awk '{print $1}')
        if [ -n "$DEST_IP" ]; then
            iptables -A OUTPUT -p tcp -d "$DEST_IP" --dport "$DEST_PORT" -j ACCEPT
        else
            # Fallback to treating it as an IP if getent fails (e.g. if it's already an IP)
            iptables -A OUTPUT -p tcp -d "$DEST_HOST" --dport "$DEST_PORT" -j ACCEPT
        fi
    fi
fi

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
