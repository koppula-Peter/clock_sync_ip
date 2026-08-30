#!/usr/bin/env bash
# run_yosys_formal.sh — bounded-model-check a formal harness with yosys+smtbmc
# Usage: formal/run_yosys_formal.sh <top> [depth]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOP="${1:?usage: run_yosys_formal.sh <top> [depth]}"
DEPTH="${2:-300}"
OUT="$ROOT/build/formal/$TOP"
mkdir -p "$OUT"

case "$TOP" in
  formal_gray_core) SRC="$ROOT/formal/formal_gray_core.sv";;
  formal_rst_sync)  SRC="$ROOT/rtl/cdc/reset/rst_sync.sv $ROOT/formal/formal_rst_sync.sv";;
  *) echo "unknown harness $TOP"; exit 2;;
esac

yosys -q -p "read_verilog -formal -sv -DCLKSYNC_FORMAL -I$ROOT/rtl/common $SRC; \
             prep -top $TOP; async2sync; opt -fast; dffunmap; write_smt2 -wires $OUT/$TOP.smt2" \
     > "$OUT/yosys.log" 2>&1 || { echo "YOSYS FAILED ($OUT/yosys.log)"; tail -5 "$OUT/yosys.log"; exit 1; }

if yosys-smtbmc -s z3 --presat --noprogress -t "$DEPTH" -m "$OUT/$TOP.smt2" \
      > "$OUT/smtbmc.log" 2>&1; then
  echo "$TOP: FORMAL PASS (depth=$DEPTH)"
else
  echo "$TOP: FORMAL FAIL — see $OUT/smtbmc.log"; grep -m3 "Assert failed\|BMC failed" "$OUT/smtbmc.log"; exit 1
fi
