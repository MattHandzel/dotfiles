#!/usr/bin/env bash
# Print a regex alternation of "distracting" app match-terms for Focus Mode, from the
# SINGLE source of truth: ~/notes/resources/focus-mode-apps.md. Everything that gates
# apps reads it through this script: the Mac Hammerspoon gate (focus_gate.lua), the
# SketchyBar workspace strip, and the Linux focus-mode-enforcer + focus_app.
#
# Deliberately NOT derived from dns-blocklist.md any more (2026-09-14). The two lists mean
# different things: DNS blocks a site outright, this only DELAYS an app by 15 s. Deep work
# can require answering email or Beeper, so those apps must be delayable without being
# DNS-blocked. (The old derivation turned every Deep-Work domain into an app term.)
#
# An entry is a single token (no spaces) of [a-z0-9_-], 3+ chars, on its own line
# (bullets and md decoration are stripped). Lines with spaces are prose and ignored.
# Prints nothing if the file is missing — callers MUST treat empty as "match nothing"
# (never feed an empty regex to grep).
set -u
MD="${FOCUS_APPS_MD:-$HOME/notes/resources/focus-mode-apps.md}"
[ -r "$MD" ] || exit 0

awk '
  /^---[[:space:]]*$/ { fm = !fm; next }                 # skip YAML frontmatter
  fm || /^[[:space:]]*#/ { next }                        # and headings
  {
    line = $0
    sub(/^[[:space:]]*[-*+][[:space:]]+/, "", line)     # bullet
    sub(/^[[:space:]]*[0-9]+[.)][[:space:]]+/, "", line) # ordered marker
    gsub(/[`*_~<>]/, "", line)                           # md decoration
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    tok = tolower(line)
    if (tok ~ /^[a-z0-9_-]+$/ && length(tok) >= 3) print tok
  }
' "$MD" | awk 'NF && !seen[$0]++' | paste -sd '|' -
