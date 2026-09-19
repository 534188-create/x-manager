#!/usr/bin/env bash
set -e

# Detect WAN interface dynamically
WAN_IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -n 1)
[ -z "$WAN_IF" ] && WAN_IF="eth0"

TPROXY_PORT="12345"
if [ -f "/etc/x-manager/gateways.env" ]; then
    # shellcheck source=/dev/null
    source /etc/x-manager/gateways.env
fi
[ -n "$XRAY_TPROXY_PORT" ] && TPROXY_PORT="$XRAY_TPROXY_PORT"

# 1. Routing table 100
ip rule show | grep -q "lookup 100" || ip rule add fwmark 1 table 100
ip route show table 100 | grep -q "local default dev lo" || ip route add local 0.0.0.0/0 dev lo table 100

# 2. iptables MANGLE rules
iptables -t mangle -N WDTT_TPROXY 2>/dev/null || iptables -t mangle -F WDTT_TPROXY

# Exclude local/internal
iptables -t mangle -A WDTT_TPROXY -d 10.66.0.0/16 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 10.70.0.0/16 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 127.0.0.0/8 -j RETURN

# TPROXY to 127.0.0.1
iptables -t mangle -A WDTT_TPROXY -p tcp -j TPROXY --on-port "$TPROXY_PORT" --on-ip 127.0.0.1 --tproxy-mark 1
iptables -t mangle -A WDTT_TPROXY -p udp -j TPROXY --on-port "$TPROXY_PORT" --on-ip 127.0.0.1 --tproxy-mark 1

# Hook to PREROUTING
iptables -t mangle -C PREROUTING -i wdtt0 -j WDTT_TPROXY 2>/dev/null || iptables -t mangle -I PREROUTING -i wdtt0 -j WDTT_TPROXY
iptables -t mangle -C PREROUTING -i wdttraw0 -j WDTT_TPROXY 2>/dev/null || iptables -t mangle -I PREROUTING -i wdttraw0 -j WDTT_TPROXY

# 3. Block external access from internet
iptables -C INPUT -i "$WAN_IF" -p tcp --dport "$TPROXY_PORT" -j DROP 2>/dev/null || iptables -I INPUT -i "$WAN_IF" -p tcp --dport "$TPROXY_PORT" -j DROP
iptables -C INPUT -i "$WAN_IF" -p udp --dport "$TPROXY_PORT" -j DROP 2>/dev/null || iptables -I INPUT -i "$WAN_IF" -p udp --dport "$TPROXY_PORT" -j DROP

# 4. Remove direct MASQUERADE (Kill Switch for direct leak)
while iptables -t nat -D POSTROUTING -s 10.66.0.0/16 -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.66.0.0/16 -o "$WAN_IF" -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.66.0.0/16 -o "$WAN_IF" -m comment --comment WDTT_MANAGED -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.70.0.0/16 -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.70.0.0/16 -o "$WAN_IF" -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.70.0.0/16 -o "$WAN_IF" -m comment --comment WDTT_RAW_MANAGED -j MASQUERADE 2>/dev/null; do :; done
