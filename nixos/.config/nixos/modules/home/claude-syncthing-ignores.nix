# Syncthing ignore list for the `claude` folder (~/.claude), shared between
# laptop, matts-computer and matts-server.
#
# This file used to be hand-maintained in place (~/.claude/.stignore, last
# edited 2026-06-01) and so drifted out of the flake entirely. It is declared
# here because one line in it decides whether Claude Code stays logged in.
#
# .stignore is per-device and is itself never synced, so every host that shares
# the `claude` folder must rebuild for the exclusion below to take effect on it.
{...}: {
  home.file.".claude/.stignore".text = ''
    // Syncthing ignores for ~/.claude — sync config + memory + CONVERSATION HISTORY
    // (session transcripts under projects/) so `claude --resume` works on either
    // machine. Only machine-local / huge / volatile stuff is excluded.
    // Syncthing: top-to-bottom, first match wins; "!" = do NOT ignore.

    // OAuth credentials are machine-local and MUST NOT be synced.
    //
    // Claude Code rotates its refresh token on every use: refreshing on one
    // machine invalidates the token every other machine holds. Syncing this
    // file therefore hands each host a token that the next refresh elsewhere
    // has already revoked, and the revoked host is forced to log in again —
    // which is exactly the "your login has expired" prompt that was firing
    // several times a day. The fingerprint was six
    // .credentials.sync-conflict-* files between 2026-06-06 and 2026-07-11.
    //
    // The cost of NOT sharing this is one login per machine per refresh-token
    // lifetime (~30 days). That is strictly cheaper than the daily re-login,
    // so do not restore the previous "!/.credentials.json" line.
    /.credentials.json
    /.credentials.sync-conflict-*
    /.syncthing..credentials.json.tmp

    // machine-local / regenerable / volatile — NOT synced
    /cache
    /shell-snapshots
    /file-history
    /paste-cache
    /session-env
    /daemon
    /daemon.log
    /debug
    /telemetry
    /backups
    /plugins
    /jobs
    // root prompt-history + usage logs: append-on-every-session => conflict-prone,
    // and NOT needed for --resume (that reads projects/<hash>/*.jsonl). Keep local.
    /history.jsonl
    /usage-log.jsonl
    (?d)*.lock
    /.last-cleanup
    /.last-update-result.json
    /stats-cache.json
    /mcp-needs-auth-cache.json

    // Everything else syncs: settings.json, CLAUDE.md, agents/, commands/, hooks/,
    // skills/, todos/, tasks/, teams/, sessions/, and projects/ (the transcripts
    // that --resume lists).
  '';
}
