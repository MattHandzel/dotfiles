# The macOS half of the Redwood-issued MacBook: Matt's system defaults and the
# Home Manager work profile. Deliberately absent, compared with ./default.nix:
# sops (no personal secrets on a managed laptop), the Homebrew cask list
# (apps come from the kit's Brewfile), the Dia/Chrome policies, Spicetify and
# the "open with Neovim" handlers, which all serve personal apps.
{
  inputs,
  username,
  host,
  self,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./system-defaults.nix
    inputs.home-manager-darwin.darwinModules.home-manager
  ];

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;
  environment.shells = [pkgs.zsh];
  # The kit installs apps and CLIs with Homebrew (brew, op, aerospace, borders,
  # sketchybar). Without this the nix-darwin shell drops /opt/homebrew/bin.
  environment.systemPath = lib.mkBefore ["/opt/homebrew/bin"];
  # Display sleep matches the personal Mac (5 min; macOS default here was 2).
  # System sleep is left alone: this is a laptop on battery.
  power.sleep.display = 5;
  environment.systemPackages = with pkgs; [kitty coreutils gnused gnugrep findutils terminal-notifier choose-gui pngpaste];

  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs username host self;};
    backupFileExtension = "hm-backup";
    users.${username} = {
      imports = [./../home/work.nix];
      home.username = username;
      home.homeDirectory = "/Users/${username}";
      home.stateVersion = "25.11";
      programs.home-manager.enable = true;
    };
  };

  # Settings from ./system-defaults.nix that must not reach a managed laptop.
  system.defaults = {
    # Gatekeeper's quarantine prompt stays on.
    LaunchServices.LSQuarantine = lib.mkForce true;
    # Login window, guest account, screen lock and updates belong to Redwood's
    # device management; leave whatever it set.
    loginwindow = {
      LoginwindowText = lib.mkForce null;
      GuestEnabled = lib.mkForce null;
      SHOWFULLNAME = lib.mkForce null;
    };
    screensaver = {
      askForPassword = lib.mkForce null;
      askForPasswordDelay = lib.mkForce null;
    };
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = lib.mkForce null;
    # SketchyBar is the bar here too (personal-only items are skipped), so the
    # macOS menu bar auto-hides as on matts-mac (system-defaults.nix).
    dock.persistent-apps = lib.mkForce [
      "/Applications/kitty.app"
      "/Applications/Google Chrome.app"
      "/Applications/Slack.app"
    ];
  };
}
