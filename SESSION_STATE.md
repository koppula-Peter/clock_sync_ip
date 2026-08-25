# SESSION_STATE.md — live handoff (update in real time)

> New session? Read this top-to-bottom, then AGENTS.md. Do not re-derive state
> from git log alone. Last updated: 2026-08-25 ~20:45 IST

## Where the project is

M1 (CDC Foundation): Gate C done; Gate D executing — xsim regression detached
(log /tmp/opencode/m1_regression.log, auto-chained to OOC synth via
scripts/run_m1_gate_d.sh, PID may be re-found with pgrep -f run_m1_gate_d).
CRITICAL HOST ISSUE: swap 100% full (7/7GB, 8.4GB swapped out) from parallel
agent sessions -> xelab runs ~5% speed. Sims WILL finish eventually; do not
kill them without checking RSS/swap first. Consider asking the user to close
other agent sessions before heavy Vivado steps.

M2 started early (authoring while M1 evidence collects):
- DONE+lint-clean: rtl/clock_divider/clk_divider.sv + tb + spec doc
  (CLK-DIV-REQ-*); rtl/clock_mux/gf_mux_seq.sv + xilinx_7series/
  gf_mux_bufgctrl_7series.sv + clock_mux_generic_ref.sv + tb_gf_mux
  (CLK-GFMUX-REQ-*); requirements appended to REQUIREMENTS.md.
- NEXT after regression/synth land: add tb_clk_divider + tb_gf_mux to
  run_xsim_regression.sh list; run them; then write M2_CLOCK_CONTROL_REPORT.md.

## Executing right now / last known run

* M1 xsim regression: `scripts/wait_and_regression.sh` auto-starts it when
  host load < 10; log `/tmp/opencode/m1_regression.log`; results under
  `clock_sync_ip/build/sim/xsim/<tb>/xsim_s{1,2,3}.log`.
* Known issue this host: xelab takes ~15-25 CPU-min per TB even at -O0 when
  other agent sessions load the box (RAM 25/30 GB). If a run seems hung check
  RSS/CPU of the xelab PID before killing anything.

## Exact next actions (in order)

1. When regression finishes: read each `xsim_s*.log` verdict line
   (`tests=N errors=M` + `*** TEST PASSED ***`).
2. Fill VERIFICATION_STATUS.md table + M1_CDC_FOUNDATION_REPORT.md §2 from
   those logs (PASS/FAIL per seed). Commit.
3. Run OOC synth: `setsid bash scripts/vivado_ooc_synth.sh m1 </dev/null
   >/tmp/opencode/m1_ooc.log 2>&1 & disown` (queue AFTER regression to avoid
   CPU fight). Check build/reports/synth/<mod>/cdc.rpt for UNSAFE entries;
   justify or fix — never waive silently. Update report §3. Commit.
4. Formal harnesses (yosys-smtbmc) for gray single-bit-change + handshake
   liveness (mandate §37) — files under formal/, wire into docs.
5. Start M2: add CLK-DIV/CLK-MUX/GFMUX requirements → clk_divider RTL+TB →
   gf-mux Layer-1 controller + BUFGCTRL backend + edge-sweep TB.

## Decisions already taken (do not relitigate)

* Two-layer architecture, ASYNC_REG macro touchpoint (AD-002); enable-ticks
  over fabric clocks (AD-003); BUFGCTRL-class mux only (AD-004);
  xsim primary + verilator lint + yosys formal stack (AD-005);
  async-assert/sync-deassert reset policy (AD-006).
* Standalone repo at ~/Desktop/clock_sync_ip, private GitHub remote
  koppula-Peter/clock_sync_ip. IP_dev keeps NO clocking content (provenance
  commit 3ddad5f1 there).

## Blockers / watchouts

* OI-002 Vitis absent (M7 sw execution), OI-004 no ZC702 (Gate I deferred),
  OI-006 ncurses shim out-of-repo.
* Host contention: multiple parallel agent sessions share this machine; use
  load-aware launchers and detached runs (see AGENTS.md).
