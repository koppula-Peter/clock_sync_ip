#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# vivado_ooc_synth.sh — out-of-context synthesis + CDC/timing report bundle
# Usage: scripts/vivado_ooc_synth.sh [m1|all]   (default: m1)
# Outputs: build/synth/ooc/<module>/*.dcp + build/reports/synth/<module>/...
# Requires: vivado in PATH (script self-bootstraps like run_xsim_regression.sh)
# ---------------------------------------------------------------------------
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/synth/ooc"
RPTS="$ROOT/build/reports/synth"

if ! command -v vivado >/dev/null 2>&1; then
  CANDS="${XILINX_TOOLS:-}/Vivado/settings64.sh"
  for v in 2025.2 2025.1 2024.2; do
    CANDS="$CANDS $HOME/Desktop/xilinx_tools/$v/Vivado/settings64.sh /tools/Xilinx/$v/Vivado/settings64.sh /opt/Xilinx/$v/Vivado/settings64.sh"
  done
  for s in $CANDS; do
    [ -f "$s" ] || continue
    # shellcheck disable=SC1090
    source "$s"; break
  done
fi
command -v vivado >/dev/null 2>&1 || { echo "ERROR: vivado not in PATH"; exit 2; }

PKG="$ROOT/rtl/common/clk_sync_cdc_pkg.sv"
INC="$ROOT/rtl/common"

declare -A TOP_SRCS=(
  [rst_sync]="$ROOT/rtl/cdc/reset/rst_sync.sv"
  [cdc_level_sync]="$ROOT/rtl/cdc/level/cdc_level_sync.sv"
  [cdc_pulse_sync]="$ROOT/rtl/cdc/pulse/cdc_pulse_sync.sv"
  [cdc_handshake]="$ROOT/rtl/cdc/handshake/cdc_handshake.sv"
  [cdc_gray_sync]="$ROOT/rtl/cdc/gray/cdc_gray_sync.sv"
)

TARGET="${1:-m1}"
case "$TARGET" in
  m1) MODULES=(rst_sync cdc_level_sync cdc_pulse_sync cdc_handshake cdc_gray_sync) ;;
  all) MODULES=("${!TOP_SRCS[@]}") ;;
  *) if [ -n "${TOP_SRCS[$TARGET]:-}" ]; then MODULES=("$TARGET"); else echo "unknown target '$TARGET'"; exit 2; fi ;;
esac

mkdir -p "$OUT" "$RPTS"
PASS_ALL=1

for mod in "${MODULES[@]}"; do
  echo "=== OOC synth: $mod ==="
  mdir="$OUT/$mod"; rdir="$RPTS/$mod"
  mkdir -p "$mdir" "$rdir"
  TCL="$mdir/ooc_$mod.tcl"
  cat > "$TCL" <<TCL
set prj "$mdir/$mod"
set part xc7z020clg484-1
create_project -force -part \$part ooc_\$mod "\$(dirname \$prj)"
read_verilog -sv {$PKG} {${TOP_SRCS[$mod]}}
synth_design -top $mod -part \$part -mode out_of_context
report_utilization                -file "$rdir/utilization.rpt"
report_timing_summary -delay_type max -file "$rdir/timing.rpt"
report_cdc                        -file "$rdir/cdc.rpt"
report_methodology                -file "$rdir/methodology.rpt"
write_checkpoint -force "$mdir/$mod.dcp"
TCL
  if ! vivado -mode batch -nojournal -nolog -source "$TCL" > "$rdir/vivado.log" 2>&1; then
    echo "  FAILED ($rdir/vivado.log)"; grep -m5 "ERROR" "$rdir/vivado.log"; PASS_ALL=0
  else
    echo "  OK -> $mdir/$mod.dcp"
  fi
done

echo "==================================================="
if [ $PASS_ALL -eq 1 ]; then echo "OOC SYNTH RESULT: ALL PASSED"; else echo "OOC SYNTH RESULT: FAILURES PRESENT"; fi
exit $PASS_ALL
