# System-level packages on the Mac.
#
# GUI apps built by Nix must go in `environment.systemPackages`, not in
# `home.packages`: nix-darwin's activation builds the /Applications/Nix Apps
# trampoline from the SYSTEM profile only. A Nix-built .app in the user profile
# is installed but never appears in Spotlight, Raycast or `open -a`.
#
# Everything here is a tool nixpkgs packages well for darwin. Anything that
# needs Apple notarization or a system extension is a cask instead — see
# modules/darwin/homebrew.nix for the reasoning.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # GUI, so it needs the trampoline
    kitty
    mpv

    # CLI
    kanata # keyboard remapper (launchd daemon in modules/darwin/kanata.nix)
    tailscale # CLI only; the NetworkExtension lives in the tailscale-app cask
    terminal-notifier # backs the `notify` shim on darwin
    choose-gui # backs the `pick` shim (the fuzzel --dmenu equivalent)
    pngpaste # backs `clip-paste -t image/png`
    coreutils
    gnused
    gnugrep
    findutils
  ];

  environment.shells = [pkgs.zsh];

  # Tailscale is the GUI app (the cask), NOT nix-darwin's services.tailscale:
  # the app is what installs the NetworkExtension and the DNS shim macOS needs.
  #
  # IMPORTANT for Matt: the tailnet's DNS points at the home server (blocky).
  # With that server down, "Use Tailscale DNS settings" must be OFF or the Mac
  # loses name resolution entirely:
  #     tailscale set --accept-dns=false
}
