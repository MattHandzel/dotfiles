#!/usr/bin/env bash

# Launcher for the Claude Desktop app (Chat/Cowork/Code). The file is named
# after the app's window class (com.anthropic.Claude) so focus_app's launch
# fallback resolves it — same pattern as claude.ai.sh / gemini.google.com.sh.
if [[ "$(uname)" == Darwin ]]; then
  exec open -a Claude "$@"
fi
exec claude-desktop "$@"
