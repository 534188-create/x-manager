#!/usr/bin/env bash
MODE_FILE="/etc/snell/routing.mode"
MODE="xray"
[ -f "$MODE_FILE" ] && MODE=$(cat "$MODE_FILE" | tr -d ' ')

iptables -t nat -D OUTPUT -m owner --uid-owner snell -j SNELL_OUT 2>/dev/null || true
iptables -t nat -F SNELL_OUT 2>/dev/null || true
iptables -t nat -X SNELL_OUT 2>/dev/null || true

if [ "$MODE" = "xray" ]; then
    iptables -t nat -N SNELL_OUT
    iptables -t nat -A SNELL_OUT -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A SNELL_OUT -d 89.19.223.185 -j RETURN
    iptables -t nat -A SNELL_OUT -p tcp -j REDIRECT --to-ports 12346
    iptables -t nat -I OUTPUT 1 -m owner --uid-owner snell -j SNELL_OUT
fi
