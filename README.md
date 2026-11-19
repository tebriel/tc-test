# tc-test

Disposable Ubuntu 24.04 ARM64 VM for testing a selective 25ms delay in each
direction on the ProxySQL client port (TCP 6033). Uses QEMU on Apple Silicon macOS.
No actual ProxySQL or MySQL installation is needed.

```bash
devenv shell
vagrant up --provision  # Boot, upload scripts, and run tests.
vagrant provision      # Upload current scripts and rerun tests.
vagrant destroy -f     # Destroy the VM.
```

Requires Nix and devenv. Vagrant and QEMU come from `devenv.nix`.
Entering the shell ensures the project-local Vagrant QEMU plugin is installed.
The first run downloads the VM image and guest packages.

The test creates client, router, and server network namespaces connected by
veth pairs inside the VM. It never modifies the host network or the VM's SSH interface.
Synced folders are disabled; scripts are copied over SSH.

Both client source IPs cross the router's `server0` interface:

| Client | IPv4 | IPv6 | TCP 6033 |
| --- | --- | --- | --- |
| Tagged | `10.200.1.2` | `fd00:200::2` | 25ms each direction |
| Untagged | `10.200.1.3` | `fd00:200::3` | No added delay |

`scripts/proxysql-delay.sh` uses iptables/ip6tables mangle PREROUTING rules to
set packet-mark bit 0 for tagged client IPs sending to TCP 6033 and replies
from that port. A tc `fw` filter sends only marked packets to a 25ms netem
PRIO band on each router egress interface. The all-zero priomap keeps
unmatched traffic out of that band. Other mark bits are preserved.

Routing is intentional: tc ingress runs **before** iptables PREROUTING,
so an ingress IFB redirect cannot use the mark assigned to that packet by
iptables. Forwarding through the router puts marking before either egress queue.
This script now requires two interfaces on an already configured router,
not a single interface on the server:

```bash
# Run as root in the router namespace; PORT defaults to 6033.
PORT=6033 bash proxysql-delay.sh server0 backend0 10.200.1.2 fd00:200::2
```

The script requires unused root qdiscs, an unused `TC_PROXYSQL` mangle chain,
and reserves mark bit 0 on both interfaces. Run it once per fresh namespace.

The test binds connections explicitly to each source IP and checks IPv4 and
IPv6 echo RTTs before and after shaping, then each direction separately:
about 50ms combined, 25ms individually for tagged clients only. Untagged
clients and ports 3306/6032 must remain below 15ms. Rule and queue counters
are printed for inspection. Namespace cleanup runs on success or failure,
so no artificial delay remains after the test.

```bash
vagrant ssh
sudo bash /home/vagrant/tc-test/run-test.sh
```

`devenv test` checks shell scripts with ShellCheck. The full network test runs
during provisioning and exits nonzero if any timing check fails.
Timing tolerances allow modest VM scheduling noise; a heavily loaded host can
still fail them.
