# nix-darwin module: Chrome auto-installs the Bitwarden extension, so passkey
# prompts (navigator.credentials) go to Bitwarden instead of Chrome's own
# "iCloud Keychain / Use a phone or tablet" sheet. Bitwarden.app from the
# Homebrew cask ships no macOS credential-provider extension (only
# safari.appex), so the extension is the only way Chrome can reach the vault.
# The Calendar/Superhuman/claude.ai app windows use their own profile
# (--user-data-dir ~/.config/chromium-app), which starts with no extensions;
# a machine-wide policy covers it and Chrome's Default profile alike
# (Oops run 20260914-095413). Same mechanism and caveats as dia-policy.nix.
{
  pkgs,
  lib,
  ...
}: let
  plist = pkgs.writeText "com.google.Chrome.plist" (lib.generators.toPlist {escape = true;} {
    ExtensionSettings = {
      nngceckbapebfimnlniiiahkandclblb = {
        installation_mode = "normal_installed";
        update_url = "https://clients2.google.com/service/update2/crx";
      };
    };
  });
  install = pkgs.writeShellScript "chrome-policy-install" ''
    dst="/Library/Managed Preferences/com.google.Chrome.plist"
    /usr/bin/cmp -s ${plist} "$dst" && exit 0
    /bin/mkdir -p "/Library/Managed Preferences"
    /bin/cp ${plist} "$dst"
    /usr/sbin/chown root:wheel "$dst"
    /bin/chmod 644 "$dst"
    /usr/bin/killall cfprefsd 2>/dev/null || true
  '';
in {
  system.activationScripts.postActivation.text = ''
    ${install}
  '';

  # The boot-time wipe of /Library/Managed Preferences hits this plist too;
  # see launchd.daemons.dia-policy in dia-policy.nix.
  launchd.daemons.chrome-policy = {
    command = "${install}"; # nix-darwin wraps it in wait4path /nix/store
    serviceConfig = {
      RunAtLoad = true;
      WatchPaths = ["/Library/Managed Preferences"];
      StartInterval = 300;
    };
  };
}
