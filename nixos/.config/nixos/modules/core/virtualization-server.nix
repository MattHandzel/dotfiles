{
  config,
  pkgs,
  username,
  ...
}: {
  users.users.${username}.extraGroups = ["docker"];

  virtualisation = {
    docker = {
      enable = true;
      # nvidia-container-toolkit is enabled in hosts/server/default.nix
    };
  };
}
