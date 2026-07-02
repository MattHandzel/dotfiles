{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  betterbirdBase = inputs.betterbird.packages.${pkgs.system}.default;
  # Heehaaw's betterbird-flake doesn't bundle libGL/libpci/libglvnd/mesa, so
  # rendering fails on Wayland NixOS (libpci missing -> EGL test failed ->
  # RenderCompositorSWGL framebuffer mapping fails -> no window). Wrap to
  # inject the graphics libs into LD_LIBRARY_PATH at launch.
  betterbird = pkgs.symlinkJoin {
    name = "betterbird-graphics-wrapped";
    paths = [betterbirdBase];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      # Wrap binary: inject graphics libs + always launch with -P matth so
      # we never hit "Profile Missing" when the install-hash binding is stale.
      wrapProgram $out/bin/betterbird \
        --prefix LD_LIBRARY_PATH ":" "${lib.makeLibraryPath (with pkgs; [libGL libglvnd mesa pciutils])}" \
        --add-flags "-P matth"

      # The .desktop file from Heehaaw's flake points Exec= at the unwrapped
      # binary (no LD_LIBRARY_PATH). Replace it with one that targets our
      # wrapped binary so fuzzel/app-menu launches work too.
      rm -f $out/share/applications/betterbird.desktop
      sed "s|${betterbirdBase}/bin/betterbird|$out/bin/betterbird|g" \
        ${betterbirdBase}/share/applications/betterbird.desktop \
        > $out/share/applications/betterbird.desktop
    '';
  };

  # Thunderbird/Betterbird add-ons, packaged from their published addons.thunderbird.net
  # XPIs (none are in nixpkgs/NUR). Home Manager's `extensions` option reads each
  # add-on from $out/share/mozilla/extensions/{ec8030f7-…}/<addonId>.xpi — the
  # same layout rycee's buildFirefoxXpiAddon emits. The {ec8030f7-…} GUID is the
  # app-extensions directory HM scans, NOT a per-add-on id; addonId must match the
  # XPI manifest's browser_specific_settings.gecko.id or the add-on won't load.
  buildTbAddon = {
    addonId,
    version,
    url,
    sha256,
  }:
    pkgs.stdenv.mkDerivation {
      pname = addonId;
      inherit version;
      src = pkgs.fetchurl {inherit url sha256;};
      preferLocalBuild = true;
      dontUnpack = true;
      installPhase = ''
        install -Dm444 "$src" \
          "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${addonId}.xpi"
      '';
    };

  # Pinned to the versions already in the profile (verified against ATN). tbkeys-lite
  # ships a vim keymap by default (j/k next/prev, r/a/f reply/replyall/forward,
  # # delete, x archive, c compose, o open); its keymap lives in WebExtension
  # storage, not a pref, so deeper remaps are a one-time step in the add-on options.
  tbExtensions = [
    (buildTbAddon {
      addonId = "tbkeys-lite@addons.thunderbird.net";
      version = "2.4.3";
      url = "https://addons.thunderbird.net/thunderbird/downloads/file/1044591/tbkeys_lite-2.4.3-tb.xpi";
      sha256 = "0l0n5a70a052alfxgmyw0fm5jizz007ir2228id750sfispgxka2";
    })
    (buildTbAddon {
      addonId = "mailmindr@arndissler.net";
      version = "1.7.1";
      url = "https://addons.thunderbird.net/thunderbird/downloads/file/1031426/mailmindr-1.7.1-tb.xpi";
      sha256 = "16660j77d3pqlv8bi845b5fsnga8v781rd5dkx95j0iq27g6qwyr";
    })
    (buildTbAddon {
      addonId = "markdown-here-revival@xul.calypsoblue.org";
      version = "4.0.9.1";
      url = "https://addons.thunderbird.net/thunderbird/downloads/file/1044024/markdown_here_revival-4.0.9.1-tb.xpi";
      sha256 = "17iy2c81pccbzcz572f84w7rz54zqh8ikn8gj662h9n370kakyv6";
    })
    (buildTbAddon {
      addonId = "nostalgy@opto.one";
      version = "5.0.3";
      url = "https://addons.thunderbird.net/thunderbird/downloads/file/1043785/nostalgy_emails_verwalten_suchen_archivieren-5.0.3-tb.xpi";
      sha256 = "0y63dgcgff6ilqnf287psbkf4zwjqf76xy9hr0yvw06fic8h6iy6";
    })
  ];
in {
  programs.thunderbird = {
    enable = true;
    profiles = {
      matth = {
        isDefault = true;
        extensions = tbExtensions;
        settings = {
          # Scale the entire UI 25% larger (1.0 = default).
          "layout.css.devPixelsPerPx" = "1.25";
          # Auto-enable the declaratively-installed add-ons. HM links the XPIs into
          # the profile read-only; without this Betterbird leaves them disabled
          # pending a manual per-add-on click. 0 = enable in all install scopes.
          "extensions.autoDisableScopes" = 0;
          "network.dns.disableIPv6" = true;
          "mailnews.sendInBackground" = true;
          "mailnews.sendInBackground.DelayMinutes" = 0;
          # Pin OAuth2 (=10) on the handzelmatthew Gmail servers. Without
          # this, BB sometimes resets authMethod to 3 (cleartext password)
          # which Gmail rejects, triggering an endless password-prompt loop
          # even though valid OAuth tokens are stored in logins.json.
          "mail.server.server1.authMethod" = 10;
          "mail.server.server2.authMethod" = 10;
          "mail.smtpserver.smtp1.authMethod" = 10;
          "mail.smtpserver.smtp2.authMethod" = 10;
        };
      };
    };
  };

  home.packages = [betterbird];

  # Betterbird looks at ~/.betterbird/ by default. Symlink it to the existing
  # ~/.thunderbird/ profile dir so BB and TB share accounts, extensions, mail
  # store. Use activation rather than home.file so Mozilla can still
  # read/write installs.ini itself when launching.
  # The wrapper passes -P matth on every launch, so installs.ini binding is
  # irrelevant — only the ~/.betterbird → ~/.thunderbird symlink matters.
  home.activation.betterbirdShareProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -L "$HOME/.betterbird" ] || [ "$(readlink "$HOME/.betterbird")" != ".thunderbird" ]; then
      rm -rf "$HOME/.betterbird"
      ln -s .thunderbird "$HOME/.betterbird"
    fi
  '';
}
