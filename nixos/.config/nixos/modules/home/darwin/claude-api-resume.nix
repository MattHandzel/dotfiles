# Claude Code StopFailure hook for every session on this Mac (Oops
# 20261019-182804): wakes a session whose turn ended on an API error once the
# API is reachable again, after sleep or a lost network too. See
# claude-api-resume.sh.
#
# Registered by hand in ~/.claude/settings.json, like the other global hooks.
# That file is Syncthing-shared with the Linux hosts, which do not have this
# binary, hence the -x guard. The timeout is 7 days because Claude Code's hook
# timeout keeps counting while the Mac sleeps and the script's own waits do not:
# the Oops-only version (900 s) was killed silently by its timeout on the first
# wake after a 50 min sleep, before it could resume anything.
#   "StopFailure": [{"matcher": "server_error|overloaded|rate_limit|unknown|max_output_tokens",
#     "hooks": [{"type": "command", "asyncRewake": true, "timeout": 604800,
#       "command": "[ -x \"$HOME/.local/bin/claude-api-resume\" ] || exit 0; exec \"$HOME/.local/bin/claude-api-resume\"",
#       "rewakeMessage": "Auto-resume:", "rewakeSummary": "Resuming after an API error"}]}]
{pkgs, ...}: let
  apiResume = pkgs.writeShellApplication {
    name = "claude-api-resume";
    runtimeInputs = [pkgs.coreutils pkgs.curl pkgs.gawk pkgs.jq];
    text = builtins.readFile ./claude-api-resume.sh;
  };
in {
  home.file.".local/bin/claude-api-resume".source = "${apiResume}/bin/claude-api-resume";
}
