{pkgs, ...}: let
  # Unofficial Linux port (github.com/wispr-flow-linux/wispr-flow-linux) — Wispr
  # ships no native Linux app. The port's own Nix flake is not usable: its helper
  # fetchFromGitHub still carries lib.fakeHash and it leaves the bundled
  # better-sqlite3 natives as Windows PE binaries, so DB-backed features break.
  # The released AppImage is pre-staged with those natives rebuilt, so wrap that.
  version = "1.6.7-1.0.3";

  src = pkgs.fetchurl {
    url = "https://github.com/wispr-flow-linux/wispr-flow-linux/releases/download/v1.0.3+wispr1.6.7/wispr-flow-1.6.7-1.0.3-x86_64.AppImage";
    hash = "sha256-T9/evAykYnc20TVc7sX3Bwf8aTkTkxEtDr8FNavIMfA=";
  };

  contents = pkgs.appimageTools.extract {
    pname = "wispr-flow";
    inherit version src;
  };

  wispr-flow = pkgs.appimageTools.wrapType2 {
    pname = "wispr-flow";
    inherit version src;

    # Text injection shells out to clipboard tooling; the tray/notification path
    # wants libnotify, and Electron's keytar needs libsecret.
    extraPkgs = ps:
      with ps; [
        libnotify
        libsecret
        wl-clipboard
        xdg-utils
        xclip
      ];

    extraInstallCommands = ''
      install -Dm444 ${contents}/usr/share/applications/ai.wisprflow.WisprFlow.desktop \
        $out/share/applications/ai.wisprflow.WisprFlow.desktop
      substituteInPlace $out/share/applications/ai.wisprflow.WisprFlow.desktop \
        --replace-fail 'Exec=AppRun' 'Exec=wispr-flow'
      cp -r ${contents}/usr/share/icons $out/share/icons
    '';
  };
  # Waybar mic-level meter — see scripts/scripts/wispr-meter.py. Needs pw-record
  # + pw-dump (pipewire) and pgrep (procps) on PATH; pure-stdlib otherwise.
  wisprMeter = pkgs.stdenv.mkDerivation {
    name = "wispr-meter";
    unpackPhase = "true";
    buildInputs = [pkgs.makeWrapper];
    installPhase = ''
      mkdir -p $out/bin
      cp ${./scripts/scripts/wispr-meter.py} $out/bin/wispr-meter
      chmod +x $out/bin/wispr-meter
      sed -i '1s|^#!.*|#!${pkgs.python3}/bin/python3|' $out/bin/wispr-meter
      wrapProgram $out/bin/wispr-meter \
        --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.pipewire pkgs.procps]}
    '';
  };
in {
  home.packages = [wispr-flow wisprMeter];

  # Wispr enumerates evdev keyboards ONCE at startup and never rescans (see
  # modules/home/kbd-relay.nix), so it must start after the relay's virtual
  # keyboard exists — and be restarted whenever the relay restarts, or it keeps
  # watching a dead device node and hears nothing from the TOTEM (bit Matt
  # 2026-07-15). kbd-relay's ExecStartPost try-restarts this unit on every
  # relay (re)start; launching Wispr here instead of a hyprland exec-once is
  # what makes that lifecycle coupling possible.
  systemd.user.services.wispr-flow = {
    Unit = {
      Description = "Wispr Flow dictation app";
      After = ["graphical-session.target" "kbd-relay.service"];
      Wants = ["kbd-relay.service"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${wispr-flow}/bin/wispr-flow";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # wispr-pill-follow — the unit that pinned Wispr's dictation pill and walked it
  # to the cursor — was retired 2026-07-24 along with its script. It solved
  # "dictation ran unseen" by creating a worse problem: a permanent, unmovable
  # 440x320 obstruction mid-screen on every workspace (unmovable because the
  # pill is no_focus, so SUPER+drag can't grab it, and the follower re-asserted
  # any position change within 200ms).
  #
  # The pill is now banished to special:hidden by windowrule — see
  # modules/home/hyprland/config.nix. Nothing is lost: the waybar mic meter
  # (custom/wispr, modules/home/waybar/settings.nix) already reports dictation
  # state in the bar Matt is looking at anyway.
  #
  # Deliberately deleted rather than left orphaned — a dead-but-present script
  # reads as live during the next debug session. `git log -- \
  # modules/home/scripts/scripts/wispr-pill-follow.sh` recovers it.
}
