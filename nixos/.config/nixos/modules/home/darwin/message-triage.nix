# Message triage: a calmer front door to Beeper (Slack, Signal, WhatsApp, ...).
#
# Serves ~/Obsidian/Main/scripts/message-triage on 127.0.0.1:8771. It polls
# Beeper Desktop's local API, has Claude (the `claude` CLI) triage each chat
# into now / today / batch / fyi / ignore, drafts replies in Matt's voice,
# and only interrupts him (modal alert + sound) for "now". The UI opens on
# "Who are you here to message?", never on the inbox; the full owed list is a
# session inside a Messages window. The server also keeps /tmp/focus_mode on
# only inside Deep work blocks (config.json focus_titles), off in those windows. Built 2026-10-01 from the CFAR TAPs class, v2 2026-10-06.
#
# Beeper Desktop must be running (hidden is fine) for its local API; the UI
# has a "start Beeper hidden" button when it isn't.
#
# The UI is Triage.app (triage-app/Triage.swift, a WKWebView shell), compiled
# at activation into ~/Applications/Triage.app so Raycast and Spotlight list it
# (2026-10-06; it was a Chrome --app window before). `triage-app` opens it;
# Ctrl-Opt-H in aerospace.nix points at it and AeroSpace keeps it on its own
# `triage` workspace, which focus_gate.lua does not gate (the launcher is the
# gate). Ctrl-Opt-Shift-H is raw Beeper. The runtime is uv
# (`uv run --with beeper-desktop-api`), same arrangement as brain-search.nix.
# Doc: areas/second-brain/message-triage.md
#
# Why compiled at activation instead of in a derivation: the only Swift
# toolchain with the macOS 26 SDK is /usr/bin/swiftc from the Command Line
# Tools, outside the store (same reason open-with-nvim.nix uses osacompile).
# The sources are declarative; the build re-runs only when they change.
{
  pkgs,
  lib,
  ...
}: let
  dir = "/Users/matth/Obsidian/Main/scripts/message-triage";
  appSrc = ./triage-app;
  serve = pkgs.writeShellApplication {
    name = "message-triage-serve";
    runtimeInputs = [pkgs.uv];
    text = ''
      if [ ! -f "${dir}/triage_server.py" ]; then
        echo "$(date -u +%FT%TZ) no ${dir}/triage_server.py yet (vault not synced?)" >&2
        sleep 300 # KeepAlive would otherwise respawn this every 10 s
        exit 1
      fi
      export PATH="$HOME/.local/bin:$PATH" # the claude CLI
      exec "${dir}/run.sh"
    '';
  };
  app = pkgs.writeShellApplication {
    name = "triage-app";
    text = ''
      if [ -d "$HOME/Applications/Triage.app" ]; then
        exec open -a "$HOME/Applications/Triage.app"
      fi
      # Fallback until the first activation has built Triage.app.
      open -na "Google Chrome" --args --app="http://127.0.0.1:8771/" \
        --user-data-dir="$HOME/.config/chromium-app" --no-first-run --no-default-browser-check
      command -v aerospace >/dev/null || exit 0
      id=""
      for _ in $(seq 40); do
        id=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
          | awk -F'|' '$2 == "Google Chrome" && $3 ~ /^Triage/ {print $1; exit}')
        [[ -n "$id" ]] && break
        sleep 0.5
      done
      [[ -n "$id" ]] || exit 0
      aerospace layout --window-id "$id" tiling || true
      aerospace move-node-to-workspace --window-id "$id" triage || true
      aerospace workspace triage || true
      exec aerospace focus --window-id "$id"
    '';
  };
in {
  home.packages = [app];

  # Build ~/Applications/Triage.app when its sources change (the store path of
  # appSrc changes with any of them). Compile into a staging dir and swap, so a
  # failed build keeps the last good app. A running Triage keeps its old binary
  # until it is quit and reopened.
  home.activation.triageApp = lib.hm.dag.entryAfter ["writeBoundary"] ''
    triage_app="$HOME/Applications/Triage.app"
    triage_want="${appSrc}"
    triage_have=$(/bin/cat "$triage_app/Contents/Resources/nix-source" 2>/dev/null || true)
    if [ -n "''${DRY_RUN:-}" ]; then
      echo "triage-app: would build $triage_app from $triage_want"
    elif [ "$triage_want" != "$triage_have" ] || [ ! -x "$triage_app/Contents/MacOS/Triage" ]; then
      if /usr/bin/xcode-select -p >/dev/null 2>&1; then
        stage=$(/usr/bin/mktemp -d "''${TMPDIR:-/tmp}/triage-app.XXXXXX")
        /bin/mkdir -p "$stage/Triage.app/Contents/MacOS" "$stage/Triage.app/Contents/Resources"
        if /usr/bin/swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
             -framework AppKit -framework WebKit \
             -o "$stage/Triage.app/Contents/MacOS/Triage" "$triage_want/Triage.swift"; then
          /bin/cp "$triage_want/Info.plist" "$stage/Triage.app/Contents/Info.plist"
          /bin/cp "$triage_want/Triage.icns" "$stage/Triage.app/Contents/Resources/Triage.icns"
          echo "$triage_want" > "$stage/Triage.app/Contents/Resources/nix-source"
          /bin/chmod -R u+w "$stage/Triage.app"
          # Ad-hoc signature: a stable identity for any TCC grant it picks up.
          /usr/bin/codesign --force --deep -s - "$stage/Triage.app" >/dev/null 2>&1 || true
          /bin/mkdir -p "$HOME/Applications"
          /bin/rm -rf "$triage_app"
          /bin/mv "$stage/Triage.app" "$triage_app"
          /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -f "$triage_app" || true
          echo "triage-app: built $triage_app"
        else
          echo "triage-app: swiftc failed, keeping the existing $triage_app" >&2
        fi
        /bin/rm -rf "$stage"
      else
        echo "triage-app: no Command Line Tools (xcode-select --install), Triage.app not built" >&2
      fi
    fi
  '';

  launchd.agents.message-triage = {
    enable = true;
    config = {
      ProgramArguments = ["${serve}/bin/message-triage-serve"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/matth/Library/Logs/message-triage.log";
      StandardErrorPath = "/Users/matth/Library/Logs/message-triage.log";
    };
  };
}
