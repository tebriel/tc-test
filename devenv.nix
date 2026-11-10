{ pkgs, config, ... }:
{
  packages = [ pkgs.vagrant pkgs.qemu pkgs.shellcheck ];
  env = {
    GEM_HOME = "${config.devenv.root}/.vagrant-home/gems-isolated";
    QEMU_DIR = "${pkgs.qemu}/share/qemu";
    VAGRANT_HOME = "${config.devenv.root}/.vagrant-home";
    VAGRANT_DEFAULT_PROVIDER = "qemu";
    CURL_CA_BUNDLE = "/etc/ssl/cert.pem";
    SSL_CERT_FILE = "/etc/ssl/cert.pem";
  };

  tasks."vagrant:plugins" = {
    before = [ "devenv:enterShell" ];
    exec = ''
      set -euo pipefail
      if ! vagrant plugin list | grep -q '^vagrant-qemu '; then
        vagrant plugin install vagrant-qemu
      fi
    '';
  };
  enterTest = "shellcheck scripts/*.sh";
}
