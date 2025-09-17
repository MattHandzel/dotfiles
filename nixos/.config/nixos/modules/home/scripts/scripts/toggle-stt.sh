set -euo pipefail

export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID/bus"
export XDG_RUNTIME_DIR="/run/user/$UID"
export PATH="/run/current-system/sw/bin:${HOME}/.nix-profile/bin:${PATH}"

PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/stt-rec.pid"
SCRIPT="/home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/stt_record.py"
SERVER="http://76.191.29.237:47770"   # adjust if needed

if [[ -f "$PIDFILE" ]]; then
  PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "${PID}" ]] && kill -0 "${PID}" 2>/dev/null; then
    # Toggle off: ask recorder to stop (SIGINT)
    kill -INT "${PID}"
    exit 0
  fi
fi

# Toggle on: start recorder (runs until SIGINT)
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null || echo)" 2>/dev/null; then
  kill -INT "$(cat "$PIDFILE")"
  exit 0
fi
nohup "$SCRIPT" --server "$SERVER" --pidfile "$PIDFILE" --mode clipboard >/tmp/stt-type.out 2>/tmp/stt-type.err &
disown
