#!/usr/bin/env bash
set -euo pipefail

IFACE=${1:?Usage: sudo bash proxysql-delay.sh CLIENT_INTERFACE}
IFB=ifb-proxysql

modprobe ifb
ip link add "$IFB" type ifb
ip link set "$IFB" up
tc qdisc add dev "$IFB" root handle 30: netem delay 25ms limit 100000

# Default traffic uses band 1; only ProxySQL replies use delayed band 3.
tc qdisc add dev "$IFACE" root handle 1: prio bands 3 \
  priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
tc qdisc add dev "$IFACE" parent 1:3 handle 20: netem delay 25ms limit 100000
tc qdisc add dev "$IFACE" handle ffff: ingress

PREF=10
for PROTO in ip ipv6; do
  tc filter add dev "$IFACE" parent 1: protocol "$PROTO" pref "$PREF" \
    flower skip_hw ip_proto tcp src_port 6033 classid 1:3
  tc filter add dev "$IFACE" parent ffff: protocol "$PROTO" pref "$PREF" \
    flower skip_hw ip_proto tcp dst_port 6033 \
    action mirred egress redirect dev "$IFB"
  PREF=$((PREF + 1))
done
