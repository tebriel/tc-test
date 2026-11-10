Vagrant.configure("2") do |config|
  config.vm.box = "perk/ubuntu-24.04-arm64"
  config.vm.box_version = "20250704"
  config.vm.box_architecture = "arm64"
  config.vm.hostname = "tc-test"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider "qemu" do |qemu|
    qemu.memory = "1G"
    qemu.smp = "2"
    # Project-local Vagrant state exceeds macOS's Unix socket path limit.
    qemu.control_port = 50023
    qemu.debug_port = 50024
  end

  config.vm.provision "file", source: "scripts", destination: "/home/vagrant/tc-test"
  config.vm.provision "shell", inline: <<-SHELL
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends iproute2 kmod python3
    if ! modprobe ifb; then
      apt-get install -y --no-install-recommends "linux-modules-extra-$(uname -r)"
      modprobe ifb
    fi
    bash /home/vagrant/tc-test/run-test.sh
  SHELL
end
