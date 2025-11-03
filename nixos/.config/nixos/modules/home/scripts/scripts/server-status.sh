#!/usr/bin/env bash
set -euo pipefail

# Allow overriding the IP via CLI while defaulting to the env var.
SERVER_IP="${SERVER_IP_ADDRESS:-${1:-}}"

if [[ -z "${SERVER_IP}" ]]; then
  printf '{"text":"󰣕","alt":"unknown","tooltip":"SERVER_IP_ADDRESS not set","class":["server-status","unknown"]}\n'
  exit 0
fi

if timeout 5 ping -c 1 "${SERVER_IP}" >/dev/null 2>&1; then
  icon="󰣖"
  alt="online"
  class="online"
  tooltip="Server ${SERVER_IP} is reachable"
else
  icon="󰣘"
  alt="offline"
  class="offline"
  tooltip="Server ${SERVER_IP} is unreachable"
fi

printf '{"text":"%s","alt":"%s","tooltip":"%s","class":["server-status","%s"]}\n' \
  "${icon}" \
  "${alt}" \
  "${tooltip}" \
  "${class}"
