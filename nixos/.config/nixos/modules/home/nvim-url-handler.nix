# nvim-url-handler.nix — laptop-side handler for the `nvim://` URL scheme (MAT-565).
#
# WHY THIS EXISTS
# The tailnet file server (filesystem.matthandzel.com, see
# modules/core/filesystem-server.nix) renders an "✎ Edit in nvim" link on every
# file it shows, e.g.:
#
#     nvim://matts-server/home/matth/Obsidian/Main/My Note.md
#
# Clicking it must open that exact file in nvim ON THIS LAPTOP. A browser can only
# hand a clicked *custom-scheme* URL to a program if that scheme is registered as an
# xdg desktop handler — there is no other way to bridge "clicked a web link" to
# "launch a local editor". So this module:
#   1. ships `nvim-open`, a tiny dispatcher script, and
#   2. registers a hidden .desktop entry as the default app for x-scheme-handler/nvim
#      (the actual `defaultApplications` line is in modules/home/default.nix, which
#      already owns the single xdg.mimeApps.defaultApplications attrset).
#
# THE FILE LIVES ON THE SERVER — two cases, auto-detected at click time:
#   • The path ALSO exists locally (the Obsidian vault is syncthing-synced to the
#     laptop) → open the LOCAL copy: instant, works offline, and syncthing
#     propagates the edit back to the server.
#   • Otherwise (e.g. ~/Projects code, which isn't synced) → open the canonical file
#     on the server over SSH: `ssh -t matts-server nvim <path>`.
# Either way nvim opens inside a fresh kitty window (Matt's terminal).
#
# nvim itself is intentionally NOT in runtimeInputs: it must be the plugin-rich
# home-manager neovim (programs.neovim), which is on the session PATH that kitty
# inherits — not a bare pkgs.neovim.
{ pkgs, ... }:
let
  server = "matts-server"; # tailnet host that owns the files (fallback if the URL omits a host)
  nvim-open = pkgs.writeShellApplication {
    name = "nvim-open";
    runtimeInputs = [ pkgs.kitty pkgs.openssh pkgs.coreutils ];
    text = ''
      # $1 is e.g.  nvim://matts-server/home/matth/Obsidian/Main/My Note.md
      url="''${1:-}"
      if [ -z "$url" ]; then
        echo "nvim-open: no nvim:// URL given" >&2
        exit 64
      fi

      rest="''${url#nvim://}"   # matts-server/home/matth/...
      host="''${rest%%/*}"      # matts-server
      path="/''${rest#*/}"      # /home/matth/...
      [ -n "$host" ] || host="${server}"

      # percent-decode (the server encodes with encodeURI: spaces -> %20, etc.)
      path="$(printf '%b' "''${path//%/\\x}")"

      if [ -f "$path" ]; then
        # local (syncthing) copy present — edit it directly
        exec kitty --class nvim-open nvim "$path"
      else
        # not local — edit the canonical file on the server over SSH.
        # %q-quote the path so the remote shell re-parses spaces/specials correctly.
        printf -v q '%q' "$path"
        exec kitty --class nvim-open ssh -t "$host" "nvim $q"
      fi
    '';
  };
in
{
  home.packages = [ nvim-open ];

  # A protocol handler, not an app-menu entry (noDisplay). default.nix wires it up as
  # the default for x-scheme-handler/nvim.
  xdg.desktopEntries.nvim-open = {
    name = "Open in Neovim (nvim:// handler)";
    genericName = "Text Editor";
    exec = "nvim-open %u";
    terminal = false;
    type = "Application";
    mimeType = [ "x-scheme-handler/nvim" ];
    noDisplay = true;
  };
}
