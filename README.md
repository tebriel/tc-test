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

## Delay script

`scripts/proxysql-delay-host.sh` runs on a ProxySQL host (or the test VM). It
adds 25ms in each direction (about 50ms per round trip) only to TCP 6033
traffic from selected CIDRs. The defaults are these IAD production supernets
from github/network `docs/ip_usage/Global-IP-Address-Allocation.yaml`:

| Site | CIDR |
| --- | --- |
| va3-iad | `10.48.0.0/14` |
| ac4-iad | `10.52.0.0/14` |
| ash1-iad | `10.56.0.0/14` |

```bash
sudo bash proxysql-delay-host.sh eth0          # Apply.
sudo bash proxysql-delay-host.sh eth0 remove   # Remove.
```

`PORT`, `DELAY`, and space-separated `CIDRS` (IPv4 or IPv6) override the
defaults. tc `flower` matches the CIDRs and port directly; iptables is not
needed. Incoming requests are redirected through an IFB with netem; outgoing
replies use a delayed PRIO band whose all-zero priomap keeps other traffic out.

The script refuses to apply if the interface already has custom qdiscs, and
removes partial shaping if apply fails. Its single PRIO root replaces the NIC's
multi-queue root qdisc while applied.

## Test

The test creates a client/server veth pair in two network namespaces inside
the VM. It never modifies the host network or the VM's SSH interface.
Synced folders are disabled; scripts are copied over SSH.

| Client | IPv4 | IPv6 | TCP 6033 |
| --- | --- | --- | --- |
| Shaped | `10.200.1.2` | `fd00:200::2` | ~50ms round trip |
| Unshaped | `10.200.1.3` | `fd00:200::3` | No added delay |

The test applies the delay script with `CIDRS` set to the shaped clients. It
binds each connection to a source IP and checks round-trip times on ports
6033, 3306, and 6032 before shaping, while shaped, and after removal. Only
shaped clients on 6033 should see about 50ms; everything else must stay below
15ms. Queue counters are printed for inspection. Namespace cleanup runs on
success or failure, so no artificial delay remains after the test.

```bash
vagrant ssh
sudo bash /home/vagrant/tc-test/run-test.sh
```

`devenv test` checks shell scripts with ShellCheck. The full network test runs
during provisioning and exits nonzero if any timing check fails.
Timing tolerances allow modest VM scheduling noise; a heavily loaded host can
still fail them.
