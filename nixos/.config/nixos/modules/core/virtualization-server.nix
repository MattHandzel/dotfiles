{
  config,
  pkgs,
  username,
  ...
}: {
  users.users.${username}.extraGroups = ["docker"];

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation = {
    oci-containers.backend = "docker";
    docker = {
      enable = true;
      autoPrune.enable = true;
    };
  };
}
