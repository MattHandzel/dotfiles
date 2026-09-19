# Espanso text expansion on the Mac — the same `;;` triggers as the laptop's
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
{...}: let
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
  matchesYaml = ''
    # Managed by modules/home/darwin/espanso.nix — edit there and rebuild.
    matches:
      - trigger: ":espanso"
        replace: "Hi there!"

      # === date / time ===
      - trigger: ";;date"
        replace: "{{mydate}}"
        vars:
          - name: mydate
            type: date
            params:
              format: "%Y-%m-%d"
      - trigger: ";;time"
        replace: "{{mytime}}"
        vars:
          - name: mytime
            type: date
            params:
              format: "%H:%M"
      - trigger: ";;timeHMS"
        replace: "{{mytimehms}}"
        vars:
          - name: mytimehms
            type: date
            params:
              format: "%H:%M:%S"
      - trigger: ";;datetime"
        replace: "{{mydatetime}}"
        vars:
          - name: mydatetime
            type: date
            params:
              format: "%Y-%m-%d %H:%M:%S"

      # === links ===
      - trigger: ";;web"
        replace: "https://matthandzel.com/"
      - trigger: ";;linkedin"
        replace: "https://www.linkedin.com/in/matthandzel"
      - trigger: ";;x"
        replace: "https://x.com/handzelmatt"
      - trigger: ";;github"
        replace: "https://github.com/MattHandzel/"
      - trigger: ";;blog"
        replace: "https://systemsforsecondbrain.substack.com/"
      - trigger: ";;bweb"
        replace: "https://www.handzelsystems.com/"
      - trigger: ";;career"
        replace: "https://matthandzel.com/career-memo"

      # === email ===
      - trigger: ";;business@"
        replace: "business@matthandzel.com"
      - trigger: ";;matt@"
        replace: "matt@matthandzel.com"
      - trigger: "matt@"
        replace: "matt@matthandzel.com"
      - trigger: ";;h@"
        replace: "handzelmatthew@gmail.com"
      - trigger: ";;m@"
        replace: "matt@matthandzel.com"

      # === scheduling ===
      - trigger: ";;cal"
        replace: "https://cal.com/matthandzel/work-meeting"
      - trigger: ";;introcal"
        replace: "https://cal.com/matthandzel/intro-call"
      - trigger: ";;importcal"
        replace: "https://cal.com/matthandzel/urgent-important"
      - trigger: ";;ucal"
        replace: "https://cal.com/matthandzel/urgent-important"
      - trigger: ";;meetlong"
        replace: "Would you be down to meet via video? We can see our mutual availability here: https://cal.com/matthandzel/20min-intro"
      - trigger: ";;meetask"
        replace: "Want to grab a 20-min coffee chat? https://cal.com/matthandzel/20min-intro"
      - trigger: ";;decline"
        replace: "Thanks for the invite — can't make this one but hope it goes well."
      - trigger: ";;meetprep"
        replace: "So that I can provide the most value to you for our meeting, can you write out what you would like to get out of our meeting, what specific questions you’d like to ask, and if you’re satisfied with me answeering them async? Please send those over 24 hours before the meeting otherwise I will reschedule. Thanks!"

      # === contact / identity ===
      # ;;phone, ;;addr, ;;dmd and ;;dms are PRIVATE (phone number, street
      # address, personal doc links) and this repo is public, so they live in
      # ~/.config/espanso/match/personal.yml — a hand-managed file espanso loads
      # alongside this one. Edit it directly; nothing here regenerates it.
      - trigger: ";;sig"
        replace: "Best,\n-Matt"

      # === common phrases ===
      - trigger: ";;followup"
        replace: "Just following up on this :)"
      - trigger: ";;reachout"
        replace: "Don't hesitate to reach out if you have any questions."
      - trigger: ";;sg"
        replace: "Sounds great!"

      # === password picker ===
      # Expands to nothing and launches the picker DETACHED, so espanso finishes
      # its own backspace cycle before the picker starts typing (same race the
      # Linux file avoided with systemd-run).
      - trigger: ";;pass"
        ${script ["/bin/bash" "-c" "nohup ${bin}/password-picker >/dev/null 2>&1 &"]}

      # === intros (source of truth in the vault; edit the file, expansion follows) ===
      - trigger: ";;intro"
        ${cat "${vault}/areas/personal-brand/intros/short.md"}
      - trigger: ";;longintro"
        ${cat "${vault}/areas/personal-brand/intros/long.md"}
      - trigger: ";;intro20"
        ${cat "${vault}/areas/personal-brand/intros/cold-coffee-chat.md"}

      # === clip2md (MAT-572): rich text on the clipboard -> Markdown, inline ===
      - trigger: ";;md"
        ${script ["/bin/bash" "-c" "html=$(${bin}/wl-paste --type text/html 2>/dev/null); if [ -n \"$html\" ]; then printf '%s' \"$html\" | ${bin}/pandoc --from html --to gfm-raw_html --wrap=none; else ${bin}/wl-paste; fi"]}
  '';
in {
  home.file.".config/espanso/match/base.yml".text = matchesYaml;
  home.file.".config/espanso/config/default.yml".text = ''
    # Managed by modules/home/darwin/espanso.nix — edit there and rebuild.
    # Double-tapping a modifier silently disables ALL expansions with no feedback
    # and the state sticks; that was the real "espanso stops working" on Linux.
    toggle_key: OFF
    search_shortcut: OFF
  '';
  # Dia's new-tab "Ask anything" composer accepts espanso's injected backspaces
  # but drops the injected unicode text, so the trigger vanishes and nothing is
  # inserted (Oops 20260914-172633). Paste via the clipboard there instead.
  home.file.".config/espanso/config/dia.yml".text = ''
    # Managed by modules/home/darwin/espanso.nix — edit there and rebuild.
    filter_exec: "Dia\\.app"
    backend: Clipboard
  '';
}
