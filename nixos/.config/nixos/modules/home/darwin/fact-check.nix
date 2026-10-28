# fetch-text: print a web page's real text (curl -> trafilatura main text, headless Chrome for JS-only
# or bot-blocked pages), so the fact-checker and research agents quote the page, not WebFetch's model
# summary of it. AI tips radar tip:34959a3b (2026-W44).
#
# The script is referenced by its vault path, so edits take effect without a rebuild; the flake only
# supplies the Python that has trafilatura. Chrome is the installed Google Chrome, run headless in a
# throwaway profile. Code: ~/Obsidian/Main/scripts/fact-check/fetch-text. Doc: areas/second-brain/fact-check.md
{
  config,
  pkgs,
  ...
}: let
  script = "${config.home.homeDirectory}/Obsidian/Main/scripts/fact-check/fetch-text";
  python = pkgs.python3.withPackages (ps: [ps.trafilatura]);
in {
  home.packages = [
    (pkgs.writeShellScriptBin "fetch-text" ''
      export PATH="$PATH:${pkgs.curl}/bin:${pkgs.poppler-utils}/bin"
      exec ${python}/bin/python3 -I ${script} "$@"
    '')
  ];
}
