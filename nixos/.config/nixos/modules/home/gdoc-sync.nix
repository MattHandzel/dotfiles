# Periodic two-way reconcile of every linked markdown ↔ Google Doc pair.
#
# A timer rather than `gdoc-sync watch --all`: watch polls every 15s, and with
# ~50 linked files that is thousands of Drive requests an hour for documents
# that change a few times a week. `sync --all` does the same safe three-way
# merge, just on a cadence that matches how fast the docs actually move.
#
# Files imported from a tabbed doc are marked pull-only in the state file, so
# this never pushes them back and never flattens their tabs.
#
# On the Mac each pass first runs `gdoc-sync mirror` (pkgs/gdoc-sync/
# mirror.patch): every Google Doc Matt owns or has opened and that is not linked
# yet lands in resources/google-docs/ as a pull-only file, so any doc can be
# opened from the vault without a manual `:Gdoc import` (Oops 2026-10-06). One
# Drive listing covers every doc, and only docs whose modifiedTime moved are
# rendered; `sync --all` skips mirrored files, so ~800 extra docs add no
# per-file Docs API reads. Mac only: two machines mirroring into one
# Syncthing'd vault would each import the same new doc.
{
  config,
  host,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  # The same derivation packages.nix puts on PATH — callPackage with identical
  # arguments yields the identical store path, so this does not build twice.
  gdoc-sync = pkgs.callPackage ../../pkgs/gdoc-sync/default.nix {
    src = inputs.gdoc-sync-src;
  };

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;

  # A failed mirror pass must not stop the reconcile, so no `set -e`; the
  # exit status is still sync's (2 = a conflict waiting for Matt). 200 new
  # docs a pass (~5 min) finishes the first ~800-doc import in about an hour.
  #
  # launchd has no After=network-online.target, so a pass that fires while the
  # Mac is offline or still joining Wi-Fi after wake died on getaddrinfo (exit
  # 1, a traceback, and "ERROR while syncing <first file>"; bug
  # err-gdoc-sync-20261019-200819). Wait up to ~30 s for Google to be
  # reachable, else skip the pass with exit 0: the next one is 15 min away.
  # The GDOC_SYNC_PROBE_* overrides exist for the bugs' repro scripts.
  mirrorThenSync = pkgs.writeShellScript "gdoc-sync-pass" ''
    probe_host=''${GDOC_SYNC_PROBE_HOST:-oauth2.googleapis.com}
    probe_port=''${GDOC_SYNC_PROBE_PORT:-443}
    online() {
      tries=''${GDOC_SYNC_PROBE_TRIES:-6}
      until /usr/bin/nc -z -G 3 "$probe_host" "$probe_port" 2>/dev/null; do
        tries=$((tries - 1))
        [ "$tries" -le 0 ] && return 1
        sleep 5
      done
    }
    if ! online; then
      echo "$(date '+%F %T') gdoc-sync: offline ($probe_host unreachable), skipping this pass"
      exit 0
    fi
    ${gdoc-sync}/bin/gdoc-sync mirror "$HOME/Obsidian/Main/resources/google-docs" --limit 200

    # The probe above only covers the start; a pass runs for minutes, and the
    # Mac sleeping, changing Wi-Fi, or the guest network's resolver dropping
    # one Google hostname for ~20 s (seen 2026-11-12: www.googleapis.com
    # unresolvable while oauth2.googleapis.com answered) used to crash sync
    # with a traceback and exit 1 (bug err-gdoc-sync-20261027-181808).
    # gdoc-sync now exits 75 when it loses the network: end the pass quietly,
    # the next one starts over. Only a streak of 4 such passes (~1 h) is
    # reported, so a lasting problem (one doc always timing out) stays loud.
    streak=''${GDOC_SYNC_STREAK_FILE:-$HOME/.local/state/gdoc-sync/network-streak}
    ${gdoc-sync}/bin/gdoc-sync sync --all
    rc=$?
    if [ "$rc" -ne 75 ]; then
      rm -f "$streak"
      exit "$rc"
    fi
    mkdir -p "$(dirname "$streak")"
    n=$(( $(cat "$streak" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$streak"
    if [ "$n" -lt 4 ]; then
      echo "$(date '+%F %T') gdoc-sync: lost Google mid-pass (offline or DNS blip, $n in a row); the next pass retries"
      exit 0
    fi
    echo "$(date '+%F %T') gdoc-sync: lost Google mid-pass $n passes in a row (about an hour); something is wrong"
    exit 75
  '';
in {
  config = scheduled {
    name = "gdoc-sync";
    description = "Reconcile linked Markdown files with their Google Docs";
    command =
      if isDarwin
      then ["${mirrorThenSync}"]
      else ["${gdoc-sync}/bin/gdoc-sync" "sync" "--all"];

    after = ["network-online.target"];
    wants = ["network-online.target"];

    # Calendar rather than OnBootSec/OnUnitActiveSec: those are monotonic, and
    # a user-manager timer combining them scheduled the first run and then
    # reported NextElapseUSecMonotonic=infinity — it fired once and never
    # again. `Persistent` is also only honoured for calendar timers, and it is
    # what makes a laptop that was asleep at :15 run the reconcile on wake
    # instead of silently skipping to the next quarter hour.
    onCalendar = "*:0/15";
    persistent = true;
    # Docs edited during a meeting should not all land at the same instant.
    randomizedDelaySec = "2m";
    timerDescription = "Periodic Google Docs reconcile";

    # launchd has no OnCalendar-with-repeat; a plain 15-minute interval is the
    # same cadence. A missed interval fires when the Mac wakes, which is what
    # Persistent buys on Linux.
    everySeconds = 900;
    path = [gdoc-sync pkgs.coreutils];
    logFile = "%h/.local/state/gdoc-sync.log";

    # Standard, not the Background default (PRI 4, E-cores only): a `sync --all`
    # started 2026-10-19 19:34 used 2.5 min of CPU in 15 h, holding the state
    # lock the whole time, so meeting-note-docs' `link` calls timed out
    # (Oops 20261020-101750). Notes typed into a Doc during a meeting should
    # reach the vault within the 15-minute cadence.
    launchdExtra.ProcessType = "Standard";

    serviceExtra = {
      # `sync --all` exits 2 when a file is genuinely conflicted. That is not a
      # crash — it is a decision waiting for Matt — but leaving the unit in a
      # failed state is exactly how it stays visible in `systemctl --user
      # --failed` instead of scrolling past in the journal.
      #
      # The OAuth consent screen is still in Testing, so the refresh token dies
      # about weekly and every run fails until `gdoc-sync auth` is run by hand
      # (MAT-1200). Same reasoning: it should be loud.
      TimeoutStartSec = "10m";

      ProtectSystem = "yes";
      NoNewPrivileges = "yes";
    };
  };
}
