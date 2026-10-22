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
#     clicks, app + workspace switches (screenshots come from Dayflow's
#     recording via ~/.hammerspoon/oops_dayflow.py, 2026-10-05; the 2/s
#     oops_ring.zsh is retired); on trigger it writes ~/.local/state/oops/<ts>/{keys.log,
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
#   screens/ + *.txt       what he saw (Dayflow's frames, one per 5-10 s, + OCR)
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
      screens/   — Dayflow's screenshots of the last 90 s (one per 5-10 s, of
                   the active display, ~1670 px; copied from Dayflow's
                   recording, Oops takes none of its own) plus T-000.0s.jpg at
                   the trigger when screencapture manages it (INDEX.txt =
                   time/workspace/app/window per frame plus a "# …" line when
                   frames are missing, written when the frames are done; *.txt =
                   OCR of every frame, written within ~60 s). No frames at all
                   usually means Dayflow was not recording. Open the
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
       never `task add`. If you built or changed something Matt starts himself
       (a key, a command, a Raycast entry, an app screen, a job that now does
       something on its own), register it so he hears about it:
       `~/Obsidian/Main/scripts/built-for-you/bfy add --id <kind:slug> --name …
       --kind … --where key=…,doc=… --built-by "Oops <ts>" --change new|changed`
       (it writes the trigger line and the loudness; a plain repair needs nothing).
    5. Finish with the report described in <final_report>.
    </procedure>

    <hard_rules>
    - Verify, don't assert: exercise the real path a human would use and paste
      the output. "The config looks right" is not evidence. A fix whose only
      proof is that it built is not verified.
    - APPLY YOUR OWN FIXES, system ones included: you may run the rebuild
      yourself, and a fix left staged for Matt to apply is not finished work.
        cd ${repo} && git add -A . && sudo darwin-rebuild switch --flake .#matts-mac
      (that is Matt's `rebuild` alias). Run `sudo -n true` first: it succeeds
      while his sudo timestamp is still valid, and otherwise the switch raises
      a Touch ID sheet on his screen — so say in the window that you are
      rebuilding and why before you start it, and if the sheet goes unanswered
      say the fix is waiting on that touch. A switch takes minutes: give it a
      generous timeout and do not start a second one concurrently.
      Home-only changes (modules/home/**) can also be applied without sudo:
        cd ${repo} && git add -A . && nix build .#darwinConfigurations.matts-mac.config.home-manager.users.matth.home.activationPackage -o /tmp/hm-oops && HOME_MANAGER_BACKUP_EXT=hm-backup /tmp/hm-oops/activate
      but that leaves new binaries off PATH (/etc/profiles/per-user is
      root-managed) and does not survive a reboot, so follow it with the
      rebuild whenever the fix has to last.
    - Never run `sfltool`, or anything else that pops a macOS password/admin
      prompt you cannot answer.
    - After a rebuild, verify against the LIVE system, never the built closure,
      and remember that a long-running app (Dia, Raycast, Hammerspoon) may need
      a restart before it picks the change up.
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

    <auto_close>
    A session that fully solved its incident closes its own tab, so the oops
    window only holds sessions that still need Matt. Your LAST tool call, just
    before the final report, writes final-report line 1 to
    <incident dir>/resolved, and ONLY when all of these hold:
    - every todo.md row is [x] and fixed/done: none needs-matt, open or partial;
    - the fix is applied to the live system and verified; nothing waits on a
      rebuild, a Touch ID sheet, an app restart or a check Matt has to do;
    - there is no open question and nothing Matt needs to know beyond what the
      problem log entry already says.
    A Stop hook then closes the tab ~5 s after your turn ends (it also refuses
    while todo.md has a "- [ ]" row). In every other case do not write the
    file: the tab stays open for Matt. If Matt sends something after you wrote
    it, delete <incident dir>/resolved before you work on it.
    </auto_close>
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

  # Claude Code Stop hook, loaded only into Oops sessions (--settings below). A
  # session that fully solved its incident ends itself (Oops 20261019-145225,
  # Matt: "if claude successfully solves the problem, then the claude code
  # session should automatically stop and be killed, if there are open questions
  # … it shouldn't be killed"): once it wrote <incident>/resolved and todo.md has
  # no open row, its tmux pane is killed a few seconds after the final report.
  # No marker, an open row, or no tmux pane → the tab stays.
  stopHook = pkgs.writeShellApplication {
    name = "oops-stop-hook";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.tmux];
    text = ''
      input="$(cat)"
      d="''${OOPS_DIR:-}"
      [ -n "$d" ] && [ -n "''${TMUX_PANE:-}" ] && [ -s "$d/resolved" ] && [ -f "$d/todo.md" ] || exit 0
      if grep -q '^[[:space:]]*- \[ \]' "$d/todo.md"; then exit 0; fi
      sid="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || true)"
      printf '%s closed pane %s; reopen with: claude -r %s\n' "$(date '+%F %T')" "$TMUX_PANE" "$sid" >> "$d/closed.txt"
      # Detached and delayed, so Claude finishes writing its transcript first.
      # tmux finds the server through $TMUX, inherited from the pane.
      # shellcheck disable=SC2016
      nohup sh -c 'sleep 5; tmux kill-pane -t "$1"' _ "$TMUX_PANE" >/dev/null 2>&1 &
    '';
  };
  # The API-error auto-resume (Oops 20261019-145311) is global now, in
  # ~/.claude/settings.json (claude-api-resume.nix); Oops sessions get it there.
  oopsSettings = pkgs.writeText "oops-claude-settings.json" (builtins.toJSON {
    hooks.Stop = [{hooks = [{type = "command"; command = "${stopHook}/bin/oops-stop-hook";}];}];
  });

  oops = pkgs.writeShellApplication {
    name = "oops";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gawk pkgs.gnused pkgs.tesseract pkgs.tmux];
    text = ''
            # oops [--dry-run] <incident-dir> | oops --attach [ts] | oops --note <dir> <text>
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

            if [ "''${1:-}" = "--note" ]; then
              # Deliver a late note to the session already running on an incident,
              # through the same channel Matt uses by hand (type into its tmux tab).
              # Used when ⌥` is pressed again right after one sent with a BLANK note:
              # that is the same complaint, and a second recording would cost a second
              # Opus session and a second problem-log entry (Oops 20260919-181349).
              d="''${2:-}"; shift 2 2>/dev/null || true
              msg="$*"
              want="$(basename "$d")"
              [ -n "$msg" ] || { echo "oops --note: empty note" >&2; exit 2; }
              idx="$(tmux -L oops list-windows -t '=oops:' -F '#{window_index} #{@oops_ts}' 2>/dev/null | awk -v t="$want" '$2 == t {print $1}')"
              [ -n "$idx" ] || { echo "oops --note: no live tab for $want" >&2; exit 1; }
              tmux -L oops send-keys -t "=oops:$idx" -l "$msg"
              # Claude's TUI drops an Enter that arrives in the same read as the text.
              sleep 0.4
              tmux -L oops send-keys -t "=oops:$idx" Enter
              exit 0
            fi

            dry=0
            if [ "''${1:-}" = "--dry-run" ]; then dry=1; shift; fi
            dir="''${1:-}"
            if [ -z "$dir" ] || [ ! -d "$dir" ]; then
              echo "usage: oops [--dry-run] <incident-dir>   |   oops --attach [ts]   |   oops --note <dir> <text>" >&2
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

              # Added 2026-09-21 (Oops 20260921-091206). Hammerspoon runs every
              # hs.eventtap and hs.hotkey callback on ONE main thread, and a
              # synchronous hs.axuielement read on that thread blocks until the
              # target app answers. When something parks it, Hammerspoon stays
              # "running" and its taps stay "enabled" while silently delivering
              # nothing — brightness keys, remaps, even the Oops recorder. That
              # failure is invisible in every other section here, and it cost a
              # whole session to find once, so probe it directly.
              sec "Hammerspoon main-thread health"
              {
                if [ "$(timeout 3 /opt/homebrew/bin/hs -c 'return "ok"' 2>&1 | tail -n 1)" = "ok" ]; then
                  echo "hs -c round trip: OK (main thread is servicing callbacks)"
                else
                  echo "hs -c round trip: NO REPLY within 3 s"
                  echo "  => the main thread is blocked (or IPC is down). While it is, EVERY hs.eventtap and"
                  echo "     hs.hotkey is dead even though the taps report enabled. Do not trust any 'the tap"
                  echo "     is enabled' check while this line says NO REPLY."
                  echo "     Confirm: run  sample <the Hammerspoon pid> 3  (pgrep -x Hammerspoon) and look for"
                  echo "     axuielement_getAttributeValue sitting in mach_msg under an HSTimer callback."
                  echo "     Usual cause: a module doing synchronous AX reads on a timer. See the 2026-09-21"
                  echo "     problem-log entry (btm_mute.lua swept Notification Center every 5 s)."
                fi
                timeout 3 /opt/homebrew/bin/hs -c 'local o={} for _,n in ipairs({"oops","btmMute","tileGuard","bitwardenFollow","screenRecord","focusGate","monitorMode","brightnessBlackout","hoverClose","pausedApps","displayArrangement"}) do o[#o+1]=n.."="..tostring(_G[n]~=nil) end return table.concat(o," ")' 2>&1 | tail -n 1
              } | fence

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
              # ~/.hammerspoon/oops_dayflow.py copies Dayflow's frames (~18) into
              # screens/ and writes INDEX.txt last, with an ocr-list.txt.
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
            # Pinned, not inherited: ~/.claude/settings.json "model" is whatever /model
            # last picked in ANY session (it was Fable on 2026-09-12), and Matt wants
            # Oops on Opus regardless (Oops 20260919-100723).
            oops_model="opus[1m]"
            # Effort pinned the same way: medium, not whatever /effort last saved
            # (Oops 20261020-101905, Matt: "medium effort, not X high").
            oops_effort="medium"
            onws=0
            [ "$(/opt/homebrew/bin/aerospace list-workspaces --focused 2>/dev/null || true)" = "oops" ] && onws=1
            tab="''${ts:4:4}-''${ts:9:4}"
            if tmux -L oops has-session -t '=oops:' 2>/dev/null; then
              bg=""; [ "$onws" = 1 ] && attached && bg="-d"
              win="$(tmux -L oops new-window $bg -P -F '#{window_id}' -t '=oops:' -n "$tab" \
                -e COLORTERM=truecolor -e OOPS_DIR="$dir" -c "${repo}" -- \
                "$claude_bin" --permission-mode auto --model "$oops_model" --effort "$oops_effort" \
                  --settings ${oopsSettings} \
                  --append-system-prompt "$(cat ${brief})" \
                  "$first")"
            else
              tmux -L oops new-session -d -x 200 -y 60 -e COLORTERM=truecolor -e OOPS_DIR="$dir" \
                -s oops -n "$tab" -c "${repo}" -- \
                "$claude_bin" --permission-mode auto --model "$oops_model" --effort "$oops_effort" \
                  --settings ${oopsSettings} \
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
