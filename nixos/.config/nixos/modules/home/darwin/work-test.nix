# Work Test: the daily work test as an app (clocks, answers, a Claude session
# per task, times from the calendar). Doc: areas/second-brain/work-test-viewer.md
#
# Serves ~/Obsidian/Main/scripts/work-test on 127.0.0.1:8772 from a launchd
# agent, so it is up after login with nothing to start. The window is
# Work Test.app (work-test-app/WorkTest.swift, a WKWebView shell), compiled at
# activation into ~/Applications/Work Test.app so Raycast and Spotlight list it.
# Matt asked on 2026-10-06 for "an actual application, or ... a script ... that
# I can run with Raycast that opens it up". `worktest.py open [date]` opens the
# app at that day through its worktest:// URL scheme.
#
# Same arrangement as message-triage.nix (Triage.app), including why the app is
# compiled at activation instead of in a derivation: the only Swift toolchain
# with the macOS 26 SDK is /usr/bin/swiftc from the Command Line Tools.
{
  pkgs,
  lib,
  ...
}: let
  dir = "/Users/matth/Obsidian/Main/scripts/work-test";
  appSrc = ./work-test-app;
  # The server is stdlib-only Python. It starts `claude --bg` sessions, opens
  # kitty, and runs tmux and nvim, so it needs Matt's PATH, not launchd's.
  serve = pkgs.writeShellApplication {
    name = "work-test-serve";
    text = ''
      export PATH="$HOME/.local/bin:/etc/profiles/per-user/matth/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin"
      export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" # the calendar reader
      if [ ! -f "${dir}/worktest.py" ]; then
        echo "$(date -u +%FT%TZ) no ${dir}/worktest.py yet (vault not synced?)" >&2
        sleep 300 # KeepAlive would otherwise respawn this every 10 s
        exit 1
      fi
      # A server started by hand (`worktest.py open` before this agent existed)
      # may hold the port. Wait for it to go away instead of failing to bind.
      while /usr/bin/nc -z 127.0.0.1 8772 2>/dev/null; do sleep 30; done
      cd "${dir}/../.."
      exec ${pkgs.python3}/bin/python3 "${dir}/worktest.py" serve
    '';
  };
in {
  # Build ~/Applications/Work Test.app when its sources change (the store path
  # of appSrc changes with any of them). Compile into a staging dir and swap,
  # so a failed build keeps the last good app. A running Work Test keeps its
  # old binary until it is quit and reopened.
  home.activation.workTestApp = lib.hm.dag.entryAfter ["writeBoundary"] ''
    wt_app="$HOME/Applications/Work Test.app"
    wt_want="${appSrc}"
    wt_have=$(/bin/cat "$wt_app/Contents/Resources/nix-source" 2>/dev/null || true)
    if [ -n "''${DRY_RUN:-}" ]; then
      echo "work-test-app: would build $wt_app from $wt_want"
    elif [ "$wt_want" != "$wt_have" ] || [ ! -x "$wt_app/Contents/MacOS/WorkTest" ]; then
      if /usr/bin/xcode-select -p >/dev/null 2>&1; then
        stage=$(/usr/bin/mktemp -d "''${TMPDIR:-/tmp}/work-test-app.XXXXXX")
        /bin/mkdir -p "$stage/Work Test.app/Contents/MacOS" "$stage/Work Test.app/Contents/Resources"
        if /usr/bin/swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
             -framework AppKit -framework WebKit -framework UserNotifications \
             -o "$stage/Work Test.app/Contents/MacOS/WorkTest" "$wt_want/WorkTest.swift"; then
          /bin/cp "$wt_want/Info.plist" "$stage/Work Test.app/Contents/Info.plist"
          /bin/cp "$wt_want/WorkTest.icns" "$stage/Work Test.app/Contents/Resources/WorkTest.icns"
          echo "$wt_want" > "$stage/Work Test.app/Contents/Resources/nix-source"
          /bin/chmod -R u+w "$stage/Work Test.app"
          # Ad-hoc signature: a stable identity for the notification permission.
          /usr/bin/codesign --force --deep -s - "$stage/Work Test.app" >/dev/null 2>&1 || true
          /bin/mkdir -p "$HOME/Applications"
          /bin/rm -rf "$wt_app"
          /bin/mv "$stage/Work Test.app" "$wt_app"
          /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -f "$wt_app" || true
          echo "work-test-app: built $wt_app"
        else
          echo "work-test-app: swiftc failed, keeping the existing $wt_app" >&2
        fi
        /bin/rm -rf "$stage"
      else
        echo "work-test-app: no Command Line Tools (xcode-select --install), Work Test.app not built" >&2
      fi
    fi
  '';

  launchd.agents.work-test = {
    enable = true;
    config = {
      ProgramArguments = ["${serve}/bin/work-test-serve"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/matth/Library/Logs/work-test.log";
      StandardErrorPath = "/Users/matth/Library/Logs/work-test.log";
    };
  };
}
