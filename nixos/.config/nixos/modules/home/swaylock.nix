{pkgs, lib, ...}: {
  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      screenshots = true;
      clock = true;
      indicator = true;
      indicator-radius = 100;
      indicator-thickness = 7;
      effect-blur = "7x5";
      effect-vignette = "0.5:0.2";
      ring-color = lib.mkForce "bb9af7";
      key-hl-color = lib.mkForce "7aa2f7";
      text-color = lib.mkForce "7aa2f7";
      line-color = lib.mkForce "00000000";
      inside-color = lib.mkForce "00000000";
      separator-color = lib.mkForce "00000000";
      # Adding mkForce to potential conflicting colors from catppuccin
      bs-hl-color = lib.mkForce "bb9af7";
      caps-lock-key-hl-color = lib.mkForce "bb9af7";
      caps-lock-bs-hl-color = lib.mkForce "bb9af7";
      inside-clear-color = lib.mkForce "00000000";
      inside-caps-lock-color = lib.mkForce "00000000";
      inside-ver-color = lib.mkForce "00000000";
      inside-wrong-color = lib.mkForce "00000000";
      layout-bg-color = lib.mkForce "00000000";
      layout-border-color = lib.mkForce "00000000";
      layout-text-color = lib.mkForce "7aa2f7";
      ring-clear-color = lib.mkForce "bb9af7";
      ring-caps-lock-color = lib.mkForce "bb9af7";
      ring-ver-color = lib.mkForce "bb9af7";
      ring-wrong-color = lib.mkForce "bb9af7";
      text-clear-color = lib.mkForce "7aa2f7";
      text-caps-lock-color = lib.mkForce "7aa2f7";
      text-ver-color = lib.mkForce "7aa2f7";
      text-wrong-color = lib.mkForce "7aa2f7";
    };
  };
}
