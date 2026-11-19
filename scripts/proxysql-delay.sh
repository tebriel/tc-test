#!/usr/bin/env bash
set -euo pipefail

IFACE=${1:?Usage: sudo bash proxysql-delay.sh CLIENT_INTERFACE SERVER_INTERFACE TAGGED_IP...}
SERVER_IFACE=${2:?Specify the server-facing interface}
shift 2
[[ $# -gt 0 ]] || { echo 'Specify at least one tagged client IP.' >&2; exit 1; }
PORT=${PORT:-6033}

# Mark after routing ingress, before tc egress. Bit 0 is reserved for this shaper.
for IPTABLES in iptables ip6tables; do
  "$IPTABLES" -t mangle -N TC_PROXYSQL
  "$IPTABLES" -t mangle -A TC_PROXYSQL -j MARK --set-xmark 0x0/0x1
  "$IPTABLES" -t mangle -A PREROUTING -i "$IFACE" -j TC_PROXYSQL
  "$IPTABLES" -t mangle -A PREROUTING -i "$SERVER_IFACE" -j TC_PROXYSQL
done

for ADDRESS in "$@"; do
  IPTABLES=iptables
  [[ $ADDRESS != *:* ]] || IPTABLES=ip6tables
  "$IPTABLES" -t mangle -A TC_PROXYSQL -i "$IFACE" -s "$ADDRESS" \
    -p tcp --dport "$PORT" -j MARK --set-xmark 0x1/0x1
  "$IPTABLES" -t mangle -A TC_PROXYSQL -i "$SERVER_IFACE" -d "$ADDRESS" \
    -p tcp --sport "$PORT" -j MARK --set-xmark 0x1/0x1
done

for DEV in "$IFACE" "$SERVER_IFACE"; do
  # Default traffic uses band 1; only marked packets use delayed band 3.
  tc qdisc add dev "$DEV" root handle 1: prio bands 3 \
    priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
  tc qdisc add dev "$DEV" parent 1:3 handle 20: netem delay 25ms limit 100000
  tc filter add dev "$DEV" parent 1: protocol all pref 10 \
    handle 0x1/0x1 fw classid 1:3
done
