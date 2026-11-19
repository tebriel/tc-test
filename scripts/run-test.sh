#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ $(uname -s) != Linux || $EUID != 0 ]]; then
  echo 'Run this as root inside the Linux VM.' >&2
  exit 1
fi

# Do not overwrite or clean up namespaces owned by another run.
for ns in tc-client tc-router tc-server; do
  if ip netns exec "$ns" true 2>/dev/null; then
    echo "Namespace $ns already exists; refusing to overwrite it." >&2
    exit 1
  fi
done

SERVER_PID=
cleanup() {
  if [[ -n $SERVER_PID ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  ip netns del tc-client 2>/dev/null || true
  ip netns del tc-router 2>/dev/null || true
  ip netns del tc-server 2>/dev/null || true
}
trap cleanup EXIT

ip netns add tc-client
ip netns add tc-router
ip netns add tc-server
ip -n tc-client link add client0 type veth peer name server0
ip -n tc-client link set server0 netns tc-router
ip -n tc-router link add backend0 type veth peer name backend1
ip -n tc-router link set backend1 netns tc-server
ip -n tc-client addr add 10.200.1.2/24 dev client0
ip -n tc-client addr add 10.200.1.3/24 dev client0
ip -n tc-router addr add 10.200.1.1/24 dev server0
ip -n tc-client -6 addr add fd00:200::2/64 dev client0 nodad
ip -n tc-client -6 addr add fd00:200::3/64 dev client0 nodad
ip -n tc-router -6 addr add fd00:200::1/64 dev server0 nodad
ip -n tc-router addr add 10.200.2.1/30 dev backend0
ip -n tc-server addr add 10.200.2.2/30 dev backend1
ip -n tc-router -6 addr add fd00:201::1/64 dev backend0 nodad
ip -n tc-server -6 addr add fd00:201::2/64 dev backend1 nodad
ip -n tc-client link set lo up
ip -n tc-router link set lo up
ip -n tc-server link set lo up
ip -n tc-client link set client0 up
ip -n tc-router link set server0 up
ip -n tc-router link set backend0 up
ip -n tc-server link set backend1 up
ip -n tc-client route add 10.200.2.0/30 via 10.200.1.1
ip -n tc-client -6 route add fd00:201::/64 via fd00:200::1
ip -n tc-server route add 10.200.1.0/24 via 10.200.2.1
ip -n tc-server -6 route add fd00:200::/64 via fd00:201::1
ip netns exec tc-router sysctl -qw net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1

ip netns exec tc-server python3 -u echo.py &
SERVER_PID=$!

ip netns exec tc-client python3 probe.py baseline
ip netns exec tc-router bash proxysql-delay.sh server0 backend0 10.200.1.2 fd00:200::2
ip netns exec tc-client python3 probe.py delayed

# Each direction alone must add 25ms, not 50ms in only one direction.
ip netns exec tc-router tc qdisc change dev server0 parent 1:3 handle 20: netem delay 0ms limit 100000
ip netns exec tc-client python3 probe.py ingress-only
ip netns exec tc-router tc qdisc change dev server0 parent 1:3 handle 20: netem delay 25ms limit 100000
ip netns exec tc-router tc qdisc change dev backend0 parent 1:3 handle 20: netem delay 0ms limit 100000
ip netns exec tc-client python3 probe.py egress-only

ip netns exec tc-router iptables -t mangle -nvL TC_PROXYSQL
ip netns exec tc-router ip6tables -t mangle -nvL TC_PROXYSQL
ip netns exec tc-router tc -s qdisc show dev server0
ip netns exec tc-router tc -s qdisc show dev backend0
echo 'PASS: IPv4/IPv6, tagged IPs delayed 25ms each direction, untagged IPs and control ports unchanged.'
