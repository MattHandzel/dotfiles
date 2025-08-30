{
  pkgs,
  lib,
  ...
}: {
  home.activation.ensureFoliateConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p $HOME/.config/foliate
    chmod -R u+w $HOME/.config/foliate
  '';
}
