# launch-watcher.nix — poll launch threads for new comments, and watch the watcher.
#
# Countermeasure 3 of the open-source launch system. The timer fires every 5 minutes;
# scripts/launch/comment-watcher.py decides per run whether that run is actually due,
# from the cadence in its watch.json (5 min for 72h -> hourly to T+14d -> daily). So the
# timer stays dumb and the policy stays in the vault, editable without a rebuild.
#
# The heartbeat service is the countermeasure's countermeasure: a silent watcher and a
# dead watcher look identical from the phone, so a heartbeat older than 30 minutes pushes
# one ntfy (rate-limited to once per 6h so a weekend outage sends one alert, not 288).
#
# SECRET — Matt must do this before importing this module:
#   `sops secrets/secrets.yaml` and add `github-launch-metrics-token: ghp_...`
#   This is the same secret launch-metrics.nix uses. Both modules declare it with an
#   identical `owner = "matth"`, and types.str merges equal definitions, so importing
#   both is safe. Declaring a sops secret with no value in secrets.yaml makes ACTIVATION
#   fail, so do not import this module until the value exists.
{
  pkgs,
  config,
  ...
}: let
  vault = "/home/matth/Obsidian/Main";
  tokenPath = config.sops.secrets."github-launch-metrics-token".path;
  heartbeat = "${vault}/agent/state/launch-watcher.heartbeat";
  stampFile = "/home/matth/.local/state/launch-watcher/stale-alert.stamp";
  ntfyUrl = "http://localhost:8124/claude"; # ntfy-sh runs on this host

  runWatcher = pkgs.writeShellScript "launch-watcher-run" ''
    export PATH="${pkgs.gh}/bin:${pkgs.curl}/bin:${pkgs.coreutils}/bin:$PATH"
    export HOME=/home/matth
    export VAULT_ROOT="${vault}"
    export NTFY_URL="http://localhost:8124"
    GH_TOKEN="$(cat ${tokenPath})"
    export GH_TOKEN
    exec ${pkgs.python3}/bin/python3 ${vault}/scripts/launch/comment-watcher.py poll --all
  '';

  # Stale-heartbeat alarm. Silent when the heartbeat is fresh; silent when it already
  # fired inside the last 6h. Only ever sends about the watcher, never about comments.
  runHeartbeatCheck = pkgs.writeShellScript "launch-watcher-heartbeat" ''
    export PATH="${pkgs.curl}/bin:${pkgs.coreutils}/bin:$PATH"
    hb="${heartbeat}"
    stamp="${stampFile}"
    mkdir -p "$(dirname "$stamp")"
    now=$(date +%s)

    if [ -f "$hb" ]; then
      age=$(( now - $(stat -c %Y "$hb") ))
    else
      age=999999
    fi
    [ "$age" -lt 1800 ] && exit 0   # fresh (< 30 min): nothing to say

    if [ -f "$stamp" ]; then
      since=$(( now - $(stat -c %Y "$stamp") ))
      [ "$since" -lt 21600 ] && exit 0   # already alerted in the last 6h
    fi

    curl -sf -H "Title: launch-watcher stale" -H "Priority: high" -H "Tags: warning" \
      -d "No launch-watcher heartbeat for $(( age / 60 )) min. Check: systemctl status launch-watcher.timer" \
      "${ntfyUrl}" >/dev/null || true
    touch "$stamp"
  '';
in {
  sops.secrets."github-launch-metrics-token" = {
    owner = "matth";
  };

  systemd.services.launch-watcher = {
    description = "Poll launch threads (GitHub/Reddit/HN) for new comments";
    after = ["network-online.target" "ntfy-sh.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${runWatcher}";
      # A single failing source must not mark the unit failed; the heartbeat is the
      # real liveness signal and it is written even when nothing is new.
      SuccessExitStatus = "0 1";
    };
  };

  systemd.timers.launch-watcher = {
    description = "Run the launch comment watcher every 5 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
      Unit = "launch-watcher.service";
    };
  };

  systemd.services.launch-watcher-heartbeat = {
    description = "Alert if the launch comment watcher has stopped writing its heartbeat";
    after = ["ntfy-sh.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${runHeartbeatCheck}";
    };
  };

  systemd.timers.launch-watcher-heartbeat = {
    description = "Check the launch-watcher heartbeat every 15 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
      Unit = "launch-watcher-heartbeat.service";
    };
  };
}
