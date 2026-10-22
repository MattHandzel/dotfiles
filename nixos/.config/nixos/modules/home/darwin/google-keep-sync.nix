# google-keep-sync: every 30 minutes, mirror Google Keep into the vault (capture/google_keep/, one file per note,
# keyed by Keep id so edits update in place; pointer notes such as Gym Logs go to fixed files). Built for MAT-630 on
# the NixOS server but never authed or scheduled; moved to the Mac 2026-10-22. Matt, 2026-10-22: "automatically
# synchronize my Google Keep notes ... conversations with people while I was in DC that talked about Uplift".
#
# gkeepapi is not in nixpkgs, so it is built from its PyPI wheel here. `google-keep-sync` points run.sh at this
# Python (GOOGLE_KEEP_PYTHON) instead of its old pip-venv bootstrap. Auth is a one-time master token:
# `google-keep-sync token --oauth-token '<oauth2_4/...>'` writes GOOGLE_KEEP_MASTER_TOKEN into the vault .env.
# The script is referenced by its vault path, so edits apply on the next tick without a rebuild.
# Code: ~/Obsidian/Main/scripts/google-keep/. Doc: areas/second-brain/google-keep-sync.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  py = pkgs.python3Packages;
  gkeepapi = py.buildPythonPackage rec {
    pname = "gkeepapi";
    version = "0.17.1";
    format = "wheel";
    src = py.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      sha256 = "8e242bc745640c809d21eb3f95c7182ac340a8cc2b84e5d78b9d692c2c2d35dc";
    };
    # Its metadata asks for `future`, which it never imports and which nixpkgs marks broken on Python 3.14.
    dependencies = [py.gpsoauth py.requests];
    pythonRemoveDeps = ["future"];
    pythonImportsCheck = ["gkeepapi"];
  };
  python = pkgs.python3.withPackages (_: [gkeepapi py.gpsoauth]);
  google-keep-sync = pkgs.writeShellScriptBin "google-keep-sync" ''
    export GOOGLE_KEEP_PYTHON=${python}/bin/python3
    exec ${pkgs.bash}/bin/bash ${home}/Obsidian/Main/scripts/google-keep/run.sh "$@"
  '';
  log = "${home}/.local/state/google-keep-sync/launchd.log";
in {
  home.packages = [google-keep-sync];

  launchd.agents.google-keep-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${google-keep-sync}/bin/google-keep-sync"];
      StartInterval = 1800;
      RunAtLoad = true;
      ProcessType = "Background";
      Nice = 10;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
