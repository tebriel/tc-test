#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ $(uname -s) != Linux || $EUID != 0 ]]; then
  echo 'Run this as root inside the Linux VM.' >&2
  exit 1
fi

# Do not overwrite or clean up namespaces owned by another run.
for ns in tc-client tc-server; do
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
  ip netns del tc-server 2>/dev/null || true
}
trap cleanup EXIT

ip netns add tc-client
ip netns add tc-server
ip -n tc-client link add client0 type veth peer name server0
ip -n tc-client link set server0 netns tc-server
# .2 / ::2 are inside the shaped CIDRs; .3 / ::3 are not.
ip -n tc-client addr add 10.200.1.2/24 dev client0
ip -n tc-client addr add 10.200.1.3/24 dev client0
ip -n tc-server addr add 10.200.1.1/24 dev server0
ip -n tc-client -6 addr add fd00:200::2/64 dev client0 nodad
ip -n tc-client -6 addr add fd00:200::3/64 dev client0 nodad
ip -n tc-server -6 addr add fd00:200::1/64 dev server0 nodad
ip -n tc-client link set lo up
ip -n tc-server link set lo up
ip -n tc-client link set client0 up
ip -n tc-server link set server0 up

ip netns exec tc-server python3 -u echo.py &
SERVER_PID=$!

ip netns exec tc-client python3 probe.py baseline
ip netns exec tc-server env CIDRS='10.200.1.2/32 fd00:200::2/128' \
  bash proxysql-delay-host.sh server0
ip netns exec tc-client python3 probe.py delayed
ip netns exec tc-server tc -s qdisc show dev server0
ip netns exec tc-server tc -s qdisc show dev ifb-proxysql

# Removal must restore baseline latency.
ip netns exec tc-server bash proxysql-delay-host.sh server0 remove
ip netns exec tc-client python3 probe.py baseline
echo 'PASS: shaped IPv4/IPv6 sources delayed ~50ms RTT on 6033; other sources and ports unchanged.'
