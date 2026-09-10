#!/usr/bin/env bash
# Print a regex alternation of "distracting" app match-terms, derived from the
# SINGLE source of truth: ~/notes/resources/dns-blocklist.md (the same file the
# DNS resolver reads). Both the focus-mode enforcer (window-switch path) and
# focus_app (keybind path) call this, so there is exactly one list to edit.
#
# What becomes an app match-term:
#   - domains under the "Deep Work only (focus mode)" heading → their second-level
#     label (discord.com → discord, spotify.com → spotify). Sites that have a
#     desktop app thus get app-delayed automatically; ones that don't (youtube,
#     reddit, …) simply never match a window class — harmless.
#   - bare names under an "## Apps" heading (beeper, betterbird, thunderbird) —
#     for apps with no domain in the list. The DNS resolver ignores these lines
#     (they aren't domains), so this never affects blocking.
#
# Terms shorter than 3 chars are dropped (e.g. "x" from x.com) so they can't match
# arbitrary window classes. Prints nothing if the file is missing — callers MUST
# treat empty as "match nothing" (never feed an empty regex to grep).
set -u
MD="${FOCUS_BLOCKLIST_MD:-$HOME/notes/resources/dns-blocklist.md}"
[ -r "$MD" ] || exit 0

# dns-blocklist.md is the bulk DNS source — tens of MB / >1M domain lines — so the
# awk below costs ~2.5s. focus_app calls this on EVERY launch in focus mode (before
# it knows whether the app is distracting), so that cost lands on opening any app.
# The derived app-term regex only changes when the markdown does, so cache it and
# recompute only when the source is newer than the cache. Warm calls are ~instant.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE="$CACHE_DIR/focus-distracting-apps.regex"
if [ -f "$CACHE" ] && [ "$CACHE" -nt "$MD" ]; then
  cat "$CACHE"
  exit 0
fi

result="$(awk '
  /^[[:space:]]*#/ {
    low = tolower($0)
    if (low ~ /deep work/ || low ~ /focus mode/) section = "focus"
    else if (low ~ /apps/)                       section = "apps"
    else                                         section = "other"
    next
  }
  {
    line = $0
    sub(/^[[:space:]]*[-*+][[:space:]]+/, "", line)     # bullet
    sub(/^[[:space:]]*[0-9]+[.)][[:space:]]+/, "", line) # ordered marker
    gsub(/[`*_~<>]/, "", line)                           # md decoration
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line == "") next
    # An ENTRY is a line that is a SINGLE token (no spaces) — this skips all
    # prose under a heading. A line with any whitespace is treated as prose.
    if (line ~ /[[:space:]]/) next
    tok = tolower(line)
    sub(/^https?:\/\//, "", tok); sub(/^\*\./, "", tok); sub(/^www\./, "", tok)
    if (tok ~ /^[a-z0-9.-]+\.[a-z]{2,}$/) {              # a domain entry
      if (section == "focus" || section == "apps") {
        m = split(tok, a, "."); if (length(a[m - 1]) >= 3) print a[m - 1]
      }
    } else if (section == "apps" && tok ~ /^[a-z0-9_-]+$/ && length(tok) >= 3) {
      print tok                                          # bare app name
    }
  }
' "$MD" | awk 'NF && !seen[$0]++' | paste -sd '|' -)"

# Cache atomically (mktemp + mv on the same fs) so concurrent callers can't read a
# half-written regex. An empty result is cached too: it means "match nothing".
mkdir -p "$CACHE_DIR"
tmp="$(mktemp "$CACHE.XXXXXX")"
printf '%s\n' "$result" >"$tmp" && mv -f "$tmp" "$CACHE"
printf '%s\n' "$result"
