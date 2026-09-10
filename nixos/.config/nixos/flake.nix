{
  description = "Matt's nixos configuration (based off FrostPhoenix)";

  inputs = {
    whisper-overlay.url = "github:oddlama/whisper-overlay";
    whisper-overlay.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    # Readest only. The main pin (nixos-unstable-small) sits at readest 0.9.100
    # from Feb 2026, and "actively developed" is the entire reason readest beats
    # foliate (foliate's last release is 3.3.0, Apr 2025). Taking just this one
    # package from a newer tree keeps the main pin — and every other package —
    # untouched. See modules/core/overlays/readest.nix.
    #
    # This pulls a second ~250MB nixpkgs, kept as its own input so the main
    # pin — and every other package — stays untouched.
    nixpkgs-readest.url = "github:NixOS/nixpkgs/f13ff45afd1bb73e640eaa08a7066dbed07e3238";

    nur.url = "github:nix-community/NUR";

    hypr-contrib.url = "github:hyprwm/contrib";
    hyprpicker.url = "github:hyprwm/hyprpicker";

    alejandra.url = "github:kamadorueda/alejandra/3.0.0";

    # Pinned ahead of nixpkgs deliberately. nixpkgs ships 0.19.7, but every
    # Vicinae store extension except silverbullet declares "@vicinae/api":
    # "^0.22.2", so extensions simply will not load on the nixpkgs version.
    # Upstream also exposes an overlay + home-manager module + an extension
    # builder lib, which is what makes declaring extensions possible at all.
    vicinae = {
      url = "github:vicinaehq/vicinae/v0.23.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gaming.url = "github:fufexan/nix-gaming";
    # notion-repackaged = {
    #   url = "github:MattHandzel/nix-notion-repackaged/master";
    #
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # hyprland = {
    #   type = "git";
    #   url = "https://github.com/hyprwm/Hyprland";
    #   submodules = true;
    # };

    # hyprsession.url = "github:joshurtree/hyprsession";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TOOD: I could remove these?
    # catppuccin-bat = {
    #   url = "github:catppuccin/bat";
    #   flake = false;
    # };
    # catppuccin-cava = {
    #   url = "github:catppuccin/cava/6ec25ba688e30f3e5d6004ef6a295e6ba90c64d4";
    #   flake = false;
    # };

    spicetify-nix.url = "github:gerg-l/spicetify-nix";
    spicetify-nix.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    # lifelog = {
    #   url = "github:MattHandzel/lifelog";
    #   flake = true;
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    second-brain-search = {
      url = "path:/home/matth/Projects/SecondBrainSearch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    text-to-speech-service = {
      url = "path:/home/matth/Projects/SecondBrainSpeech";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    project-asset-generator-src = {
      url = "path:/home/matth/Projects/project-asset-generator";
      flake = false;
    };

    # Real remote (git@github.com:MattHandzel/gdoc-sync.git), not a `path:` input,
    # so the flake evaluates on a machine that is not this laptop. The other three
    # project inputs still need their GitHub repos created — see
    # docs/mac-migration/TODO-path-inputs.md for the exact remaining diff.
    gdoc-sync-src = {
      url = "git+ssh://git@github.com/MattHandzel/gdoc-sync?ref=main";
      flake = false;
    };

    betterbird = {
      url = "github:Heehaaw/betterbird-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland-native ActivityWatch window watcher — reports real window titles
    # via the Hyprland IPC socket. The generic aw-watcher-window logs "unknown"
    # on Hyprland (no wlr-foreign-toplevel title). Not in nixpkgs; upstream
    # ships a clean Rust flake. Consumed by modules/home/activitywatch.nix.
    aw-watcher-window-hyprland = {
      url = "github:bobvanderlinden/aw-watcher-window-hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ── macOS (darwinConfigurations.matts-mac) ──────────────────────────────
    #
    # A SECOND nixpkgs on purpose. The main pin is `nixos-unstable-small`, a
    # Linux-only jobset: cache.nixos.org has essentially no aarch64-darwin
    # binaries for it, so a Mac built against it compiles texlive/neovim/etc
    # from source on first switch. `nixpkgs-unstable` is the channel whose
    # darwin jobset IS built, so the Mac downloads instead of compiling. The
    # Linux hosts never see this input.
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # A SECOND home-manager, following nixpkgs-darwin.
    #
    # `home-manager` above follows the main `nixpkgs` pin and is locked to a
    # revision of the same era. Pointing that same locked home-manager at a much
    # newer nixpkgs (which nixpkgs-unstable is) breaks on any module whose
    # options are defined half in home-manager and half in nixpkgs — the neovim
    # plugin submodule is the one that fails first ("option
    # plugins.[...].runtime does not exist"). Keeping the pair matched on each
    # platform is the supported combination; the Linux hosts are untouched.
    home-manager-darwin = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # Declarative Homebrew prefix + pinned taps. Casks are the only sane way to
    # get the notarized, auto-updating GUI apps (Zen, Slack, Raycast, …) that
    # nixpkgs either does not package for darwin or packages unusably.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Taps are pinned as flake inputs so `mutableTaps = false` can point at
    # them; without this the tap contents are whatever `brew update` last
    # fetched, which is the opposite of reproducible.
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    # AeroSpace lives here, not in homebrew-cask.
    nikitabobko-tap = {
      url = "github:nikitabobko/homebrew-tap";
      flake = false;
    };
    # JankyBorders (the focused-window border that replaces Hyprland's).
    felixkratz-tap = {
      url = "github:FelixKratz/homebrew-formulae";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    self,
    home-manager,
    ...
  } @ inputs: let
    username = "matth";
    linuxSystem = "x86_64-linux";
    darwinSystem = "aarch64-darwin";

    sharedVariables = import ./shared_variables.nix;

    # One definition of the lint/format gate, instantiated per platform so
    # `nix flake check` means the same thing on the laptop and on the Mac.
    mkChecks = system: pkgs: {
      statix = pkgs.runCommand "statix" {
        nativeBuildInputs = [pkgs.statix];
      } "statix check ${self} || true && touch $out";

      deadnix = pkgs.runCommand "deadnix" {
        nativeBuildInputs = [pkgs.deadnix];
      } "deadnix ${self} && touch $out";

      format = pkgs.runCommand "alejandra-check" {
        nativeBuildInputs = [inputs.alejandra.packages.${system}.default];
      } "alejandra --check ${self} && touch $out";
    };
  in {
    # nixpkgs = {
    #   overlay = final: prev: {
    #     nixpkgs.config.permittedInsecurePackages = [
    #       "electron-28.3.3"
    #       "electron-30.5.1"
    #     ];
    #   };
    # };

    # packages.x86_64-linux = notion-repackaged.packages.${system}.default;

    nixosConfigurations = {
      desktop = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        modules = [(import ./hosts/desktop)];
        specialArgs = {
          host = "desktop";
          inherit self inputs username sharedVariables;
        };
      };
      server = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        modules = [(import ./hosts/server)];
        specialArgs = {
          host = "server";
          inherit self inputs username sharedVariables;
        };
      };
      laptop = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        modules = [
          (import ./hosts/laptop)
        ];
        specialArgs = {
          host = "laptop";
          inherit self inputs username sharedVariables;
        };
      };
      vm = nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        modules = [(import ./hosts/vm)];
        specialArgs = {
          host = "vm";
          inherit self inputs username sharedVariables;
        };
      };
    };

    # The Mac. `host = "mac"` (short, like the NixOS hosts) because
    # modules/home/{tmux,zsh}.nix already branch on `host`.
    darwinConfigurations.matts-mac = inputs.nix-darwin.lib.darwinSystem {
      modules = [(import ./hosts/mac)];
      specialArgs = {
        host = "mac";
        inherit self inputs username sharedVariables;
      };
    };

    checks = {
      ${linuxSystem} = mkChecks linuxSystem nixpkgs.legacyPackages.${linuxSystem};
      ${darwinSystem} = mkChecks darwinSystem inputs.nixpkgs-darwin.legacyPackages.${darwinSystem};
    };
  };
}
