# Espanso text expansion on the Mac — `;` triggers (were `;;` until 2026-11-24, Matt: one less `;`), the same set as the laptop's
# ~/.config/espanso/match/base.yml, nix-managed.
#
# History, because the config had drifted: homebrew.nix claimed on 2026-09-10 that
# Raycast Snippets replaced Espanso, but Espanso.app was installed anyway, its
# own LaunchAgent (com.federicoterzi.espanso, registered by `espanso service
# register`) was running, and a hand-copied base.yml was loaded with 33 live
# triggers — several still pointing at Linux paths (`;;pass` via systemd-run,
# `;;intro*` via /home/matth, `;;md` via /run/current-system bash). The
# 2026-09-12 migration audit flagged the snippets as "gone"; they were not, but
# they were unmanaged and partly broken. This module is the single source now.
#
# Differences from the Linux file, all deliberate:
#   ;;pass     systemd-run → detached password-picker (same picker, mac build)
#   ;;intro*   /home/matth → /Users/matth (the /home bridge vanishes on reboot)
#   ;;md       /run/current-system bash → /bin/bash; wl-paste/pandoc are the
#              HM-profile shims, same absolute paths as before
#   ;;ucal     Mac-only trigger Matt added by hand; kept
#   ;;meeting, ;;importcal   were on Linux only; restored
# Everything else (dates, links, emails, phrases, signature) is identical,
# except the private matches (phone, address, personal doc links), which stay
# out of the public repo in ~/.config/espanso/match/personal.yml.
# The espanso-latex packages under match/packages/ are installed by the
# espanso CLI and left alone.
{
  config,
  lib,
  ...
}: let
  work = config.my.work or false;
  vault = "/Users/matth/Obsidian/Main";
  bin = "/etc/profiles/per-user/matth/bin";
  # Interpolated lines are not re-indented by the `''` block (only its literal
  # lines lose their 4-space common indent), so every line after the first
  # carries the absolute indent it needs in the final file.
  script = args:
    builtins.concatStringsSep "\n" ([
        "replace: \"{{o}}\""
        "    vars:"
        "      - name: o"
        "        type: script"
        "        params:"
        "          args:"
      ]
      ++ map (a: "            - ${builtins.toJSON a}") args);
  cat = path: script ["/bin/cat" path];
  # Matches that call the vault or the personal password picker; left off the
  # Redwood laptop (my.work).
  personalMatches = ''
    # Managed by modules/home/darwin/espanso.nix; not written on the Redwood laptop.
    matches:
      # === password picker ===
      # Expands to nothing and launches the picker DETACHED, so espanso finishes
      # its own backspace cycle before the picker starts typing (same race the
      # Linux file avoided with systemd-run).
      - trigger: ";pass"
        ${script ["/bin/bash" "-c" "nohup ${bin}/password-picker >/dev/null 2>&1 &"]}

      # === intros (source of truth in the vault; edit the file, expansion follows) ===
      - trigger: ";intro"
        ${cat "${vault}/areas/personal-brand/intros/short.md"}
      - trigger: ";longintro"
        ${cat "${vault}/areas/personal-brand/intros/long.md"}
      - trigger: ";intro20"
        ${cat "${vault}/areas/personal-brand/intros/cold-coffee-chat.md"}
  '';
  matchesYaml = ''
    # Managed by modules/home/darwin/espanso.nix — edit there and rebuild.
    matches:
      - trigger: ":espanso"
        replace: "Hi there!"

      # === date / time ===
      - trigger: ";date"
        replace: "{{mydate}}"
        vars:
          - name: mydate
            type: date
            params:
              format: "%Y-%m-%d"
      - trigger: ";time"
        replace: "{{mytime}}"
        vars:
          - name: mytime
            type: date
            params:
              format: "%H:%M"
      - trigger: ";timeHMS"
        replace: "{{mytimehms}}"
        vars:
          - name: mytimehms
            type: date
            params:
              format: "%H:%M:%S"
      - trigger: ";datetime"
        replace: "{{mydatetime}}"
        vars:
          - name: mydatetime
            type: date
            params:
              format: "%Y-%m-%d %H:%M:%S"

      # === links ===
      # Short links: mhzl.dev/<slug>, managed in the vault table
      # areas/personal-brand/website/shortlinks.md (or matthandzel.com/admin/short-links).
      # Repoint a link there; these triggers never need to change.
      - trigger: ";web"
        replace: "https://matthandzel.com/"
      - trigger: ";linkedin"
        replace: "https://mhzl.dev/linkedin"
      - trigger: ";x"
        replace: "https://mhzl.dev/x"
      - trigger: ";github"
        replace: "https://mhzl.dev/gh"
      - trigger: ";blog"
        replace: "https://mhzl.dev/blog"
      - trigger: ";mac"
        replace: "https://mhzl.dev/mac"
      - trigger: ";bweb"
        replace: "https://mhzl.dev/biz"
      - trigger: ";career"
        replace: "https://mhzl.dev/career-memo"

      # === email ===
      - trigger: ";business@"
        replace: "business@matthandzel.com"
      - trigger: ";matt@"
        replace: "matt@matthandzel.com"
      - trigger: "matt@"
        replace: "matt@matthandzel.com"
      - trigger: ";h@"
        replace: "handzelmatthew@gmail.com"
      - trigger: ";m@"
        replace: "matt@matthandzel.com"
      - trigger: ";r@"
        replace: "matt.handzel@rdwrs.com"

      # === scheduling ===
      - trigger: ";cal"
        replace: "https://mhzl.dev/cal"
      - trigger: ";ai-cal"
        replace: "https://mhzl.dev/uplift"
      - trigger: ";introcal"
        replace: "https://mhzl.dev/intro"
      - trigger: ";ical"
        replace: "https://mhzl.dev/intro"
      - trigger: ";importcal"
        replace: "https://mhzl.dev/urgent"
      - trigger: ";ucal"
        replace: "https://mhzl.dev/urgent"
      - trigger: ";meetlong"
        replace: "Would you be down to meet via video? We can see our mutual availability here: https://mhzl.dev/coffee"
      - trigger: ";meetask"
        replace: "Want to grab a 20-min coffee chat? https://mhzl.dev/coffee"
      - trigger: ";decline"
        replace: "Thanks for the invite — can't make this one but hope it goes well."
      - trigger: ";meetprep"
        replace: "So that I can provide the most value to you for our meeting, can you write out what you would like to get out of our meeting, what specific questions / discussion points you have? If they are short and quick I would prefer to answer them async. Please send those 24 hours in advanced otherwise I will reschedule. Thanks!"

      - trigger: ";irlmeetprep"
        replace: "So that I can provide the most value to you for our meeting, can you write out what you would like to get out of our meeting, what specific questions / discussion points you have? If they are short and quick I would prefer to answer them async. Please send those 24 hours in advanced otherwise I will reschedule. Thanks!"

      # === contact / identity ===
      # ;phone, ;addr, ;dmd and ;dms are PRIVATE (phone number, street
      # address, personal doc links) and this repo is public, so they live in
      # ~/.config/espanso/match/personal.yml — a hand-managed file espanso loads
      # alongside this one. Edit it directly; nothing here regenerates it.
      - trigger: ";sig"
        replace: "Best,\n-Matt"

      # === common phrases ===
      - trigger: ";followup"
        replace: "Just following up on this :)"
      - trigger: ";reachout"
        replace: "Don't hesitate to reach out if you have any questions."
      - trigger: ";sg"
        replace: "Sounds great!"

      # === Slack Claude model flags (MAT-5541): fast opus / fast sonnet ===
      - trigger: ";scfo"
        replace: "!fast !opus"
      - trigger: ";scfs"
        replace: "!fast !sonnet"

      # === clip2md (MAT-572): rich text on the clipboard -> Markdown, inline ===
      - trigger: ";md"
        ${script ["/bin/bash" "-c" "html=$(${bin}/wl-paste --type text/html 2>/dev/null); if [ -n \"$html\" ]; then printf '%s' \"$html\" | ${bin}/pandoc --from html --to gfm-raw_html --wrap=none; else ${bin}/wl-paste; fi"]}
  '';
