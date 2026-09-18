#!/bin/bash
set -e

# 1. Routing table 100
ip rule show | grep -q "lookup 100" || ip rule add fwmark 1 table 100
ip route show table 100 | grep -q "local default dev lo" || ip route add local 0.0.0.0/0 dev lo table 100

# 2. iptables MANGLE rules
iptables -t mangle -N WDTT_TPROXY 2>/dev/null || iptables -t mangle -F WDTT_TPROXY

# Exclude local/internal
iptables -t mangle -A WDTT_TPROXY -d 10.66.0.0/16 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 10.70.0.0/16 -j RETURN
iptables -t mangle -A WDTT_TPROXY -d 127.0.0.0/8 -j RETURN

# TPROXY to 127.0.0.1:12345
iptables -t mangle -A WDTT_TPROXY -p tcp -j TPROXY --on-port 12345 --on-ip 127.0.0.1 --tproxy-mark 1
iptables -t mangle -A WDTT_TPROXY -p udp -j TPROXY --on-port 12345 --on-ip 127.0.0.1 --tproxy-mark 1

# Hook to PREROUTING
iptables -t mangle -C PREROUTING -i wdtt0 -j WDTT_TPROXY 2>/dev/null || iptables -t mangle -I PREROUTING -i wdtt0 -j WDTT_TPROXY
iptables -t mangle -C PREROUTING -i wdttraw0 -j WDTT_TPROXY 2>/dev/null || iptables -t mangle -I PREROUTING -i wdttraw0 -j WDTT_TPROXY

# 3. Block external access from internet (ens3)
iptables -C INPUT -i ens3 -p tcp --dport 12345 -j DROP 2>/dev/null || iptables -I INPUT -i ens3 -p tcp --dport 12345 -j DROP
iptables -C INPUT -i ens3 -p udp --dport 12345 -j DROP 2>/dev/null || iptables -I INPUT -i ens3 -p udp --dport 12345 -j DROP

# 4. Remove direct MASQUERADE
iptables -t nat -D POSTROUTING -s 10.66.0.0/16 -o ens3 -m comment --comment WDTT_MANAGED -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.70.0.0/16 -o ens3 -m comment --comment WDTT_RAW_MANAGED -j MASQUERADE 2>/dev/null || true
