{
  config,
  pkgs,
  username,
  ...
}: {
  users.users.${username}.extraGroups = ["docker"];

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation = {
    oci-containers.backend = "podman";
    docker = {
      enable = true;
      # nvidia-container-toolkit is enabled in hosts/server/default.nix
    };
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