in {
  home.file.".config/espanso/match/base.yml".text = matchesYaml;
  home.file.".config/espanso/match/personal-tools.yml" = lib.mkIf (!work) {text = personalMatches;};
  home.file.".config/espanso/config/default.yml".text = ''
    # Managed by modules/home/darwin/espanso.nix — edit there and rebuild.
    # Double-tapping a modifier silently disables ALL expansions with no feedback
    # and the state sticks; that was the real "espanso stops working" on Linux.
    toggle_key: OFF
    search_shortcut: OFF
  '';
  # Dia's new-tab "Ask anything" composer accepts espanso's injected backspaces
  # but drops the injected unicode text, so the trigger vanishes and nothing is
  # inserted (Oops 20260914-172633). Paste via the clipboard there instead —
  # but ONLY in the new-tab window: on ordinary web pages the clipboard paste
  # is silently dropped about a third of the time (Swapcard chat: 1 of 6
  # `;;cal` landed; trail log 2026-10-08..18: 18 of 58 web-page pastes retried
  # within 20 s vs 0 of 7 in New Tab — Oops 20261018-165007), while injected
  # text works there. Espanso reads the title via Accessibility; filters AND.
  home.file.".config/espanso/config/dia.yml".text = ''
    # Managed by modules/home/darwin/espanso.nix — edit there and rebuild.
    filter_exec: "Dia\\.app"
    filter_title: "New Tab$"
    backend: Clipboard
  '';

  # The LaunchAgent, nix-managed since Oops 20261113-144204. `espanso service
  # register` wrote it with RunAtLoad only, no KeepAlive. At 13:56 on 2026-11-13
  # two config reloads arrived back to back, and the second worker found the
  # first one still alive ("worker is already running!"). The daemon then exited
  # 101 and Espanso stayed dead until the next login. KeepAlive on a non-zero
  # exit restarts it; `espanso stop` exits 0 and stays stopped. The label is
  # espanso's own, so `espanso service start/stop/restart` keep working.
  launchd.agents.espanso = {
    enable = true;
    config = {
      Label = "com.federicoterzi.espanso";
      ProgramArguments = [
        (
          if work
          then "/Applications/Espanso.app/Contents/MacOS/espanso"
          else "/opt/homebrew/bin/espanso"
        )
        "launcher"
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      EnvironmentVariables.PATH = "${bin}:/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "/tmp/espanso.out";
      StandardErrorPath = "/tmp/espanso.err";
    };
  };
}
