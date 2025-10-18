{
  pkgs,
  lib,
  ...
}: {
  home.activation.ensureFoliateConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -d "$HOME/.config/foliate" ]; then
      # Remove existing directory if owned by root
      if [ "$(stat -c '%U' "$HOME/.config/foliate")" = "root" ]; then
        $DRY_RUN_CMD rm -rf "$HOME/.config/foliate"
      fi
    fi
    $DRY_RUN_CMD mkdir -p "$HOME/.config/foliate"
    $DRY_RUN_CMD chmod -R u+w "$HOME/.config/foliate"
  '';
}
