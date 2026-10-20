# "Open in Neovim" as a real macOS default-application.
#
# LaunchServices will only ever hand a document to an APP BUNDLE. `nvim` is a
# plain binary, so it can never be a default handler on its own, and neither can
# kitty (kitty opens a terminal, not the file you double-clicked). This module
# generates a one-purpose bundle that adapts between the two: it receives the
# `odoc` AppleEvent and runs `nvim <file>` inside a kitty window.
#
# Why generated at activation instead of built in Nix: the only tool that can
# compile an AppleScript droplet is /usr/bin/osacompile, which lives outside the
# store and cannot be used inside a sandboxed derivation. The SOURCE is
# declarative (below); the compile step is idempotent and re-runs on every
# switch, so the bundle always matches this file.
#
# postActivation, not a custom `neovimDroplet` name: nix-darwin silently ignores
# activationScripts entries it does not know, so from the day this module was
# written until 2026-09-20 it never ran even once and the bundle on disk was the
# hand-made 2026-09-10 one. Same trap as dia-policy.nix and system-defaults.nix.
#
# The default-app BINDING is set with `duti` below rather than through Finder's
# "Do you want all documents with the extension .md to open with Neovim?" sheet,
# which cannot be answered from a config file. duti writes the same
# com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers entry the
# sheet would, so the binding survives a reboot and is re-asserted every switch.
{
  pkgs,
  username,
  ...
}: let
  nvimBin = "/etc/profiles/per-user/${username}/bin/nvim";

  droplet = pkgs.writeText "neovim-droplet.applescript" ''
    on open theFiles
        repeat with f in theFiles
            set p to POSIX path of (f as text)
            do shell script "/usr/bin/open -na /Applications/kitty.app --args --single-instance --instance-group=nvim --directory " & quoted form of (do shell script "dirname " & quoted form of p) & " -e ${nvimBin} " & quoted form of p
        end repeat
    end open

    on run
        do shell script "/usr/bin/open -na /Applications/kitty.app --args --single-instance --instance-group=nvim -e ${nvimBin}"
    end run
  '';
in {
  system.activationScripts.postActivation.text = ''
    APP=/Applications/Neovim.app
    PB=/usr/libexec/PlistBuddy
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    DUTI=/opt/homebrew/bin/duti

    # Compile to a staging path and swap in. A bare `rm -rf "$APP"` followed by a
    # failing osacompile would leave the machine with no Neovim handler at all.
    STAGE=$(/usr/bin/mktemp -d /tmp/neovim-droplet.XXXXXX)
    if /usr/bin/osacompile -o "$STAGE/Neovim.app" ${droplet}; then
      P="$STAGE/Neovim.app/Contents/Info.plist"
      "$PB" -c "Set :CFBundleIdentifier com.matth.neovim" "$P" 2>/dev/null \
        || "$PB" -c "Add :CFBundleIdentifier string com.matth.neovim" "$P"
      "$PB" -c "Set :CFBundleName Neovim" "$P" 2>/dev/null \
        || "$PB" -c "Add :CFBundleName string Neovim" "$P"
      "$PB" -c "Add :CFBundleDisplayName string Neovim" "$P" 2>/dev/null || true

      # Named types only, on purpose. Widening this to public.plain-text would
      # make Neovim the handler for every .txt/.log/.json on the machine.
      "$PB" -c "Delete :CFBundleDocumentTypes" "$P" 2>/dev/null || true
      "$PB" -c "Add :CFBundleDocumentTypes array" "$P"

      "$PB" -c "Add :CFBundleDocumentTypes:0 dict" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Markdown document" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string net.daringfireball.markdown" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string md" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string markdown" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:2 string mdx" "$P"

      # 2026-09-20: .csv was bound to Claude.app, and Finder's "Open With >
      # Other…" panel greys out any app that does not DECLARE the type, so there
      # was no way to reach nvim from Finder at all.
      "$PB" -c "Add :CFBundleDocumentTypes:1 dict" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeName string Comma-separated values" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeRole string Editor" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:LSHandlerRank string Alternate" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes:0 string public.comma-separated-values-text" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeExtensions array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeExtensions:0 string csv" "$P"

      # Ad-hoc signature: unsigned bundles get a fresh identity on every rebuild,
      # which would drop any TCC grant the bundle picks up later.
      /usr/bin/codesign --force --deep -s - "$STAGE/Neovim.app" >/dev/null 2>&1 || true

      rm -rf "$APP"
      /bin/mv "$STAGE/Neovim.app" "$APP"
      /usr/sbin/chown -R ${username} "$APP" || true
      "$LSREG" -f "$APP" || true
    else
      echo "open-with-nvim: osacompile failed, keeping the existing $APP" >&2
    fi
    rm -rf "$STAGE"

    # As ${username}: LSHandlers live in the USER's LaunchServices prefs, and
    # activation runs as root.
    # `sudo -u` alone talks to root's cfprefsd; `launchctl asuser` puts the call
    # in ${username}'s GUI session so it reaches the same prefs Finder reads.
    UID_M=$(/usr/bin/id -u ${username})
    if [ -x "$DUTI" ] && [ -n "$UID_M" ]; then
      /bin/launchctl asuser "$UID_M" /usr/bin/sudo -u ${username} \
        "$DUTI" -s com.matth.neovim public.comma-separated-values-text all || true
      /bin/launchctl asuser "$UID_M" /usr/bin/sudo -u ${username} \
        "$DUTI" -s com.matth.neovim net.daringfireball.markdown all || true
    fi
  '';
}
