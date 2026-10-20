# claude-api-resume — Claude Code StopFailure hook for every session on this
# Mac (registered in ~/.claude/settings.json, see claude-api-resume.nix). It
# wakes a session whose turn ended on a transient API error, so the work carries
# on by itself.
#
# WHY (Oops 20261019-145311, Matt: "oops should be resistant to api errors, i.e.
# automatically continue / restart"): the 10/14 13:22 Oops session (timer pill)
# was mid-verification when its turn ended with "API Error: Your computer went
# to sleep mid-response" at 13:57. Nothing resumed it; Matt found it idle five
# days later. Claude Code retries a failed request itself, but once a turn has
# ended on the error the session just waits at its prompt.
# Oops 20261019-182804 (Matt: "i want claude continue when my laptop wakes up
# or when the api is back online or internet is back online"): made global
# (it was Oops-only), and it no longer wakes a session while the API cannot be
# reached. Offline at the airport (ENOTFOUND, recorded as server_error) the
# Oops-only version spent all 6 wakes in 55 min, each one ~3 min of Claude's
# own retries into the same error, and gave up while still offline.
#
# How: registered with asyncRewake, so Claude Code runs this in the background
# and, on exit 2, queues stderr as the session's next message (a new turn in
# the SAME session, nothing typed into a terminal). The matcher in
# settings.json limits it to errors a retry can cure (server_error, overloaded,
# rate_limit, unknown, max_output_tokens); login, billing and invalid-request
# errors still wait for Matt. Headless `claude -p` / SDK runs are left alone:
# whatever started them re-runs them.
#
# 1. Backoff 30 s, 1, 2, 4 … 30 min: at most CLAUDE_RESUME_MAX (12) wakes per
#    session in 6 h, then one notification and the session waits for Matt.
# 2. Then, while the API host gives no HTTP answer at all (offline, DNS,
#    captive portal), poll every 20 s. Offline time costs no wake, and the poll
#    carries on across sleep, so the session continues soon after the lid opens
#    and the network is back.
# It stands down when anything moved the session on during the wait (Matt typed,
# or the turn was retried by hand). Log: ~/.local/state/claude-api-resume/resume.log
input="$(cat)"
case "${CLAUDE_CODE_ENTRYPOINT:-}" in sdk-*) exit 0 ;; esac
# A launcher with its own retry sets CLAUDE_API_RESUME=off in its --settings env:
# meeting-listener resumes a failed session as a NEW session id, so waking the
# old one here too would process the meeting twice.
[ "${CLAUDE_API_RESUME:-}" != off ] || exit 0
sid="$(jq -r '.session_id // empty' <<<"$input")"
err="$(jq -r '.error // "unknown"' <<<"$input")"
details="$(jq -r '.error_details // empty' <<<"$input" | tr '\n' ' ' | head -c 300 || true)"
transcript="$(jq -r '.transcript_path // empty' <<<"$input")"
[ -n "$sid" ] || exit 0

state="$HOME/.local/state/claude-api-resume"
mkdir -p "$state"
touch "$state/$sid"
log="$state/resume.log"
max="${CLAUDE_RESUME_MAX:-12}"
now="$(date +%s)"
recent="$(awk -v since="$((now - 21600))" '$1 > since' "$state/$sid" | wc -l | tr -d ' ')"
if [ "$recent" -ge "$max" ]; then
  echo "$(date '+%F %T') $sid $err: $recent wakes in the last 6 h, giving up" >>"$log"
  /usr/bin/osascript -e "display notification \"API error ($err) came back after $recent automatic resumes; it waits for you.\" with title \"Claude session stopped\"" >/dev/null 2>&1 || true
  exit 0
fi
delay=$((${CLAUDE_RESUME_BASE:-30} << recent))
[ "$delay" -le 1800 ] || delay=1800
echo "$now" >>"$state/$sid"
size=0
[ -f "$transcript" ] && size="$(wc -c <"$transcript" | tr -d ' ')"
echo "$(date '+%F %T') $sid $err: waiting ${delay}s before wake $((recent + 1))/$max${details:+ ($details)}" >>"$log"

# A user entry (Matt typed, a tool result) or a real assistant reply after the
# error means the session is no longer stuck.
moved_on() {
  [ -f "$transcript" ] &&
    tail -c +"$((size + 1))" "$transcript" |
    jq -R -e -n '[inputs | fromjson? | select(.type == "user" or (.type == "assistant" and (.isApiErrorMessage | not)))] | length > 0' >/dev/null
}
# Any HTTP status from the API host means requests get through again; curl
# honours HTTPS_PROXY like Claude Code does.
api="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
reachable() { [ "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$api" || true)" != 000 ]; }

sleep "$delay"
offline=0
until reachable; do
  if moved_on; then
    echo "$(date '+%F %T') $sid: session moved on while offline, not waking" >>"$log"
    exit 0
  fi
  [ "$offline" -gt 0 ] || echo "$(date '+%F %T') $sid: $api unreachable, waiting for the network" >>"$log"
  offline=$((offline + 1))
  sleep 20
done
[ "$offline" -eq 0 ] || echo "$(date '+%F %T') $sid: $api reachable again after $offline checks" >>"$log"

if moved_on; then
  echo "$(date '+%F %T') $sid: session moved on during the wait, not waking" >>"$log"
  exit 0
fi
echo "$(date '+%F %T') $sid: woke" >>"$log"
cat >&2 <<EOF
your previous turn was cut off by an API error ($err${details:+: $details}) and nothing has happened since; this is automatic wake $((recent + 1)) of $max. Carry on${OOPS_DIR:+ with the Oops procedure} from where you stopped: first re-check the last step whose result you did not see (a command may have finished, or never run), then continue.
EOF
exit 2
