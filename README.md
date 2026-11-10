# tc-test

Disposable Ubuntu 24.04 ARM64 VM for testing a 25ms delay in each direction
on the ProxySQL client port (TCP 6033). Uses QEMU on Apple Silicon macOS.
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

The test creates a client/server veth pair in two network namespaces inside
the VM. It never modifies the host network or the VM's SSH interface.
Synced folders are disabled; scripts are copied over SSH.

`scripts/proxysql-delay.sh` redirects TCP destination port 6033 ingress through
an IFB with netem, and selects TCP source port 6033 egress into a delayed PRIO
band. The all-zero priomap keeps unmatched traffic out of that band.

The test checks IPv4 and IPv6 echo RTTs before and after shaping, then checks
each direction separately: about 50ms combined, 25ms individually. Ports 3306
and 6032 must remain below 15ms. Namespace cleanup runs on success or failure,
so no artificial delay remains after the test.

```bash
vagrant ssh
sudo bash /home/vagrant/tc-test/run-test.sh
```

`devenv test` checks shell scripts with ShellCheck. The full network test runs
during provisioning and exits nonzero if any timing check fails.
Timing tolerances allow modest VM scheduling noise; a heavily loaded host can
still fail them.
