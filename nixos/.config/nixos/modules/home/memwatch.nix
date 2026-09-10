{
  config,
  lib,
  pkgs,
  ...
}: let
  memwatchSnapshot = pkgs.writeShellApplication {
    name = "memwatch-snapshot";
    runtimeInputs = with pkgs; [
      coreutils
      procps
      util-linux
      gawk
      gnugrep
      systemd
    ];
    # Drop errexit/pipefail — partial errors (process disappearing mid-scan,
    # zramctl absent on some hosts) shouldn't abort the whole snapshot.
    bashOptions = ["nounset"];
    text = ''
      LOG_DIR="$HOME/.local/state/memwatch"
      mkdir -p "$LOG_DIR"
      LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"
      TS="$(date -Iseconds)"

      {
        echo "===== SNAPSHOT $TS ====="
        echo "## uptime"
        uptime
        echo
        echo "## free -h"
        free -h
        echo
        echo "## meminfo"
        grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty|Writeback|AnonPages|Mapped|Shmem|Slab|SReclaimable|SUnreclaim|KernelStack|PageTables|Committed_AS)' /proc/meminfo
        echo
        echo "## /proc/swaps"
        cat /proc/swaps
        echo
        echo "## zramctl"
        zramctl 2>/dev/null || true
        echo
        echo "## vmstat sample (5x1s)"
        vmstat 1 5
        echo
        echo "## process state histogram"
        ps -eo state --no-headers | sort | uniq -c
        echo "total=$(ps -e --no-headers | wc -l)"
        echo
        echo "## top 25 by RSS"
        ps -eo pid,user,etime,rss,vsz,comm --sort=-rss | head -26
        echo
        echo "## top 20 by RSS+swap (per-process anon footprint)"
        for p in $(ps -eo pid --no-headers); do
          status="/proc/$p/status"
          [ -r "$status" ] || continue
          rss=$(awk '/^VmRSS:/{print $2}' "$status" 2>/dev/null)
          swp=$(awk '/^VmSwap:/{print $2}' "$status" 2>/dev/null)
          name=$(awk '/^Name:/{print $2}' "$status" 2>/dev/null)
          if [ -n "$rss" ] && [ -n "$swp" ]; then
            echo "$((rss + swp)) $rss $swp $p $name"
          fi
        done | sort -rn | head -20 \
          | awk 'BEGIN{printf "%-12s %-10s %-10s %-7s %s\n","TOTAL_kB","RSS_kB","SWAP_kB","PID","NAME"} {printf "%-12s %-10s %-10s %-7s %s\n",$1,$2,$3,$4,$5}'
        echo
        echo "## per-app rollup (sum across all matching PIDs)"
        for pat in firefox zen chromium chrome brave thunderbird beepertexts discord slack electron 'code|Code' cursor java claude kitty obsidian zotero spotify; do
          rss_sum=0
          swp_sum=0
          n=0
          for p in $(pgrep -f "$pat" 2>/dev/null || true); do
            status="/proc/$p/status"
            [ -r "$status" ] || continue
            r=$(awk '/^VmRSS:/{print $2}' "$status" 2>/dev/null)
            s=$(awk '/^VmSwap:/{print $2}' "$status" 2>/dev/null)
            [ -n "$r" ] && rss_sum=$((rss_sum + r))
            [ -n "$s" ] && swp_sum=$((swp_sum + s))
            n=$((n + 1))
          done
          if [ "$rss_sum" -gt 0 ] || [ "$swp_sum" -gt 0 ]; then
            printf "%-18s procs=%-4d rss=%-10d swap=%-10d total=%d\n" "$pat" "$n" "$rss_sum" "$swp_sum" "$((rss_sum + swp_sum))"
          fi
        done
        echo
        echo "## systemd-cgtop top 20 by memory"
        systemd-cgtop --order=memory -n 1 -b 2>/dev/null | head -20 || true
        echo
        echo "## tmpfs df"
        df -h -t tmpfs 2>/dev/null || true
        echo
        echo "===== END $TS ====="
        echo
      } >> "$LOG_FILE" 2>&1
    '';
  };
in {
  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/memwatch 0700 - - - -"
  ];

  systemd.user.services.memwatch = {
    Unit = {
      Description = "Memory snapshot for diagnosing slow-over-time memory pressure";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${memwatchSnapshot}/bin/memwatch-snapshot";
    };
  };

  systemd.user.timers.memwatch = {
    Unit = {
      Description = "Run memwatch snapshot every 15 minutes";
    };
    Timer = {
      # Was every 5 min while diagnosing the swap/OOM issue. That diagnosis is
      # done; 15 min still tracks slow memory creep without each run's
      # `vmstat 1 5` (5s) + full /proc walk adding to idle load 12x/hour.
      OnCalendar = "*:0/15";
      # Don't catch up on missed runs after laptop sleep — they'd all fire at once.
      Persistent = false;
      Unit = "memwatch.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
