# Stop macOS from relaunching every app that was open at the last shutdown.
#
# THE BUG THIS FIXES (2026-09-12): after a reboot, Discord, Superhuman, Zoom,
# Chrome, Anki, Linear, Obsidian, Spotify, TextEdit, Terminal … all came back,
# even though Login Items held only Slack / Wispr Flow / Raycast / AeroSpace and
# `TALLogoutSavesState` was already false. The unified log named the culprit:
#
#   loginwindow [TAL] PersistentAppsSupport persistentAppPreLaunch |
#       Launching:/Applications/Discord.app … previouslyRunningApps count:20
#
# TAL is "Reopen windows when logging back in". loginwindow keeps a snapshot of
# the running apps in
#   ~/Library/Group Containers/group.com.apple.loginwindow.persistent-apps/persistantApps
# and rewrites it a few seconds after every app launch. The TALLogoutSavesState
# preference is only consulted on a loginwindow-driven logout (Apple menu,
# `tell application "System Events" to restart`). Matt reboots with
# `sudo reboot` from a kitty shell, which kills loginwindow without a logout,
# so the last snapshot survives and is replayed wholesale at the next login.
#
# Two layers, both idempotent, both re-applied on every home-manager switch:
#
#   1. The two resume preferences, in the per-user domain AND the -currentHost
#      (ByHost) domain. nix-darwin's CustomUserPreferences can only write the
#      former; system-defaults.nix still carries that copy.
#   2. The snapshot file is emptied and made immutable (chflags uchg). Verified
#      live: loginwindow's periodic write then fails silently — it logs
#      "Writing dictionary to prefs" and the file stays empty, no error, no
#      crash — so the list loginwindow reads at the next login is always empty
#      no matter how the machine went down.
#
# Login-time apps are declared in login-items.nix (Beeper, Hammerspoon) and the
# macOS Login Items list (Slack, Wispr Flow, Raycast, AeroSpace). Nothing else
# should start on its own; if something does, `sudo reboot` is no longer the
# explanation.
#
# To undo: chflags nouchg "$snapshot" and delete this module.
{lib, ...}: {
  home.activation.disableAppResume = lib.hm.dag.entryAfter ["writeBoundary"] ''
    snapshot="$HOME/Library/Group Containers/group.com.apple.loginwindow.persistent-apps/persistantApps"

    for dom in "" "-currentHost"; do
      $DRY_RUN_CMD /usr/bin/defaults $dom write com.apple.loginwindow TALLogoutSavesState -bool false
      $DRY_RUN_CMD /usr/bin/defaults $dom write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false
    done

    if [ -z "''${DRY_RUN:-}" ]; then
      /bin/mkdir -p "$(/usr/bin/dirname "$snapshot")"
      /usr/bin/chflags nouchg "$snapshot" 2>/dev/null || true
      /bin/cat > "$snapshot" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PersistentApps</key>
	<array/>
</dict>
</plist>
PLIST
      /usr/bin/chflags uchg "$snapshot"
    fi
  '';
}
