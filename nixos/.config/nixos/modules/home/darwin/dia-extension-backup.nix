# Home-manager module: a daily copy of Dia's per-extension storage.
#
# When Dia starts without the ExtensionSettings policy it treats every
# policy-installed extension as an orphaned external extension and uninstalls
# it, DELETING its local storage with it — which is where extension logins
# live. That is how Matt lost every extension session on 2026-09-19 (Oops run
# 20260919-105936: the reboot wiped /Library/Managed Preferences, see
# modules/darwin/dia-policy.nix, which now keeps the policy in place).
#
# The policy is the fix; this is the net under it. A dated copy of each
# profile's extension storage means the worst case is a restore, not another
# round of signing in to everything.
{
  config,
  pkgs,
  ...
}: let
  backup = pkgs.writeShellScript "dia-extension-backup" ''
    set -u
    src="$HOME/Library/Application Support/Dia/User Data"
    dst="$HOME/Backups/dia-extension-data/$(/bin/date +%Y-%m-%d)"
    [ -d "$src" ] || exit 0
    for profile in "Default" "Profile 1" "Profile 2"; do
      [ -d "$src/$profile" ] || continue
      /bin/mkdir -p "$dst/$profile"
      for dir in "Local Extension Settings" "Sync Extension Settings" "Extension State" "Extension Rules" "Extension Scripts"; do
        [ -e "$src/$profile/$dir" ] && /bin/cp -Rp "$src/$profile/$dir" "$dst/$profile/" || true
      done
    done
    # Keep the 7 most recent days.
    cd "$HOME/Backups/dia-extension-data" || exit 0
    /bin/ls -1d 20* 2>/dev/null | /usr/bin/sort -r | /usr/bin/tail -n +8 | while read -r old; do
      /bin/rm -rf "$old"
    done
  '';
in {
  launchd.agents.dia-extension-backup = {
    enable = true;
    config = {
      ProgramArguments = ["/bin/sh" "-c" "/bin/wait4path /nix/store && exec ${backup}"];
      RunAtLoad = true;
      StartCalendarInterval = [
        {
          Hour = 12;
          Minute = 30;
        }
      ];
      StandardOutPath = "${config.home.homeDirectory}/.local/state/dia-extension-backup.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/dia-extension-backup.log";
    };
  };
}
