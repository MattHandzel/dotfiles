{
  pkgs,
  lib,
  ...
}: {
  programs.waybar = {
    enable = true;
  };
  programs.waybar.package = pkgs.waybar.overrideAttrs (oa: {
    mesonFlags = (oa.mesonFlags or []) ++ ["-Dexperimental=true"];
  });

  # Waybar reads its config once at startup, so a rebuild that adds or changes a
  # module leaves the running bar showing the OLD one with no indication that
  # anything is stale. That looked exactly like a broken widget on 2026-07-26:
  # the "custom/writing" module was added and rebuilt at 10:46, but the bar had
  # been running since the 07:31 boot and never had the module at all.
  #
  # SIGUSR2 makes waybar re-read its config in place. Both names are tried
  # because wrapProgram renames the running process: its comm is
  # ".waybar-wrapped" even though its cmdline still reads "waybar", so matching
  # only "waybar" signals nothing and the reload silently does not happen —
  # which is the very bug this exists to prevent. `|| true` because no bar
  # running (a headless or pre-login activation) is not a failure.
  home.activation.reloadWaybar = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.procps}/bin/pkill -USR2 -x waybar \
      || ${pkgs.procps}/bin/pkill -USR2 -x .waybar-wrapped \
      || true
  '';
}
