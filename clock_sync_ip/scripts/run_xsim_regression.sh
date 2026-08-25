#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_xsim_regression.sh — M1 unit regression under Vivado xsim
# Usage: scripts/run_xsim_regression.sh [tb_name ...]   (default: all M1 TBs)
# Results: build/sim/xsim/<tb>/{xvlog,xelab,xsim_s<seed>}.log + summary
# ---------------------------------------------------------------------------
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTBASE="$ROOT/build/sim/xsim"
SEEDS_DEFAULT="1 2 3"

source "$ROOT/../xilinx_env.sh" 2>/dev/null || true
command -v xvlog >/dev/null 2>&1 || { echo "ERROR: xvlog not in PATH"; exit 2; }

PKG="$ROOT/rtl/common/clk_sync_cdc_pkg.sv"
RTL="$ROOT/rtl/cdc/reset/rst_sync.sv $ROOT/rtl/cdc/level/cdc_level_sync.sv $ROOT/rtl/cdc/pulse/cdc_pulse_sync.sv $ROOT/rtl/cdc/handshake/cdc_handshake.sv $ROOT/rtl/cdc/gray/cdc_gray_sync.sv"

declare -A TB_TOP=(
  [tb_rst_sync]="$ROOT/tb/cdc/tb_rst_sync.sv"
  [tb_cdc_level_sync]="$ROOT/tb/cdc/tb_cdc_level_sync.sv"
  [tb_cdc_pulse_sync]="$ROOT/tb/cdc/tb_cdc_pulse_sync.sv"
  [tb_cdc_handshake]="$ROOT/tb/cdc/tb_cdc_handshake.sv"
  [tb_cdc_gray_sync]="$ROOT/tb/cdc/tb_cdc_gray_sync.sv"
)

TBS=("$@")
if [ ${#TBS[@]} -eq 0 ]; then
  TBS=(tb_rst_sync tb_cdc_level_sync tb_cdc_pulse_sync tb_cdc_handshake tb_cdc_gray_sync)
fi

mkdir -p "$OUTBASE"
PASS_ALL=1

for tb in "${TBS[@]}"; do
  dir="$OUTBASE/$tb"
  mkdir -p "$dir"
  echo "=== $tb ==="
  pushd "$dir" > /dev/null

  if ! xvlog -sv -i "$ROOT/rtl/common" "$ROOT/tb/cdc/tb_util_pkg.sv" "$PKG" $RTL "${TB_TOP[$tb]}" > xvlog.log 2>&1; then
    echo "  XVLOG FAILED (xvlog.log)"; grep -m5 "ERROR" xvlog.log; PASS_ALL=0; popd > /dev/null; continue
  fi
  if ! xelab -debug typical -s snap "$tb" > xelab.log 2>&1; then
    echo "  XELAB FAILED (xelab.log)"; grep -m5 -i "error" xelab.log; PASS_ALL=0; popd > /dev/null; continue
  fi

  for seed in $SEEDS_DEFAULT; do
    xsim snap -R --sv_seed "$seed" > "xsim_s$seed.log" 2>&1
    if grep -q '\*\*\* TEST PASSED \*\*\*' "xsim_s$seed.log"; then
      echo "  seed $seed : PASS ($(grep -o 'tests=[0-9]* errors=[0-9]*' "xsim_s$seed.log" | tail -1))"
    else
      echo "  seed $seed : FAIL  ($dir/xsim_s$seed.log)"
      grep -E "FAIL|Fatal|ERROR" "xsim_s$seed.log" | head -8
      PASS_ALL=0
    fi
  done
  popd > /dev/null
done

echo "==================================================="
if [ $PASS_ALL -eq 1 ]; then echo "REGRESSION RESULT: ALL PASSED"; else echo "REGRESSION RESULT: FAILURES PRESENT"; fi
exit $PASS_ALL
