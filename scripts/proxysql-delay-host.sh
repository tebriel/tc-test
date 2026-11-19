#!/usr/bin/env bash
# Delay ProxySQL traffic from selected CIDRs by DELAY in each direction.
# Defaults to the IAD production sites.
# Run as root on the ProxySQL host itself.
set -euo pipefail

usage='Usage: sudo bash proxysql-delay-host.sh INTERFACE [apply|remove]'
IFACE=${1:?$usage}
ACTION=${2:-apply}
PORT=${PORT:-6033}
DELAY=${DELAY:-25ms}
IFB=ifb-proxysql
# Production supernets (va3-iad, ac4-iad, ash1-iad) from github/network
# docs/ip_usage/Global-IP-Address-Allocation.yaml. Override with CIDRS="a b".
read -r -a CIDRS <<< "${CIDRS:-10.48.0.0/14 10.52.0.0/14 10.56.0.0/14}"

remove() {
  tc qdisc del dev "$IFACE" root 2>/dev/null || true
  tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
  ip link del "$IFB" 2>/dev/null || true
}

case $ACTION in
  remove) remove; exit ;;
  apply) ;;
  *) echo "$usage" >&2; exit 1 ;;
esac

# Only kernel-default qdiscs (handle 0:) may exist, so removal never deletes
# shaping owned by something else.
if tc qdisc show dev "$IFACE" | grep -qvE '^qdisc [a-z_]+ 0: (root|parent )'; then
  echo "$IFACE already has custom qdiscs; run '$0 $IFACE remove' if they are ours." >&2
  exit 1
fi
if ip link show "$IFB" &>/dev/null; then
  echo "$IFB already exists; run '$0 $IFACE remove' first." >&2
  exit 1
fi
trap 'echo "Apply failed; removing partial shaping." >&2; remove' ERR

# Replies: only matching packets enter the delayed PRIO band 3.
# ponytail: one prio root replaces mq, so egress shares one qdisc lock; use
# mq with per-queue prio children if throughput on this NIC suffers.
tc qdisc add dev "$IFACE" root handle 1: prio bands 3 \
  priomap 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
tc qdisc add dev "$IFACE" parent 1:3 handle 20: netem delay "$DELAY" limit 100000

# Requests: ingress has no queue, so redirect matches through a delayed IFB.
modprobe ifb
ip link add "$IFB" type ifb
ip link set "$IFB" up
tc qdisc add dev "$IFB" root handle 30: netem delay "$DELAY" limit 100000
tc qdisc add dev "$IFACE" handle ffff: ingress

for CIDR in "${CIDRS[@]}"; do
  # tc requires one protocol per filter priority.
  PROTO=ip PREF=10
  [[ $CIDR != *:* ]] || PROTO=ipv6 PREF=11
  tc filter add dev "$IFACE" parent 1: protocol "$PROTO" pref "$PREF" \
    flower skip_hw ip_proto tcp dst_ip "$CIDR" src_port "$PORT" classid 1:3
  tc filter add dev "$IFACE" parent ffff: protocol "$PROTO" pref "$PREF" \
    flower skip_hw ip_proto tcp src_ip "$CIDR" dst_port "$PORT" \
    action mirred egress redirect dev "$IFB"
done
