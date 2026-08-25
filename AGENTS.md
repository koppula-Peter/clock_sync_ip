# AGENTS.md — clock_sync_ip working rules for AI/dev sessions

Standalone repo: Clocking & Synchronization IP Suite (Zynq-7000 / ZC702,
Vivado 2025.2). Governing mandate: industrial-grade IP development (see
`clock_sync_ip/docs/` and git history for decision records).

## Repo layout

Project root is `clock_sync_ip/` inside this repository (kept so sibling IPs
can join later). All commands below assume `cd clock_sync_ip`.

## Session start checklist

1. Read `SESSION_STATE.md` (live handoff: where we are, exact next actions).
2. Read `CURRENT_STATUS.md`, `OPEN_ISSUES.md`, latest milestone report under
   `docs/milestones/`.
3. Check running sims: `pgrep -af xelab | grep -v pgrep`,
   `tail build/sim/xsim/*/xsim_s*.log`.
4. NEVER trust status docs over actual logs; docs must be updated FROM logs.

## Environment quirks (this workstation)

* Tools NOT on PATH by default. Scripts self-bootstrap from
  `$XILINX_TOOLS/Vivado/settings64.sh` or `~/Desktop/xilinx_tools/2025.2/...`.
* xsim needs `libncurses.so.5`; compat shim lives OUTSIDE the repo at
  `/home/peter/Desktop/xilinx_tools/ncurses5/` (symlinks to system ncurses6).
  See OI-006.
* Host is often HEAVILY loaded by parallel agent sessions. Before launching
  Vivado jobs check `/proc/loadavg`. Use
  `scripts/wait_and_regression.sh` (starts when load < LOAD_MAX, default 10)
  or pass `XELAB_FLAGS="-O0 -debug off"` to elaborate fast without debug info.
* Long jobs MUST run detached:
  `setsid bash <script> </dev/null >log 2>&1 & disown`
  (plain `&` dies with the tool timeout). Never use `pkill -f <pattern>` from
  inside a command whose own cmdline contains that pattern.

## Flows

```bash
# unit regression (all M1 TBs, 3 seeds each)
scripts/run_xsim_regression.sh            # add TB names to run subset
# OOC synthesis + CDC/methodology/timing reports per module
scripts/vivado_ooc_synth.sh m1            # or: <module-name>
# static lint gate
verilator --lint-only -Wall --top-module <mod> -Irtl/common <files...>
```

Results land in `build/sim/xsim/<tb>/` and `build/synth/ooc/`,
reports in `build/reports/synth/<module>/`. `build/` is never committed.

## Working rules

* Milestone order fixed by mandate: M1 CDC → M2 div/mux → M3 supervision →
  M4 measurement → M5 loops → M6 MMCM ctrl → M7 PS/PL → integration.
* Every module: spec → RTL → self-checking TB (+SVA) → lint → regression →
  synth → report_cdc → docs. "Compiles" ≠ complete.
* Update `VERIFICATION_STATUS.md` only from executed evidence.
* Commit after every verified step; pathspec-scoped commits
  (`git commit -- <paths>`) if other sessions share this worktree.
* Push to origin after every commit batch. Keep `SESSION_STATE.md` current —
  it is the cross-session memory; write it so a fresh session can resume
  with zero context recovery.
