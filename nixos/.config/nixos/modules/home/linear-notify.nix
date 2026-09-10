{
  config,
  host,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  # Linear ships no Linux app, so we poll its GraphQL API for unread
  # notifications and surface them through swaync via notify-send. This is a
  # systemd *user* service (not a system one) so notify-send finds the session
  # D-Bus and the notification actually renders. Same poll→notify shape as
  # gmail-automation.nix, but no browser needs to stay open.
  #
  # The Linear personal API key lives in the sops secret `linear_api_key`
  # (declared in modules/core/sops.nix on NixOS, modules/darwin/sops.nix on the
  # Mac). Read the path out of the OS config rather than hardcoding
  # /run/secrets: on darwin /run only exists as a firmlink after a reboot, and
  # sops-nix's darwin module puts secrets somewhere else entirely.
  keyFile = osConfig.sops.secrets.linear_api_key.path;

  # notify-send does not exist on macOS; the platform shim maps it onto
  # terminal-notifier there and onto libnotify on Linux.
  inherit (import ./lib/platform-scripts.nix {inherit pkgs;}) notify;

  poller = pkgs.writeShellApplication {
    name = "linear-notify-poll";
    runtimeInputs = [pkgs.curl pkgs.jq notify pkgs.coreutils];
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
        notify "Linear: $ident" "$title"
      done

      # Remember every currently-unread id (cap the set so it can't grow forever).
      jq -cn --argjson seen "$seen" --argjson ids "$unread_ids" \
        '($seen + $ids) | unique' > "$seen_file"
    '';
  };
  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = scheduled {
    name = "linear-notify";
    description = "Poll Linear for unread notifications → swaync";
    command = ["${poller}/bin/linear-notify-poll"];

    after = ["network-online.target"];

    # Linear notifications aren't time-critical; 5min latency is fine and cuts
    # the curl+jq poll from 1440 to ~288 runs/day.
    onBootSec = "1min";
    onUnitActiveSec = "5min";
    # Catch up after suspend/resume.
    persistent = true;
    timerDescription = "Poll Linear notifications every 5min";

    everySeconds = 300;
    path = [poller pkgs.coreutils];
    logFile = "%h/.local/state/linear-notify.log";

    # 0 ok, 1 transient API error, 2 missing key — none should spam failure logs.
    serviceExtra.SuccessExitStatus = "0 1 2";
  };
}
