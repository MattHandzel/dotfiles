# Every finished Wispr Flow dictation also lands on the clipboard, so Raycast's
# Clipboard History keeps a searchable record of everything Matt dictated.
#
# Wispr Flow (macOS) has no "always copy to clipboard" setting — its docs only
# offer a per-dictation copy button and a copy-on-paste-failure fallback. But
# it logs every dictation locally in
#   ~/Library/Application Support/Wispr Flow/flow.sqlite  (table History)
# with the text it actually pasted. This agent tails that table every 0.5 s and
# pbcopy's each new row; Raycast watches the pasteboard and records it.
#
# Order of preference for the text: pastedText (what really went into the app)
# > formattedText (Wispr's cleaned transcript) > asrText (raw). The row's
# timestamp is the cursor, kept in ~/.local/state/wispr-clipboard-sync/last.
# NOTE: `timestamp` is a TEXT column ("2026-09-13 02:29:36.887 +00:00", UTC),
# not epoch ms. SQLite orders TEXT above every INTEGER, so comparing against a
# number matches every row (that replayed all 439 dictations once, 2026-09-12).
# The cursor is therefore kept in the same text format and always quoted.
# Read-only, WAL-safe (mode=ro on a live Chromium-style sqlite is fine).
{pkgs, ...}: let
  sync = pkgs.writeShellApplication {
    name = "wispr-clipboard-sync";
    runtimeInputs = [pkgs.sqlite pkgs.coreutils];
    text = ''
      db="$HOME/Library/Application Support/Wispr Flow/flow.sqlite"
      state="$HOME/.local/state/wispr-clipboard-sync"; mkdir -p "$state"
      last=$(cat "$state/last" 2>/dev/null || true)
      # First run (or a legacy numeric cursor): start from "now", in the DB's own
      # UTC text format, so 400+ old dictations do not flood the clipboard.
      case "$last" in
        20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ *) ;;
        *) last=$(date -u +'%Y-%m-%d %H:%M:%S.000 +00:00'); echo "$last" > "$state/last" ;;
      esac
      while true; do
        if [ -f "$db" ]; then
          rows=$(sqlite3 -readonly -separator $'\x1f' "file:$db?mode=ro" \
            "select timestamp, replace(coalesce(nullif(pastedText,'''), nullif(formattedText,'''), asrText, '''), char(10), char(30)) from History where timestamp > '$last' order by timestamp" 2>/dev/null || true)
          if [ -n "$rows" ]; then
            while IFS=$'\x1f' read -r ts text; do
              [ -n "$text" ] || continue
              text=$(printf '%s' "$text" | tr '\036' '\n')
              # Wispr writes the row BEFORE it restores the pre-dictation clipboard
              # (~0.5 s later, measured 2026-09-13), so a copy made right away gets
              # overwritten. Wait out the restore, copy, and re-copy if clobbered.
              sleep 1
              prev=$(/usr/bin/pbpaste 2>/dev/null || true)
              printf '%s' "$text" | /usr/bin/pbcopy
              sleep 1
              if [ "$prev" != "$text" ] && [ "$(/usr/bin/pbpaste 2>/dev/null || true)" = "$prev" ]; then
                printf '%s' "$text" | /usr/bin/pbcopy
              fi
              last="$ts"; echo "$last" > "$state/last"
            done <<<"$rows"
          fi
        fi
        sleep 0.5
      done
    '';
  };
in {
  launchd.agents.wispr-clipboard-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${sync}/bin/wispr-clipboard-sync"];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "/tmp/wispr-clipboard-sync.err";
    };
  };
}
