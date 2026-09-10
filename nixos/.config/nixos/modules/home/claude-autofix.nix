# claude-autofix — when a script or service fails, hand the failure to a headless
# Claude Opus instance that diagnoses it, fixes it declaratively in this flake,
# rebuilds, and reports back.
#
# Why this shape:
#   * The watcher follows the journal rather than relying on OnFailure= alone,
#     because "any failure of a script that is logged" includes plain scripts
#     (vicinae commands, ~/.local/bin) that are not systemd units at all. Those
#     log an AUTOFIX marker via `logger`; systemd units are picked up from their
#     own failure records. An OnFailure= template is exported too, for units that
#     want a synchronous trigger.
#   * Everything runs as matth, not root: the fixer needs ~/.claude credentials
#     and the repo, and `sudo nixos-rebuild` is already passwordless here.
#   * Notifications go through ntfy rather than notify-send, because the ntfy
#     topic Matt already subscribes to fans out to BOTH the desktop (via
#     ntfy-desktop-sub) and his phone, and works from a unit with no session bus.
{pkgs, ...}: let
  repo = "/home/matth/dotfiles/nixos/.config/nixos";
  stateDir = "/home/matth/.local/state/claude-autofix";
  ntfyTopic = "http://server.matthandzel.com:8124/claude";

  # Subjects that must never be auto-fixed. Repairing the repair loop, or a
  # crash-looping compositor piece, turns one failure into a fork bomb of Opus
  # instances. Matched as a substring against the subject name.
  denylist = [
    "claude-autofix"
    "claude-desktop"
    # A failing display/session unit usually means the session is mid-teardown
    # (logout, suspend); "fixing" it is noise and it recovers on its own.
    "graphical-session"
    "xdg-desktop-portal"
    "systemd-oomd"
  ];

  autofix = pkgs.writeShellApplication {
    name = "claude-autofix";
    # claude-code is pinned here rather than relied on from PATH: this runs from
    # a systemd user unit, whose PATH does not include the per-user profile.
    runtimeInputs = with pkgs; [coreutils systemd curl util-linux git jq gnugrep gnused claude-code nix];
    text = ''
                  # claude-autofix <subject> [--log-file FILE] [--exit-code N] [--detail TEXT]
                  #
                  # <subject> is a systemd unit name or a bare script name.
                  #
                  # errexit is deliberately OFF (writeShellApplication turns it on).
                  # Nearly every command here is a best-effort diagnostic against a
                  # thing that is BY DEFINITION broken — `systemctl status` alone exits
                  # 3 for a failed unit — so errexit would abort context collection
                  # before the repair ever starts. Failures are checked explicitly.
                  set +o errexit
                  set -uo pipefail

                  subject="''${1:-}"
                  if [ -z "$subject" ]; then
                    echo "usage: claude-autofix <subject> [--log-file F] [--exit-code N] [--detail TEXT]" >&2
                    exit 2
                  fi
                  shift

                  log_file=""
                  exit_code=""
                  detail=""
                  while [ $# -gt 0 ]; do
                    case "$1" in
                      --log-file) log_file="''${2:-}"; shift 2 ;;
                      --exit-code) exit_code="''${2:-}"; shift 2 ;;
                      --detail) detail="''${2:-}"; shift 2 ;;
                      *) shift ;;
                    esac
                  done

                  STATE_DIR="${stateDir}"
                  mkdir -p "$STATE_DIR/runs"

                  slug="$(printf '%s' "$subject" | sed 's#[^A-Za-z0-9._-]#_#g')"
                  COOLDOWN_SECONDS="''${AUTOFIX_COOLDOWN:-1800}"
                  DAILY_CAP="''${AUTOFIX_DAILY_CAP:-8}"

                  notify() {
                    # $1 = title, $2 = body, $3 = priority, $4 = tags
                    curl -s -m 10 \
                      -H "Title: $1" \
                      -H "Priority: ''${3:-default}" \
                      -H "Tags: ''${4:-wrench}" \
                      -d "$2" "${ntfyTopic}" >/dev/null 2>&1 || true
                  }

                  for bad in ${builtins.concatStringsSep " " (map (d: "\"${d}\"") denylist)}; do
                    case "$subject" in
                      *"$bad"*)
                        echo "autofix: '$subject' is denylisted, ignoring" >&2
                        exit 0
                        ;;
                    esac
                  done

                  # Cooldown: one attempt per subject per window. Without this a unit with
                  # Restart=on-failure spawns an Opus instance on every restart.
                  last_file="$STATE_DIR/last-$slug"
                  if [ -f "$last_file" ]; then
                    last=$(cat "$last_file" 2>/dev/null || echo 0)
                    now=$(date +%s)
                    if [ $((now - last)) -lt "$COOLDOWN_SECONDS" ]; then
                      echo "autofix: '$subject' fixed $((now - last))s ago, within cooldown" >&2
                      exit 0
                    fi
                  fi

                  # Daily cap across all subjects — a blunt backstop against a cascade.
                  today=$(date +%F)
                  count_file="$STATE_DIR/count-$today"
                  count=$(cat "$count_file" 2>/dev/null || echo 0)
                  if [ "$count" -ge "$DAILY_CAP" ]; then
                    echo "autofix: daily cap ($DAILY_CAP) reached" >&2
                    notify "Autofix paused" "Daily cap of $DAILY_CAP autofix runs reached; '$subject' was not repaired." "default" "warning"
                    exit 0
                  fi

                  # Serialize: one Opus instance at a time. Concurrent runs would race on the
                  # same git worktree and on nixos-rebuild.
                  exec 9>"$STATE_DIR/global.lock"
                  if ! flock -n 9; then
                    echo "autofix: another repair is already running" >&2
                    exit 0
                  fi

                  date +%s >"$last_file"
                  echo $((count + 1)) >"$count_file"

                  # Remember where Matt's checkout was. A repair fires whenever a unit
                  # breaks — possibly while he is mid-task on a feature branch — and
                  # must not leave him standing on the autofix branch afterwards.
                  orig_branch="$(git -C "${repo}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

                  ts=$(date +%Y%m%d-%H%M%S)
                  run_dir="$STATE_DIR/runs/$ts-$slug"
                  mkdir -p "$run_dir"
                  ctx="$run_dir/context.txt"
                  summary_file="$run_dir/SUMMARY.md"
                  question_file="$run_dir/QUESTION.md"
                  claude_log="$run_dir/claude.log"

                  # ---- collect the error context -------------------------------------
                  {
                    echo "# Failure report"
                    echo
                    echo "subject: $subject"
                    echo "host: laptop"
                    echo "when: $(date -Is)"
                    [ -n "$exit_code" ] && echo "exit code: $exit_code"
                    [ -n "$detail" ] && { echo; echo "## Reported detail"; echo; echo "$detail"; }

                    if systemctl --user cat "$subject" >/dev/null 2>&1; then
                      echo; echo "## systemd user unit"; echo
                      echo '```'
                      systemctl --user status "$subject" --no-pager -l 2>&1 | head -n 40
                      echo '```'
                      echo; echo "## journal (user unit, last 200 lines)"; echo
                      echo '```'
                      journalctl --user -u "$subject" -n 200 --no-pager -o cat 2>&1
                      echo '```'
                      echo; echo "## unit definition"; echo
                      echo '```'
                      systemctl --user cat "$subject" --no-pager 2>&1
                      echo '```'
                    elif systemctl cat "$subject" >/dev/null 2>&1; then
                      echo; echo "## systemd system unit"; echo
                      echo '```'
                      systemctl status "$subject" --no-pager -l 2>&1 | head -n 40
                      echo '```'
                      echo; echo "## journal (system unit, last 200 lines)"; echo
                      echo '```'
                      journalctl -u "$subject" -n 200 --no-pager -o cat 2>&1
                      echo '```'
                      echo; echo "## unit definition"; echo
                      echo '```'
                      systemctl cat "$subject" --no-pager 2>&1
                      echo '```'
                    else
                      echo; echo "## journal (free-text match on subject, last 200 lines)"; echo
                      echo '```'
                      journalctl --since "-30 min" --no-pager -o cat 2>&1 | grep -F "$subject" | tail -n 200
                      echo '```'
                    fi

                    if [ -n "$log_file" ] && [ -r "$log_file" ]; then
                      echo; echo "## log file: $log_file"; echo
                      echo '```'
                      tail -n 200 "$log_file" 2>&1
                      echo '```'
                    fi
                  } >"$ctx" 2>&1

                  short="$(grep -viE '^(#|\s*$|```)' "$ctx" | tail -n 3 | head -c 300)"

                  notify "🔧 Autofix started — $subject" \
                    "Claude Opus is diagnosing the failure now. Run: $run_dir

            $short" \
                    "default" "wrench,robot"

                  # ---- hand it to Opus ------------------------------------------------
                  branch="autofix/$slug-$ts"

                  prompt="You are an automated repair agent running headless on Matt's NixOS laptop.
            A script or service just FAILED. Your job is to diagnose the root cause and fix it
            DECLARATIVELY in the flake at ${repo}, then prove the fix works.

            The full failure report is at: $ctx
            READ THAT FILE FIRST.

            Rules:
            1. Work in ${repo}. Create and switch to git branch '$branch' before editing.
            2. Fix the ROOT CAUSE in the Nix modules — never patch generated files under
               /nix/store, ~/.config, or ~/.local/share directly, and never introduce
               imperative state (manual systemctl enable, hand-installed packages).
            3. Format every Nix file you touch with alejandra.
            4. Validate, and paste real command output as proof:
               - If your change touches ONLY modules/home/**, apply it with:
                   cd ${repo} && git add --all . && nix build .#nixosConfigurations.laptop.config.home-manager.users.matth.home.activationPackage -o /tmp/hm-activation-result && HOME_MANAGER_BACKUP_EXT=hm-backup HOME_MANAGER_BACKUP_OVERWRITE=1 /tmp/hm-activation-result/activate
               - If it touches modules/core/** or hosts/**, apply it with:
                   cd ${repo} && sudo nixos-rebuild switch --flake .#laptop
               You ARE authorized to rebuild and switch this machine. NixOS generations make
               it recoverable.
            5. Then actually EXERCISE the thing that failed (start the unit, run the script)
               and confirm it now works. A green systemctl status is NOT proof on its own —
               check that it does its job.
            6. Commit your fix to the branch '$branch' with a clear message. Commit ONLY the
               files you actually changed — the working tree carries unrelated in-progress
               edits, so never use 'git add --all' or 'git commit -a'. Do NOT merge to main
               and do NOT push. Matt was on branch '$orig_branch' before this run.
            7. Write a 3-8 line plain-text summary of what was broken, what you changed, and
               the evidence it works, to: $summary_file
            8. If — and only if — you genuinely cannot proceed without information only Matt
               has (a credential, a preference, an intent you cannot infer), write the single
               most important question to: $question_file
               Then stop. Do not guess at hard requirements.
            9. If the failure turns out to be transient or external (network blip, device
               unplugged) and no code change is warranted, say so in $summary_file and make
               no changes.

            Be surgical. Change the minimum needed to fix this specific failure."

                  # The prompt goes over stdin, not as a positional argument: --add-dir
                  # is variadic and silently swallows a trailing positional as a second
                  # directory, leaving claude with no input at all.
                  printf '%s' "$prompt" | timeout 1800 claude \
                    --print \
                    --model opus \
                    --permission-mode bypassPermissions \
                    --add-dir "${repo}" >"$claude_log" 2>&1
                  rc=$?

                  # ---- put the checkout back ------------------------------------------
                  # The fix stays on its own branch; only the working checkout returns.
                  restored=""
                  if [ -n "$orig_branch" ] && [ "$orig_branch" != "HEAD" ]; then
                    current="$(git -C "${repo}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
                    if [ "$current" != "$orig_branch" ]; then
                      if git -C "${repo}" checkout "$orig_branch" >/dev/null 2>&1; then
                        restored="
      Your checkout was returned to '$orig_branch'."
                      else
                        restored="
      WARNING: could not return your checkout to '$orig_branch'; it is on '$current'."
                      fi
                    fi
                  fi

                  # ---- report back -----------------------------------------------------
                  if [ -s "$question_file" ]; then
                    notify "❓ Autofix needs you — $subject" \
                      "$(head -c 900 "$question_file")

            Branch: $branch
            Run dir: $run_dir$restored" \
                      "high" "question,robot"
                    exit 0
                  fi

                  if [ "$rc" -eq 124 ]; then
                    notify "⏱️ Autofix timed out — $subject" \
                      "Opus hit the 30-minute limit and was stopped. Nothing was merged. Log: $claude_log" \
                      "high" "warning"
                    exit 1
                  fi

                  if [ "$rc" -ne 0 ]; then
                    notify "❌ Autofix failed — $subject" \
                      "Opus exited $rc without producing a fix. Log: $claude_log

            $(tail -c 500 "$claude_log" 2>/dev/null)" \
                      "high" "x,robot"
                    exit 1
                  fi

                  if [ -s "$summary_file" ]; then
                    body="$(head -c 1200 "$summary_file")"
                  else
                    body="$(tail -c 800 "$claude_log" 2>/dev/null)"
                  fi

                  changed="$(cd "${repo}" && git log --oneline main.."$branch" 2>/dev/null | head -n 5)"
                  notify "✅ Autofix done — $subject" \
                    "$body

            Branch: $branch
            $changed$restored" \
                    "default" "white_check_mark,robot"
    '';
  };

  # Journal watcher. Follows the merged system+user journal and turns failure
  # records into autofix runs. Written in Python for reliable line-buffered JSON
  # parsing — a shell read-loop over `journalctl -f` is fragile here.
  watcher = pkgs.writers.writePython3Bin "claude-autofix-watch" {flakeIgnore = ["E501"];} ''
    import itertools
    import json
    import os
    import re
    import subprocess
    import sys

    AUTOFIX = "${autofix}/bin/claude-autofix"

    # systemd's own failure records. UNIT/USER_UNIT carries the failing unit.
    UNIT_FAILURE = re.compile(
        r"(Failed with result|Failed to start|Start request repeated too quickly|entered failed state)"
    )
    # Explicit marker any plain script can emit:
    #   logger -t autofix "AUTOFIX: <subject>: <what went wrong>"
    MARKER = re.compile(r"AUTOFIX:\s*([^:]+):\s*(.*)")

    # systemd's own anonymous transient units (`systemd-run` with no --unit).
    # They are scaffolding, not a service worth repairing, and the repair units
    # spawned below would otherwise re-enter this loop as new failures.
    TRANSIENT = re.compile(r"^run-[pu]?\d+(-i\d+)?\.(service|scope)$")

    SYSTEMD_RUN = "${pkgs.systemd}/bin/systemd-run"
    _seq = itertools.count()


    def dispatch(subject, detail):
        subject = subject.strip()
        if not subject or TRANSIENT.match(subject):
            return
        slug = re.sub(r"[^A-Za-z0-9._-]", "_", subject)[:80]
        # Each repair gets its OWN transient unit, so it survives a restart of
        # this watcher and its (large, node-based) memory is accounted to itself
        # rather than to the watcher's cgroup. The claude-autofix- name prefix is
        # denylisted inside the fixer, so a failing repair cannot recurse.
        unit = f"claude-autofix-{slug}-{os.getpid()}-{next(_seq)}"
        print(f"autofix-watch: dispatching {subject} as {unit}", flush=True)
        try:
            subprocess.Popen(
                [
                    SYSTEMD_RUN, "--user", "--quiet", "--collect",
                    "--unit", unit,
                    "--description", f"Claude Opus repair for {subject}",
                    "--property=MemoryMax=8G",
                    AUTOFIX, subject, "--detail", detail[:2000],
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:  # pragma: no cover - defensive
            print(f"autofix-watch: dispatch failed: {exc}", file=sys.stderr, flush=True)


    def main():
        cmd = [
            "${pkgs.systemd}/bin/journalctl",
            "--follow",
            "--lines", "0",
            "--merge",
            "--output", "json",
        ]
        env = dict(os.environ)
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, env=env)
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg = rec.get("MESSAGE") or ""
            if isinstance(msg, list):
                msg = " ".join(str(m) for m in msg)

            hit = MARKER.search(msg)
            if hit:
                dispatch(hit.group(1), hit.group(2) or msg)
                continue

            if UNIT_FAILURE.search(msg):
                unit = rec.get("USER_UNIT") or rec.get("UNIT") or rec.get("_SYSTEMD_UNIT") or ""
                # Only systemd itself reports unit failures; ignore an app that
                # merely logs the phrase.
                if unit and rec.get("_COMM") == "systemd":
                    dispatch(unit, msg)


    if __name__ == "__main__":
        main()
  '';
in {
  # pkgs.claude-code is deliberately NOT in home.packages. nixpkgs lags npm badly
  # (2.1.39 vs 2.1.219 on 2026-07-24) and putting it on PATH installs a second,
  # older `claude` at /etc/profiles/per-user/matth/bin/claude. Login shells hide
  # that — zsh prepends ~/.npm-packages/bin — but Hyprland's exec environment
  # does NOT carry the npm bin dir, so every hotkey-launched script silently got
  # the stale binary. That is what made SUPER+grave (nixos-assistant) die on
  # launch: 2.1.39 rejects `--permission-mode auto`, exits 1, and the tmux
  # session collapses instantly. The autofix scripts below still pin the package
  # explicitly via runtimeInputs, which is where a version-sensitive dependency
  # belongs — on PATH it was only ever an ambient footgun.
  home.packages = [autofix watcher];

  # Always-on watcher: any logged failure becomes an autofix run.
  systemd.user.services.claude-autofix-watch = {
    Unit = {
      Description = "Watch the journal for script/service failures and dispatch Claude Opus repairs";
      After = ["default.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${watcher}/bin/claude-autofix-watch";
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = ["default.target"];
  };

  # Synchronous trigger for units that want it: OnFailure=claude-autofix@%n.service
  systemd.user.services."claude-autofix@" = {
    Unit.Description = "Claude Opus repair for %i";
    Service = {
      Type = "oneshot";
      ExecStart = "${autofix}/bin/claude-autofix %i";
    };
  };
}
