# Grammar-check the current selection (or clipboard) anywhere on the desktop.
# Bound to SUPER+C in hyprland/config.nix.
#
# Engine: languagetool-commandline (packages.nix) — fully offline, spawned per
# invocation so no JVM sits resident (this machine swaps under RAM pressure; a
# parked LanguageTool server is exactly what lspconfig.lua evicted). Cold start
# is a few seconds — the "checking…" notification is there so it doesn't feel
# dead. Neovim prose uses harper-ls instead (fast, incremental); this script is
# the catch-all for Slack/Obsidian/browser text.

set -u

text="$(wl-paste -p 2>/dev/null || true)"
[ -z "$text" ] && text="$(wl-paste 2>/dev/null || true)"

if [ -z "${text// /}" ]; then
  notify-send -u normal -t 3000 "Grammar check" "Nothing selected or in clipboard."
  exit 0
fi

notify-send -u low -t 2000 "Grammar check" "Checking…"

tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/grammar-check.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s' "$text" >"$tmp"

# Cap the JVM well below default so a big selection can't balloon memory.
JAVA_TOOL_OPTIONS="-Xmx512m" languagetool-commandline --json -l en-US "$tmp" 2>/dev/null |
  python3 - <<'EOF'
import json, subprocess, sys

try:
    matches = json.load(sys.stdin).get("matches", [])
except (json.JSONDecodeError, ValueError):
    subprocess.run(["notify-send", "-u", "normal", "Grammar check", "LanguageTool failed — see journal."])
    sys.exit(1)

if not matches:
    subprocess.run(["notify-send", "-u", "normal", "-t", "4000", "Grammar check", "✓ No issues found."])
    sys.exit(0)

lines = []
for m in matches[:8]:
    ctx = m["context"]
    flagged = ctx["text"][ctx["offset"] : ctx["offset"] + ctx["length"]]
    fix = m["replacements"][0]["value"] if m["replacements"] else None
    msg = m.get("shortMessage") or m["message"]
    lines.append(f"• “{flagged}” — {msg}" + (f" → “{fix}”" if fix else ""))
if len(matches) > 8:
    lines.append(f"…and {len(matches) - 8} more")

subprocess.run(
    ["notify-send", "-u", "normal", "-t", "15000",
     f"Grammar check — {len(matches)} issue{'s' if len(matches) != 1 else ''}",
     "\n".join(lines)]
)
EOF
