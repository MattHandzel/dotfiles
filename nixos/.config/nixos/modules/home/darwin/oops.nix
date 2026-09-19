# oops — "something just went wrong" on the Mac: one keypress hands the last
# 90 s of what Matt saw and did, plus everything the machine knows about that
# window, to a Claude session that (1) logs the problem in the vault's system
# problem log, (2) tries to fix it, (3) records the outcome.
#
# Added 2026-09-12 at Matt's request ("press a keyboard shortcut when something
# did not happen … goes back in time and looks at all the keyboard presses …
# spins it off to Claude … saves this as a problem stored in the persistent
# problem log … immediately tries to solve that problem"), then widened the same
# night ("be comprehensive … screenshots … websites … process history … think").
# It also absorbs the macOS port of the Linux SUPER+grave nixos-assistant
# (~/.local/bin/mac-assistant, hand-written 2026-09-10, never nix-managed, and
# its `gum input` prompt could not run from an AeroSpace hotkey because there is
# no TTY): a typed note that reads as a change request is handled as one.
#
# Wiring:
#   ⌥` is an hs.hotkey inside ~/.hammerspoon/oops.lua (2026-09-13; the AeroSpace
#     `alt-backtick -> open -g hammerspoon://oops` hop lost the first press in
#     2 of 3 runs). Raycast "Oops" still uses  open -g hammerspoon://oops?text=…
#   ~/.hammerspoon/oops.lua (always on) keeps the last 90 s of keystrokes,
#     clicks, app + workspace switches and 2 screenshots/s on a RAM disk
#     (~/.hammerspoon/oops_ring.zsh); on trigger it writes ~/.local/state/oops/<ts>/{keys.log,
#     note.txt, front.txt, hammerspoon-console.txt, screens/} and runs
#     ~/.local/bin/oops <dir>  (symlink to this package, see home.file —
#     /etc/profiles/per-user is root-managed and only refreshes on `rebuild`)
#   `oops <dir>` adds the machine-side context (below), then starts Claude in a
#     new tmux window (tab, named MMDD-HHMM) of the one detached session "oops"
#     (socket "oops"; the sketchybar `oops` life-ring counts the tabs). No window
#     opens on Matt's workspace: `oops --view` opens the single kitty (title
#     "oops") when he goes to workspace "oops"; closing it keeps the tabs running.
#   `oops --attach [ts]`  shows the newest (or named) tab; also the
#     Raycast command "Oops: Reattach".
#
# What the incident directory ends up holding, and why each piece is there
# (each one is a failure class that has actually cost Matt time):
#   keys.log               what he did, with workspace/app/window per line
#   screens/ + *.txt       what he saw (2 frames/s + OCR of a subset)
#   front.txt              stuck modifiers, secure input, layout, permissions
#   hammerspoon-console.txt hotkey/tap errors only visible in the HS console
#   context.md             windows/workspaces/monitors, processes started in
#                          the window, top CPU/mem, launchd agents failing,
#                          launchd spawn/exit events, crash reports, recently
#                          written logs, secure-input owner, connected
#                          keyboards, network/VPN, last wake, rebuild state,
#                          git status of the flake, other live oops sessions
#   terminal.txt           the focused kitty window's screen + last command
#                          output (kitty remote control), and recent zsh history
#   browser-history.md     pages visited in the last 120 s (Dia, all profiles)
#   dictations.md          Wispr Flow dictations in the window (paste failures)
#   clipboard.txt          the clipboard at the trigger
#   unified-log-errors.txt macOS unified log errors/faults (arrives ~25 s later)
#
# The problem log lives in the vault so other Claude instances can mine it:
#   ~/Obsidian/Main/areas/second-brain/system-problem-log.md
{pkgs, ...}: let
  repo = "/Users/matth/dotfiles/nixos/.config/nixos";
  problemLog = "/Users/matth/Obsidian/Main/areas/second-brain/system-problem-log.md";
  stateRoot = "/Users/matth/.local/state/oops";

  brief = pkgs.writeText "oops-brief.md" ''
    <role>
    You are Matt's "Oops" assistant on his Mac: the session that runs when he
    presses ⌥` because something on the machine just did not do what it should.
    You own the whole repair end to end — diagnose, log, fix, verify, report —
    with no check-ins. Matt is usually on another workspace and reads this
    window later, so everything you conclude must be written down where it
    lasts: the problem log and the incident's todo.md, not just the screen.
    </role>

    <machine>
    nix-darwin + home-manager flake at ~/dotfiles/nixos/.config/nixos, host
    `matts-mac`. AeroSpace tiling WM (modules/home/darwin/aerospace.nix),
    Hammerspoon (~/.hammerspoon, NOT nix-managed; oops.lua is the recorder and
    the ⌥` hotkey), Karabiner (internal keyboard only; the ZMK Totem is not
    grabbed), Espanso (modules/home/darwin/espanso.nix), Raycast script commands
    (modules/home/darwin/raycast-scripts.nix), sketchybar
    (modules/home/darwin/sketchybar/), kitty + tmux, Dia browser, Wispr Flow
    dictation, Polish keyboard layout. This session runs in `tmux -L oops`
    inside a kitty window that AeroSpace parks on workspace "oops"; the
    sketchybar life-ring shows it is alive.
    </machine>

    <incident_files>
    Your first message names the incident directory. It contains:
      keys.log   — the last 90 s of keystrokes, typing bursts, clicks, app and
                   workspace switches, oldest first, "T-12.3s" = seconds before
                   the trigger; every line is prefixed with its workspace
      note.txt   — what Matt typed (may be empty; may be a change request instead
                   of a failure — treat it as one if so)
      front.txt  — input state at the trigger: focused window, modifiers HELD,
                   secure input, keyboard layout, Hammerspoon permissions
      screens/   — 2 screenshots per second for the last 90 s (~180 frames)
                   plus one at the trigger (INDEX.txt = time/workspace/app/
                   window per frame, written when the frames are done; *.txt =
                   OCR of the last 10 s and one frame per 5 s before that,
                   written within ~60 s). Open the
                   frames around the failure with the Read tool — they show what
                   Matt actually saw; if a Read hook caps or refuses the image,
                   shrink a copy with `sips -Z 900` into your scratchpad and read
                   that, or fall back to the OCR text.
      hammerspoon-console.txt — the Hammerspoon console (hotkey/tap errors)
      context.md — windows/workspaces/monitors, processes started in the last
                   2 min, top CPU/memory, launchd agents with non-zero exit and
                   launchd spawn/exit events, fresh crash reports, recently
                   written logs, the secure-input owner, connected keyboards,
                   network/VPN, last wake, rebuild/generation state, git status
      terminal.txt — the focused kitty window's screen and last command output,
                   plus the last zsh commands
      browser-history.md — pages visited in the last 120 s (Dia, all profiles)
      dictations.md — Wispr Flow dictations in the window and their status
      clipboard.txt — the clipboard at the trigger
      unified-log-errors.txt — macOS unified log errors/faults (may still be
                   writing for ~25 s after you start; re-read it)
    File mtimes inside the directory are evidence too: keys.log is written at
    the trigger, screens/INDEX.txt when the frames are done, note.txt when Matt
    submits the note box.
    </incident_files>

    <procedure>
    Do, in this order:
    1. Reconstruct what Matt was trying to do and what failed (2 lines, from
       keys.log, the screenshots and the note). Read the evidence before
       forming a theory; never speculate about a file or config you have not
       opened. If it is ambiguous, ask ONE sharp question, then proceed on your
       best reading while waiting.
    2. IMMEDIATELY append an entry to the problem log (${problemLog}), status
       `open`, BEFORE attempting any fix. Non-negotiable: the log is the durable
       record other Claude instances mine, and a fix that is not logged is a
       fix that gets re-discovered from scratch next time. Entry format (append
       at the end):

       ## YYYY-MM-DD HH:MM — <short title>
       - **Status:** open
       - **Where:** <app / kitty command / workspace>
       - **Symptom:** <what Matt expected vs what happened>
       - **Root cause:** <fill in>
       - **Fix:** <files changed / what was done>
       - **Verified:** <the real command/path you exercised and its output>
       - **Run:** `<incident dir>`

       Then check the EARLIER entries for the same symptom. A repeat means the
       previous fix was wrong: say so, do not re-apply a variant of it, restart
       from observation.
    3. Create <incident dir>/todo.md (format in <requests_queue>) with the
       incident as item #1, then fix the ROOT CAUSE, declaratively where it
       belongs (flake modules, or ~/.hammerspoon/*.lua for the recorder and
       keyboard-agnostic remaps).
    4. Update the entry: Status fixed | needs-matt | open, and fill Root cause /
       Fix / Verified. If it is not `fixed`, the problem log entry and todo.md
       are the only record. Matt no longer uses Taskwarrior as a to-do list:
       never `task add`.
    5. Finish with the report described in <final_report>.
    </procedure>

    <hard_rules>
    - Verify, don't assert: exercise the real path a human would use and paste
      the output. "The config looks right" is not evidence. A fix whose only
      proof is that it built is not verified.
    - Never run sudo, `darwin-rebuild switch`, `sfltool`, or anything that pops
      a macOS password/admin prompt. Home-only changes (modules/home/**) apply
      WITHOUT sudo:
        cd ${repo} && git add -A . && nix build .#darwinConfigurations.matts-mac.config.home-manager.users.matth.home.activationPackage -o /tmp/hm-oops && HOME_MANAGER_BACKUP_EXT=hm-backup /tmp/hm-oops/activate
      After that, new binaries are NOT on PATH until Matt runs `rebuild`
      (/etc/profiles/per-user is root-managed) — reference them by store path
      or via a home.file symlink in ~/.local/bin. Changes under modules/darwin/**
      need Matt to run `rebuild`; stage them and say so.
    - Reload Hammerspoon with `timeout 8 hs -c 'hs.reload()' || true`; reload
      AeroSpace with `aerospace reload-config`; sketchybar with
      `sketchybar --reload`; Espanso reloads itself.
    - Never delete personal data; move retired files to a dated backup dir.
    - Fix what the incident needs and nothing else: no refactors, no cleanup of
      code you did not have to touch, no extra configurability. Do not commit.
    - Reversible local edits: just do them. Anything hard to undo or visible to
      other people (force-push, deleting a directory of Matt's data, sending a
      message): stop and ask.
    </hard_rules>

    <requests_queue>
    Matt keeps talking to this session while it works — he thinks out loud, and
    his messages arrive mid-turn next to tool results. Every such message is a
    REQUEST TO QUEUE, not an interrupt. The failure this prevents: he mentions
    three things in five minutes, the session sprints at each in turn, and he
    gets three 30%-done investigations instead of one finished repair.
    - Keep <incident dir>/todo.md from your first action on. One line per
      request, in arrival order, in Matt's words condensed. The incident is #1.
    - The moment a new request arrives: append it to todo.md, tell Matt in one
      line that it is captured ("Captured as #3 — finishing #1 first."), and
      keep working the item you were on.
    - Finish the current item, or reach a clean stopping point and write down
      what state you left it in, before starting the next. Never abandon a
      half-done item for the newest message.
    - Work the list in order unless Matt says "now", "first", "urgent" or
      "drop everything". Items about a different subsystem still go on the
      list; an item too large for this session stays open in todo.md with a note.
    - Nothing on the list is ever silently forgotten. Before the final report,
      re-read todo.md and mark every row.
    <example>
    # todo — Oops 20260913-122139
    - [x] #1 ⌥` takes ~15 s before the note box appears — fixed, verified (dry trigger 0.2 s)
    - [x] #2 Improve the Oops brief: keep a to-do list, do not switch focus — done
    - [ ] #3 Bar indicator that a session is running + terminal on its own workspace — needs-matt: `rebuild`
    </example>
    </requests_queue>

    <progress_updates>
    Matt reads this window from another workspace, sometimes minutes later, and
    only your text is visible to him — not your tool calls. So write a one-line
    update every time the phase changes (reconstructed → logged → cause found →
    fixing → verifying → done) and whenever you learn something that changes the
    plan. State facts, not feelings. Do not compress these updates away.
    </progress_updates>

    <final_report>
    End with, in this order:
    1. One line: what was broken, what changed, how it was verified, and
       anything Matt must do (e.g. `rebuild`).
    2. The todo.md list with every item's final status.
    3. Any open question, as one sentence.
    </final_report>
  '';

  # Pages visited in the last 120 s, from every Dia profile's History db.
  browserHistory = pkgs.writeText "oops-browser-history.py" ''
    import glob, os, shutil, sqlite3, tempfile, time
    window_s = 120
    now_us = int(time.time() * 1e6) + 11644473600 * 10**6   # Chromium epoch = unix + 1601 offset
    cutoff = now_us - window_s * 10**6
    print("# Websites visited in the last %d s (Dia history, all profiles; newest first)\n" % window_s)
    rows = []
    for db in glob.glob(os.path.expanduser("~/Library/Application Support/Dia/User Data/*/History")):
        prof = os.path.basename(os.path.dirname(db))
        tmp = tempfile.mkdtemp(prefix="oops-hist-")
        try:
            shutil.copy2(db, os.path.join(tmp, "History"))
            con = sqlite3.connect(os.path.join(tmp, "History"))
            for url, title, vt in con.execute(
                "select u.url, u.title, v.visit_time from visits v join urls u on u.id = v.url "
                "where v.visit_time > ? order by v.visit_time desc limit 60", (cutoff,)):
                rows.append(((now_us - vt) / 1e6, prof, title or "", url))
            con.close()
        except Exception as e:
            print("(%s: %s)" % (prof, e))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    rows.sort()
    for ago, prof, title, url in rows:
        print("- T-%5.1fs  [%s]  %s\n  <%s>" % (ago, prof, title[:100], url[:200]))
    if not rows:
        print("(no page visits in the window; window titles in keys.log are the next best signal)")
  '';

  # Wispr Flow dictations in the window: what was said, what was pasted, where.
  dictations = pkgs.writeText "oops-dictations.py" ''
    import datetime, os, sqlite3
    db = os.path.expanduser("~/Library/Application Support/Wispr Flow/flow.sqlite")
    print("# Wispr Flow dictations in the last 180 s (newest first)\n")
    if not os.path.exists(db):
        print("(no Wispr Flow database)"); raise SystemExit
    since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=180)).strftime("%Y-%m-%d %H:%M:%S")
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    cols = [r[1] for r in con.execute("pragma table_info(History)")]
    want = [c for c in ("timestamp", "status", "app", "pastedText", "formattedText", "asrText", "numWords") if c in cols]
    n = 0
    for row in con.execute("select %s from History where timestamp > ? order by timestamp desc limit 20" % ", ".join(want), (since,)):
        d = dict(zip(want, row)); n += 1
        text = (d.get("pastedText") or d.get("formattedText") or d.get("asrText") or "").replace("\n", " ")
        print("- %s  status=%s  app=%s  words=%s\n  %s" % (d.get("timestamp"), d.get("status"), d.get("app"), d.get("numWords"), text[:300]))
    if n == 0:
        print("(none)")
  '';

  oops = pkgs.writeShellApplication {
    name = "oops";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gawk pkgs.gnused pkgs.tesseract pkgs.tmux];
    text = ''
      # oops [--dry-run] <incident-dir> | oops --attach [ts]
      # runtimeInputs (gawk, tesseract, tmux, …) stay FIRST: /usr/bin/awk has no
      # strftime, and a first version let it shadow gawk.
      export PATH="$PATH:/opt/homebrew/bin:/etc/profiles/per-user/matth/bin:/run/current-system/sw/bin:$HOME/.local/bin:$HOME/.npm-packages/bin:/usr/bin:/bin:/usr/sbin:/sbin"

      # All incidents are windows (tabs) of ONE tmux session "oops", shown in ONE
      # kitty window titled "oops" (2026-09-15, Matt: "oops should not create a
      # new kitty window, but just spawn another tmux tab in the same oops
      # window"). Before, each incident was its own session + kitty window and
      # workspace oops tiled 13 of them ~13 columns wide. Tab name = MMDD-HHMM;
      # the full ts is the window option @oops_ts.
      attached() { [ "$(tmux -L oops display-message -p -t '=oops:' '#{session_attached}' 2>/dev/null || echo 0)" -gt 0 ]; }

      if [ "''${1:-}" = "--view" ]; then
        # Open the kitty window when a new incident arrived and no window shows
        # the session (flag set by the launcher). Only runs while Matt is on
        # workspace "oops", so the window appears where he is looking. Exit 1
        # when nothing was pending.
        lock="''${TMPDIR:-/tmp}/oops-view.lock"
        mkdir "$lock" 2>/dev/null || exit 0
        trap 'rmdir "$lock"' EXIT
        [ "$(tmux -L oops show-options -qv -t '=oops:' @oops_pending 2>/dev/null || true)" = 1 ] || exit 1
        tmux -L oops set-option -u -t '=oops:' @oops_pending
        attached && exit 1
        kitty --title oops -e tmux -L oops attach -t '=oops:' >/dev/null 2>&1 &
        exit 0
      fi

      if [ "''${1:-}" = "--attach" ]; then
        # Show the newest (or the named) incident tab; open the kitty if none.
        want="''${2:-}"
        if ! tmux -L oops has-session -t '=oops:' 2>/dev/null; then
          /usr/bin/osascript -e 'display notification "no Oops session is running" with title "Oops"'; exit 1
        fi
        if [ -n "$want" ]; then
          idx="$(tmux -L oops list-windows -t '=oops:' -F '#{window_index} #{@oops_ts}' | awk -v t="$want" '$2 == t {print $1}')"
        else
          idx="$(tmux -L oops list-windows -t '=oops:' -F '#{window_index}' | tail -n 1)"
        fi
        [ -n "$idx" ] && tmux -L oops select-window -t "=oops:$idx"
        attached || kitty --title oops -e tmux -L oops attach -t '=oops:' >/dev/null 2>&1 &
        sleep 0.8; /opt/homebrew/bin/aerospace summon-workspace oops 2>/dev/null || true
        exit 0
      fi

      dry=0
      if [ "''${1:-}" = "--dry-run" ]; then dry=1; shift; fi
      dir="''${1:-}"
      if [ -z "$dir" ] || [ ! -d "$dir" ]; then
        echo "usage: oops [--dry-run] <incident-dir>   |   oops --attach [ts]" >&2
        exit 2
      fi
      cd "$dir"
      ts="$(basename "$dir")"
      # From here on every command is a best-effort probe of a machine that is
      # BY DEFINITION misbehaving — a grep with no match or a dead ping must not
      # abort context collection (writeShellApplication turns errexit/pipefail on).
      set +o errexit
      set +o pipefail
      log="${problemLog}"
      mkdir -p "$(dirname "$log")"
      if [ ! -f "$log" ]; then
        printf '%s\n' '---' 'id: system-problem-log' 'aliases:' '  - System Problem Log' 'tags:' '  - systems' '  - problem-log' "created_date: \"$(date +%F)\"" '---' "" '# System Problem Log' "" > "$log"
      fi
      sec() { echo; echo "## $1"; echo; }
      fence() { echo '```'; cat; echo '```'; }

      # ---- fast context, inline (everything here returns in well under 2 s) ------
      {
        echo "# Oops context ($ts)"
        sec "Frontmost / input state at trigger (front.txt)"; cat front.txt 2>/dev/null

        sec "AeroSpace: focused workspace, monitors, every window"
        if command -v aerospace >/dev/null 2>&1; then
          echo "focused workspace: $(aerospace list-workspaces --focused 2>&1)"
          echo "monitors: $(aerospace list-monitors 2>&1 | tr '\n' ';')"
          aerospace list-windows --all --format '%{workspace} | %{app-name} | %{window-title}' 2>&1 | head -n 80 | fence
        else echo "(aerospace CLI not found)"; fi

        sec "Processes started in the last 2 min (etime < 2:00)"
        ps -axo pid=,ppid=,etime=,user=,comm= 2>/dev/null | awk '$3 !~ /-/ && $3 !~ /:.*:/ { split($3,t,":"); if (t[1]+0 < 2) print }' | head -n 40 | fence

        sec "Top CPU / memory right now"
        ps -axo %cpu=,%mem=,rss=,etime=,comm= -r 2>/dev/null | head -n 12 | fence

        sec "launchd agents with a non-zero last exit status"
        launchctl list 2>/dev/null | awk 'NR>1 && $2 != 0 && $2 != "-" && $3 !~ /^com\.apple\./ {print}' | head -n 40 | fence

        sec "Crash reports written in the last 15 min"
        find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -mmin -15 \( -name '*.ips' -o -name '*.crash' -o -name '*.diag' \) 2>/dev/null | head -n 10 | fence

        sec "Secure input owner (if a process holds the keyboard)"
        /usr/sbin/ioreg -l -w 0 2>/dev/null | grep -o 'kCGSSessionSecureInputPID[^,}]*' | head -n 3 | fence

        sec "Keyboards / pointing devices connected"
        /usr/bin/hidutil list 2>/dev/null | awk 'NR==1 || /Keyboard|Mouse|Trackpad|TOTEM|Totem|ZMK/' | cut -c1-160 | head -n 12 | fence

        sec "Network"
        {
          wifidev="$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $2; exit}')"
          echo "wifi ($wifidev): $(/usr/sbin/networksetup -getairportnetwork "''${wifidev:-en0}" 2>/dev/null | sed 's/^.*: //')"
          echo "online: $(/sbin/ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 && echo yes || echo NO)"
          echo "dns: $(/usr/bin/dscacheutil -q host -a name apple.com 2>/dev/null | grep -c ip_address) answers for apple.com"
          if command -v tailscale >/dev/null 2>&1; then echo "tailscale: $(tailscale status --peers=false 2>&1 | head -n 1)"; else echo "tailscale: not installed"; fi
        } | fence

        sec "Power / uptime / last wake"
        {
          echo "uptime: $(/usr/bin/uptime)"
          /usr/bin/pmset -g batt 2>/dev/null | tail -n 1
          /usr/bin/pmset -g log 2>/dev/null | grep -E 'Wake from|DarkWake to FullWake|Entering Sleep' | tail -n 3
        } | fence

        sec "Rebuild / generation state"
        {
          echo "system generation: $(readlink /run/current-system 2>/dev/null)  ($(stat -f '%Sm' /run/current-system 2>/dev/null))"
          echo "home-manager generation: $(readlink "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null)  ($(stat -f '%Sm' "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null))"
          echo "flake git status (staged/unstaged, first 20):"
          git -C ${repo} status --short 2>/dev/null | head -n 20
        } | fence

        sec "launchd spawn/exit events in the last 100 s"
        (timeout 8 /usr/bin/log show --last 100s --style compact --predicate 'process == "launchd" AND (eventMessage CONTAINS "exited" OR eventMessage CONTAINS "spawn" OR eventMessage CONTAINS "Could not")' 2>/dev/null | grep -v 'com.apple.' | tail -n 30 || true) | fence

        sec "Other live Oops sessions"
        (tmux -L oops list-windows -a -F '#{session_name}:#{window_index} #{window_name} #{@oops_ts}' 2>/dev/null || echo "(none)") | fence

        sec "Recently modified logs (last 10 min): ~/.local/state, /tmp"
        while IFS= read -r f; do
          echo; echo "### $f"; tail -n 25 "$f" 2>/dev/null | fence
        done < <(find "$HOME/.local/state" /tmp -maxdepth 3 -type f -mmin -10 \( -name '*.log' -o -name '*.err' -o -name '*.out' \) -size +0 2>/dev/null | grep -v "/oops/" | head -n 12)
      } > context.md 2>&1

      # ---- terminal: the focused kitty window + recent shell history -------------
      {
        echo "# Terminal at trigger"
        echo
        echo "## Focused kitty window (screen, then last command output)"
        got=0
        for sock in "$HOME"/.local/state/kitty/*.sock /tmp/kitty-* "$HOME"/Library/Caches/kitty/*.sock; do
          [ -S "$sock" ] || continue
          if kitty @ --to "unix:$sock" ls >/dev/null 2>&1; then
            echo; echo "(socket $sock)"; echo
            kitty @ --to "unix:$sock" get-text --match state:focused --extent screen 2>/dev/null | tail -n 60 | fence
            echo; echo "last command output:"; kitty @ --to "unix:$sock" get-text --match state:focused --extent last_cmd_output 2>/dev/null | tail -n 40 | fence
            got=1
          fi
        done
        if [ "$got" = 0 ]; then
          if kitty @ ls >/dev/null 2>&1; then
            kitty @ get-text --match state:focused --extent screen 2>/dev/null | tail -n 60 | fence
            echo; echo "last command output:"; kitty @ get-text --match state:focused --extent last_cmd_output 2>/dev/null | tail -n 40 | fence
          else
            echo "(kitty remote control not reachable: no socket / allow_remote_control off)"
          fi
        fi
        echo; echo "## Last 25 zsh commands (~/.zsh_history, newest last)"
        tail -n 25 "$HOME/.zsh_history" 2>/dev/null | sed -E 's/^: ([0-9]+):[0-9]+;/\1  /' | awk '{ if ($1 ~ /^[0-9]+$/) { cmd=strftime("%H:%M:%S", $1); $1=cmd } print }' | fence
      } > terminal.txt 2>&1

      # ---- browser, dictation, clipboard ----------------------------------------
      ${pkgs.python3}/bin/python3 ${browserHistory} > browser-history.md 2>&1 || true
      ${pkgs.python3}/bin/python3 ${dictations} > dictations.md 2>&1 || true
      { echo "# Clipboard at trigger (first 2000 chars)"; echo; /usr/bin/pbpaste 2>/dev/null | head -c 2000; echo; } > clipboard.txt

      # ---- slow context, detached ------------------------------------------------
      ( timeout 25 /usr/bin/log show --last 100s --style compact \
          --predicate 'messageType == error OR messageType == fault' 2>&1 \
          | tail -n 400 > unified-log-errors.txt ) >/dev/null 2>&1 &
      if [ -d screens ]; then
        # The 2/s ring (~180 frames) is shrunk into screens/ by oops_ring.zsh,
        # which writes INDEX.txt last and an ocr-list.txt (last 10 s + one per
        # 5 s): OCR of every frame would take minutes.
        ( for _ in $(seq 60); do [ -f screens/INDEX.txt ] && break; sleep 0.5; done
          if [ -f screens/ocr-list.txt ]; then list=$(sed 's|^|screens/|' screens/ocr-list.txt); else list=$(ls screens/*.jpg); fi
          for f in $list; do [ -f "$f" ] && tesseract "$f" "''${f%.jpg}" --psm 3 >/dev/null 2>&1 || true; done ) >/dev/null 2>&1 &
      fi

      if [ "$dry" = 1 ]; then
        echo "dry run: context written to $dir"; exit 0
      fi

      # ---- Claude ----------------------------------------------------------------
      claude_bin="$HOME/.npm-packages/bin/claude"
      [ -x "$claude_bin" ] || claude_bin="$HOME/.local/bin/claude"
      [ -x "$claude_bin" ] || claude_bin="$(command -v claude || true)"
      if [ -z "$claude_bin" ]; then
        /usr/bin/osascript -e 'display notification "no claude binary found" with title "Oops"'
        exit 1
      fi
      note="$(cat note.txt 2>/dev/null || true)"
      first="Oops incident: $dir
Read $dir/keys.log, note.txt, front.txt, context.md, terminal.txt, browser-history.md, dictations.md and screens/INDEX.txt now, and look at the screenshots around the failure (unified-log-errors.txt and screens/*.txt OCR land within ~30 s).
Matt's note: ''${note:-(none — infer from keys.log and the screenshots)}"
      printf '%s\n' "$first" > first-message.txt
      # One tmux window (tab) per incident in the session "oops" on a dedicated
      # socket; the kitty window is just a view of it — close it and the repairs
      # keep running. AeroSpace parks
      # the window on workspace "oops" without stealing focus (aerospace.nix);
      # the sketchybar `oops` item lights up once the session exists — the
      # detached trigger below fires after tmux has had time to create it.
      #   reattach:  oops --attach            (or Raycast "Oops: Reattach")
      #   by hand:   tmux -L oops attach -t oops
      ( sleep 3; /opt/homebrew/bin/sketchybar --trigger oops_update ) >/dev/null 2>&1 &
      # No window is opened here. Any new kitty window flashes on Matt's current
      # workspace (~200 ms, re-tiling it) before AeroSpace parks it on "oops",
      # and the kitty app activation then pulls focus; the earlier park rule and
      # focus-restore loop only undid that after it was visible (Oops
      # 20260914-083945, Matt: "I want it so that it's seamless"). The session
      # starts detached and is marked @oops_pending; `oops --view` opens its
      # window when Matt goes to workspace "oops" (AeroSpace workspace hook,
      # sketchybar click), or right away if he is already there. If the window
      # is already open, the incident is just a new tab: selected when Matt is
      # elsewhere (it is what he sees on arrival), left in the background when
      # he is on "oops" reading another tab.
      onws=0
      [ "$(/opt/homebrew/bin/aerospace list-workspaces --focused 2>/dev/null || true)" = "oops" ] && onws=1
      tab="''${ts:4:4}-''${ts:9:4}"
      if tmux -L oops has-session -t '=oops:' 2>/dev/null; then
        bg=""; [ "$onws" = 1 ] && attached && bg="-d"
        win="$(tmux -L oops new-window $bg -P -F '#{window_id}' -t '=oops:' -n "$tab" \
          -e COLORTERM=truecolor -c "${repo}" -- \
          "$claude_bin" --permission-mode auto \
            --append-system-prompt "$(cat ${brief})" \
            "$first")"
      else
        tmux -L oops new-session -d -x 200 -y 60 -e COLORTERM=truecolor \
          -s oops -n "$tab" -c "${repo}" -- \
          "$claude_bin" --permission-mode auto \
            --append-system-prompt "$(cat ${brief})" \
            "$first"
        win="$(tmux -L oops display-message -p -t '=oops:' '#{window_id}')"
      fi
      tmux -L oops set-option -w -t "$win" @oops_ts "$ts"
      attached || tmux -L oops set-option -t '=oops:' @oops_pending 1
      if [ "$onws" = 1 ]; then
        "$0" --view || true
      fi
    '';
  };

  # `mac-assistant` keeps working as a name (AeroSpace bound it since 2026-09-10):
  # it is now just the Oops prompt.
  macAssistant = pkgs.writeShellScriptBin "mac-assistant" ''
    exec /usr/bin/open -g "hammerspoon://oops"
  '';
in {
  home.packages = [oops macAssistant];

  # Stable paths Hammerspoon and Raycast can call without waiting for `rebuild`.
  home.file.".local/bin/oops".source = "${oops}/bin/oops";
  home.file.".local/bin/mac-assistant".source = "${macAssistant}/bin/mac-assistant";

  # Raycast: "Oops" with an optional note (empty = infer), and "Oops: Reattach".
  home.file.".config/raycast/scripts/oops.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Oops (something went wrong)
      # @raycast.mode silent
      # @raycast.icon 🆘
      # @raycast.packageName System
      # @raycast.argument1 { "type": "text", "placeholder": "what went wrong (optional)", "optional": true }
      # @raycast.description Hand the last 90 s of keystrokes, screenshots + context to Claude: logs the problem, tries to fix it.
      note="''${1:-}"
      enc="$(${pkgs.python3}/bin/python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$note")"
      # no echo: in silent mode Raycast shows any output as a HUD, and Matt does
      # not want a message that Oops ran (2026-09-13)
      /usr/bin/open -g "hammerspoon://oops?text=$enc&prompt=0"
    '';
  };
  home.file.".config/raycast/scripts/oops-attach.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Oops: Reattach Last Session
      # @raycast.mode silent
      # @raycast.icon 🆘
      # @raycast.packageName System
      # @raycast.description Reopen the floating window of the most recent Oops Claude session (tmux -L oops).
      exec "$HOME/.local/bin/oops" --attach
    '';
  };
}
