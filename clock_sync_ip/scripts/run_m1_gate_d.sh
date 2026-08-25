#!/usr/bin/env bash
# run_m1_gate_d.sh — sequential Gate-D evidence collection
# 1. waits for any active xsim regression to finish
# 2. runs the full M1 unit regression if no results yet / forced
# 3. runs OOC synth + report_cdc bundle for all five M1 modules
# Logs: /tmp/opencode/m1_gate_d.log
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${LOG:-/tmp/opencode/m1_gate_d.log}"

log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

# --- 1: wait for an in-flight regression (xvlog/xelab/xsim) -----------------
while pgrep -f "run_xsim_regression" >/dev/null 2>&1 || \
      pgrep -x xvlog >/dev/null 2>&1 || pgrep -x xelab >/dev/null 2>&1 || \
      pgrep -x xsim >/dev/null 2>&1; do
  sleep 60
done
log "no active sim processes — proceeding"

# --- 2: ensure regression results exist -------------------------------------
NEED=0
for tb in tb_rst_sync tb_cdc_level_sync tb_cdc_pulse_sync tb_cdc_handshake \
          tb_cdc_gray_sync tb_clk_divider tb_gf_mux; do
  if ! { [ -f "$ROOT/build/sim/xsim/$tb/xsim_s3.log" ] && \
         grep -q "TEST PASSED\\|TEST FAILED" "$ROOT/build/sim/xsim/$tb/xsim_s3.log"; }; then
    NEED=1
  fi
done
if [ "$NEED" = "1" ]; then
  log "running missing regression pieces"
  env XELAB_FLAGS="${XELAB_FLAGS:--O0 -debug off}" bash "$ROOT/scripts/run_xsim_regression.sh"
  log "regression pass done rc=$?"
else
  log "regression logs already present — skipping sim"
fi

# --- 3: OOC synthesis + CDC bundles ------------------------------------------
if command -v vivado >/dev/null 2>&1 || [ -f "$HOME/Desktop/xilinx_tools/2025.2/Vivado/settings64.sh" ]; then
  log "starting OOC synth bundle"
  bash "$ROOT/scripts/vivado_ooc_synth.sh" m1
  log "ooc synth rc=$?"
else
  log "vivado unavailable — skipping synth stage"
fi
log "gate-d sequence complete"
