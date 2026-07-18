{
  pkgs,
  config,
  ...
}: {
  services.mako = {
    enable = true;
    settings = {
      font = "${config.theme.font.mono} ${toString config.theme.font.sizes.xs}";
      margin = "10";
    };
  };
}
