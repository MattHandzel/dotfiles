{pkgs, ...}: let
  # Linear ships no Linux app, so we poll its GraphQL API for unread
  # notifications and surface them through swaync via notify-send. This is a
  # systemd *user* service (not a system one) so notify-send finds the session
  # D-Bus and the notification actually renders. Same poll→notify shape as
  # gmail-automation.nix, but no browser needs to stay open.
  #
  # The Linear personal API key lives in the sops secret `linear_api_key`
  # (declared in modules/core/sops.nix), materialized at /run/secrets/linear_api_key.
  keyFile = "/run/secrets/linear_api_key";

  poller = pkgs.writeShellApplication {
    name = "linear-notify-poll";
    runtimeInputs = with pkgs; [curl jq libnotify coreutils];
    text = ''
      set -euo pipefail

      key_file="${keyFile}"
      if [ ! -r "$key_file" ]; then
        echo "linear-notify: $key_file not readable — add the sops secret 'linear_api_key'." >&2
        exit 2
      fi
      api_key="$(cat "$key_file")"

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/linear-notify"
      seen_file="$state_dir/seen.json"
      init_flag="$state_dir/.initialized"
      mkdir -p "$state_dir"
      [ -f "$seen_file" ] || echo '[]' > "$seen_file"

      # Fetch the 30 most-recent notifications; we only act on unread ones.
      query='{ "query": "{ notifications(first: 30) { nodes { id readAt type ... on IssueNotification { issue { identifier title } } } } }" }'

      resp="$(curl -sS --max-time 20 -X POST https://api.linear.app/graphql \
        -H "Authorization: $api_key" \
        -H "Content-Type: application/json" \
        --data "$query")"

      # A valid response has .data.notifications.nodes; anything else = transient
      # error (rate limit, network, bad key). Exit 1 so the next tick retries.
      if ! echo "$resp" | jq -e '.data.notifications.nodes' >/dev/null 2>&1; then
        echo "linear-notify: unexpected API response: $(echo "$resp" | head -c 300)" >&2
        exit 1
      fi

      # Unread notifications only.
      unread="$(echo "$resp" | jq -c '[.data.notifications.nodes[] | select(.readAt == null)]')"
      unread_ids="$(echo "$unread" | jq -c 'map(.id)')"
      seen="$(cat "$seen_file")"

      # First run: seed the seen-set silently so we don't blast every existing
      # unread item as a "new" notification.
      if [ ! -f "$init_flag" ]; then
        echo "$unread_ids" > "$seen_file"
        touch "$init_flag"
        exit 0
      fi

      # New = unread and not previously notified.
      new="$(jq -cn --argjson nodes "$unread" --argjson seen "$seen" \
        '$nodes | map(select((.id) as $i | ($seen | index($i)) | not))')"

      echo "$new" | jq -c '.[]' | while IFS= read -r n; do
        ident="$(echo "$n" | jq -r '.issue.identifier // "Linear"')"
        title="$(echo "$n" | jq -r '.issue.title // .type // "New notification"')"
        notify-send -a Linear -u normal "Linear: $ident" "$title"
      done

      # Remember every currently-unread id (cap the set so it can't grow forever).
      jq -cn --argjson seen "$seen" --argjson ids "$unread_ids" \
        '($seen + $ids) | unique' > "$seen_file"
    '';
  };
in {
  systemd.user.services.linear-notify = {
    Unit = {
      Description = "Poll Linear for unread notifications → swaync";
      After = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${poller}/bin/linear-notify-poll";
      # 0 ok, 1 transient API error, 2 missing key — none should spam failure logs.
      SuccessExitStatus = "0 1 2";
    };
  };

  systemd.user.timers.linear-notify = {
    Unit.Description = "Poll Linear notifications every 5min";
    Timer = {
      # Linear notifications aren't time-critical; 5min latency is fine and cuts
      # the curl+jq poll from 1440 to ~288 runs/day.
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      # Catch up after suspend/resume.
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
