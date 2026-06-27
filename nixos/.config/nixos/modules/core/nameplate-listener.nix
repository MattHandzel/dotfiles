{pkgs, ...}: let
  # render.py needs Pillow + qrcode. Provide them via a pinned python env so the script does
  # NOT re-exec itself under nix-shell per message (which would add seconds of latency to every
  # render and miss the "badge updates within ~5s" bar). NAMEPLATE_NO_NIXSHELL=1 (below) makes
  # render.py trust this interpreter's PIL instead of relaunching.
  pyEnv = pkgs.python3.withPackages (ps: [ps.pillow ps.qrcode]);

  # DejaVu Sans Bold for the renderer. render.py's pinned store path is host-specific and is
  # often absent here; without a fast hit it falls back to globbing all of /nix/store (minutes
  # per render). NAMEPLATE_FONT points it straight at this font (MAT-1198).
  dejavuBold = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf";

  # The pipeline scripts live in the Syncthing-synced vault (shipped by MAT-1113 + this issue),
  # NOT in the nix store — so they update without a rebuild. listen.sh drives generate.py|render.py.
  listenScript = "/home/matth/Obsidian/Main/scripts/nameplate/listen.sh";
in {
  # World-readable publish dir nginx serves and the listener writes to (atomic temp+rename).
  systemd.tmpfiles.rules = [
    "d /var/www/nameplate 0755 matth users - -"
  ];

  systemd.services.nameplate-listener = {
    description = "Listen on the ntfy 'nameplate' topic -> generate+render a 296x128 badge -> publish to /var/www/nameplate";
    after = ["network.target" "ntfy-sh.service"];
    wantedBy = ["multi-user.target"];
    # generate.py shells out to the local `claude` CLI (resolved via HOME=~/.npm-global/bin);
    # render.py uses pyEnv's python3. curl/jq/coreutils are used by listen.sh itself.
    path = [pyEnv pkgs.bash pkgs.coreutils pkgs.curl pkgs.jq];
    environment = {
      HOME = "/home/matth";
      NAMEPLATE_NO_NIXSHELL = "1";
      NAMEPLATE_FONT = dejavuBold;
      NAMEPLATE_WEBROOT = "/var/www/nameplate";
    };
    serviceConfig = {
      Type = "simple";
      User = "matth";
      Restart = "always";
      RestartSec = 10;
      ExecStart = "${pkgs.bash}/bin/bash ${listenScript}";
    };
  };
}
