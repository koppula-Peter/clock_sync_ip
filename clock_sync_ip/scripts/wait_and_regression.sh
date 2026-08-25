#!/usr/bin/env bash
# wait_and_regression.sh — defer M1 regression until host load allows
# Detached helper: polls 1-min load average; starts run_xsim_regression.sh
# once below LOAD_MAX. Log: /tmp/opencode/m1_regression.log
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOAD_MAX="${LOAD_MAX:-10}"
LOG="${LOG:-/tmp/opencode/m1_regression.log}"

while :; do
  load="$(cut -d' ' -f1 /proc/loadavg)"
  awk -v l="$load" -v m="$LOAD_MAX" 'BEGIN{exit !(l<m)}' && break
  echo "$(date +%H:%M:%S) load=$load > $LOAD_MAX — waiting" >> "$LOG.wait"
  sleep 120
done

echo "$(date +%H:%M:%S) load=$load — starting regression" >> "$LOG"
exec env XELAB_FLAGS="${XELAB_FLAGS:--O0 -debug typical}" \
  "$ROOT/scripts/run_xsim_regression.sh"
