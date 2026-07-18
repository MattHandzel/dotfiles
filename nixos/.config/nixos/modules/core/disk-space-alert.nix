{pkgs, ...}: let
  curl = pkgs.curl;
  coreutils = pkgs.coreutils;

  alertScript = pkgs.writeShellScript "disk-space-alert" ''
    #!${pkgs.bash}/bin/bash
    # disk-space-alert — check /home and / free space, send ntfy on threshold crossing.
    # Runs every 15 min via systemd timer. Uses a state file to debounce repeated alerts.

    set -euo pipefail

    NTFY_URL="http://server.matthandzel.com:8124/claude"
    STATE_DIR="/var/lib/disk-space-alert"
    STATE_FILE="$STATE_DIR/last-alert-level"

    # Absolute path avoids shell alias (df is aliased to duf in user shell)
    DF="${coreutils}/bin/df"

    # Thresholds in GiB (integer arithmetic, avail from df --block-size=G)
    WARN_HOME_GIB=20
    URGENT_HOME_GIB=5
    WARN_ROOT_GIB=5
    URGENT_ROOT_GIB=2

    mkdir -p "$STATE_DIR"

    # Read previous alert level (none / warn / urgent)
    prev_level="none"
    if [ -f "$STATE_FILE" ]; then
      prev_level=$(cat "$STATE_FILE")
    fi

    # Get available space in GiB (integer, rounds down)
    home_avail_gib=$("$DF" --block-size=1G /home --output=avail | tail -1 | tr -d ' ')
    root_avail_gib=$("$DF" --block-size=1G /     --output=avail | tail -1 | tr -d ' ')

    # Determine current alert level
    current_level="none"
    if [ "$home_avail_gib" -le "$URGENT_HOME_GIB" ] || [ "$root_avail_gib" -le "$URGENT_ROOT_GIB" ]; then
      current_level="urgent"
    elif [ "$home_avail_gib" -le "$WARN_HOME_GIB" ] || [ "$root_avail_gib" -le "$WARN_ROOT_GIB" ]; then
      current_level="warn"
    fi

    # Send notification only on level change
    if [ "$current_level" = "$prev_level" ]; then
      echo "Disk level unchanged ($current_level). No notification."
      exit 0
    fi

    # Update state file
    echo "$current_level" > "$STATE_FILE"

    if [ "$current_level" = "none" ]; then
      # Recovered — send an all-clear (low priority)
      ${curl}/bin/curl -s \
        -H "Title: Disk Space OK" \
        -H "Priority: low" \
        -H "Tags: white_check_mark" \
        -d "$(hostname): disk space recovered. /home ${"\${home_avail_gib}"}G free, / ${"\${root_avail_gib}"}G free." \
        "$NTFY_URL" > /dev/null
      exit 0
    fi

    if [ "$current_level" = "urgent" ]; then
      priority="urgent"
      title="URGENT: Disk space critically low"
      tags="rotating_light"
    else
      priority="high"
      title="Disk space warning"
      tags="warning"
    fi

    msg="$(hostname): /home ${"\${home_avail_gib}"}G free, / ${"\${root_avail_gib}"}G free."

    ${curl}/bin/curl -s \
      -H "Title: $title" \
      -H "Priority: $priority" \
      -H "Tags: $tags" \
      -d "$msg" \
      "$NTFY_URL" > /dev/null

    echo "Sent $current_level notification: $msg"
  '';
in {
  # Create the state directory with correct ownership before the service runs
  systemd.tmpfiles.rules = [
    "d /var/lib/disk-space-alert 0755 root root -"
  ];

  systemd.services.disk-space-alert = {
    description = "Check disk space and send ntfy alert on threshold crossing";
    after = ["network.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${alertScript}";
      # Harden: only needs network + disk read + state dir write
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectHome = "read-only";
      ReadWritePaths = ["/var/lib/disk-space-alert"];
    };
  };

  systemd.timers.disk-space-alert = {
    description = "Run disk space check every 15 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";   # first run 5 min after boot (let network settle)
      OnUnitActiveSec = "15min";
      Persistent = false;   # intentionally NOT persistent: missed runs during
                            # sleep are fine — we don't want a burst on wake
    };
  };
}
