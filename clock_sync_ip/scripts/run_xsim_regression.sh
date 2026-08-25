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

# --- tool environment -------------------------------------------------------
# Prefer an already-configured PATH. Otherwise locate Vivado settings64.sh via
# $XILINX_TOOLS or common install locations. xsim additionally needs the
# libncurses.so.5 soname; if only ncurses6 exists, a compat-shim directory
# (kept OUTSIDE this repository, e.g. <tools_root>/ncurses5/) must provide it.
NCURSES_SHIM_DIRS=""
if ! command -v xvlog >/dev/null 2>&1; then
  CANDS="${XILINX_TOOLS:-}/Vivado/settings64.sh"
  for v in 2025.2 2025.1 2024.2; do
    CANDS="$CANDS $HOME/Desktop/xilinx_tools/$v/Vivado/settings64.sh /tools/Xilinx/$v/Vivado/settings64.sh /opt/Xilinx/$v/Vivado/settings64.sh"
  done
  for s in $CANDS; do
    [ -f "$s" ] || continue
    # shellcheck disable=SC1090
    source "$s"
    TOOLS_ROOT="$(dirname "$(dirname "$(dirname "$s")")")"   # .../xilinx_tools
    [ -d "$TOOLS_ROOT/ncurses5" ] && NCURSES_SHIM_DIRS="$TOOLS_ROOT/ncurses5"
    break
  done
fi
if [ -n "$NCURSES_SHIM_DIRS" ]; then
  case ":${LD_LIBRARY_PATH:-}:" in
    *":$NCURSES_SHIM_DIRS:"*) ;;
    *) export LD_LIBRARY_PATH="$NCURSES_SHIM_DIRS:${LD_LIBRARY_PATH:-}" ;;
  esac
fi
command -v xvlog >/dev/null 2>&1 || { echo "ERROR: xvlog not in PATH"; exit 2; }
command -v xsim  >/dev/null 2>&1 || { echo "ERROR: xsim not in PATH (libncurses.so.5 shim missing? see header comment)"; exit 2; }

PKG="$ROOT/rtl/common/clk_sync_cdc_pkg.sv"
RTL="$ROOT/rtl/cdc/reset/rst_sync.sv $ROOT/rtl/cdc/level/cdc_level_sync.sv $ROOT/rtl/cdc/pulse/cdc_pulse_sync.sv $ROOT/rtl/cdc/handshake/cdc_handshake.sv $ROOT/rtl/cdc/gray/cdc_gray_sync.sv"

declare -A TB_TOP=(
  [tb_rst_sync]="$ROOT/tb/cdc/tb_rst_sync.sv"
  [tb_cdc_level_sync]="$ROOT/tb/cdc/tb_cdc_level_sync.sv"
  [tb_cdc_pulse_sync]="$ROOT/tb/cdc/tb_cdc_pulse_sync.sv"
  [tb_cdc_handshake]="$ROOT/tb/cdc/tb_cdc_handshake.sv"
  [tb_cdc_gray_sync]="$ROOT/tb/cdc/tb_cdc_gray_sync.sv"
  [tb_clk_divider]="$ROOT/tb/clock_divider/tb_clk_divider.sv"
  [tb_gf_mux]="$ROOT/tb/clock_mux/tb_gf_mux.sv"
)

# RTL needed per TB group
RTL_CDC="$ROOT/rtl/cdc/reset/rst_sync.sv $ROOT/rtl/cdc/level/cdc_level_sync.sv $ROOT/rtl/cdc/pulse/cdc_pulse_sync.sv $ROOT/rtl/cdc/handshake/cdc_handshake.sv $ROOT/rtl/cdc/gray/cdc_gray_sync.sv"
RTL_DIV="$ROOT/rtl/clock_divider/clk_divider.sv"
RTL_MUX="$ROOT/rtl/clock_mux/gf_mux_seq.sv"

declare -A TB_RTL=(
  [tb_rst_sync]="$RTL_CDC" [tb_cdc_level_sync]="$RTL_CDC" [tb_cdc_pulse_sync]="$RTL_CDC"
  [tb_cdc_handshake]="$RTL_CDC" [tb_cdc_gray_sync]="$RTL_CDC"
  [tb_clk_divider]="$RTL_DIV" [tb_gf_mux]="$RTL_MUX"
)

TBS=("$@")
if [ ${#TBS[@]} -eq 0 ]; then
  TBS=(tb_rst_sync tb_cdc_level_sync tb_cdc_pulse_sync tb_cdc_handshake tb_cdc_gray_sync tb_clk_divider tb_gf_mux)
fi

mkdir -p "$OUTBASE"
PASS_ALL=1

# xelab flags may be overridden, e.g. XELAB_FLAGS="-O0 -debug typical" for
# fast functional-only elaboration on heavily loaded machines.
XELAB_FLAGS="${XELAB_FLAGS:--debug typical}"

for tb in "${TBS[@]}"; do
  dir="$OUTBASE/$tb"
  mkdir -p "$dir"
  echo "=== $tb ==="

  # incremental: skip TBs with complete results unless FORCE=1
  if [ "${FORCE:-0}" != "1" ] && [ -f "$dir/xsim_s3.log" ] \
     && grep -q "TEST PASSED\|TEST FAILED" "$dir/xsim_s3.log"; then
    echo "  cached result present ($(grep -o 'tests=[0-9]* errors=[0-9]*' "$dir/xsim_s3.log" | tail -1)) — FORCE=1 to rerun"
    continue
  fi

  # util pkg only used by CDC TBs; harmless elsewhere but keep include tight
  UTIL=""
  case "$tb" in tb_rst_sync|tb_cdc_*) UTIL="$ROOT/tb/cdc/tb_util_pkg.sv";; esac

  pushd "$dir" > /dev/null

  if ! xvlog -sv -i "$ROOT/rtl/common" $UTIL "$PKG" ${TB_RTL[$tb]} "${TB_TOP[$tb]}" > xvlog.log 2>&1; then
    echo "  XVLOG FAILED (xvlog.log)"; grep -m5 "ERROR" xvlog.log; PASS_ALL=0; popd > /dev/null; continue
  fi
  if ! xelab $XELAB_FLAGS -s snap "$tb" > xelab.log 2>&1; then
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
