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
# The default-app BINDING is a separate, user-consented step that macOS gates
# behind a confirmation dialog ("Do you want all documents with the extension
# .md to open with Neovim?"). It cannot be set from a config file. It was
# accepted once on 2026-09-10; if it ever resets, re-run:
#   /Users/matth/migration/setdefaults /Applications/Neovim.app type:net.daringfireball.markdown
# and click "Use Neovim".
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
  system.activationScripts.neovimDroplet.text = ''
    APP=/Applications/Neovim.app
    PB=/usr/libexec/PlistBuddy
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

    rm -rf "$APP"
    /usr/bin/osacompile -o "$APP" ${droplet}

    P="$APP/Contents/Info.plist"
    "$PB" -c "Set :CFBundleIdentifier com.matth.neovim" "$P" 2>/dev/null \
      || "$PB" -c "Add :CFBundleIdentifier string com.matth.neovim" "$P"
    "$PB" -c "Set :CFBundleName Neovim" "$P" 2>/dev/null \
      || "$PB" -c "Add :CFBundleName string Neovim" "$P"
    "$PB" -c "Add :CFBundleDisplayName string Neovim" "$P" 2>/dev/null || true

    # Markdown only, on purpose. Widening this to public.plain-text would make
    # Neovim the handler for every .txt/.log/.csv on the machine.
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

    # Ad-hoc signature: unsigned bundles get a fresh identity on every rebuild,
    # which would drop any TCC grant the bundle picks up later.
    /usr/bin/codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
    "$LSREG" -f "$APP" || true
  '';
}
