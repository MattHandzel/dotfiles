{
  pkgs,
  lib,
  ...
}: {
  programs.dconf.enable = true;
  programs.zsh.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
  ];

  # Superhuman ships no Linux client, and mail.superhuman.com is NOT a standalone
  # web app — it is an empty host page that the extension injects the real client
  # into. Verified in the CRX manifest (2026-08-05):
  #
  #   content_scripts = [{ matches: ["https://mail.superhuman.com/**"],
  #                        js: ["pages/index.js"], run_at: "document_start" }]
  #
  # Without the extension the `superhuman` launcher opens a window that sets its
  # title and renders nothing else — which is exactly what it did.
  #
  # Installed by policy rather than by hand so it survives a wiped profile and
  # covers the ~/.config/chromium-app user-data-dir the launcher uses; Chromium
  # policies are machine-wide, not per-profile.
  programs.chromium = {
    enable = true;
    extensions = ["dcgcnpooblobhncpnddnhoendgbnglpn"]; # Superhuman Mail
  };
}
