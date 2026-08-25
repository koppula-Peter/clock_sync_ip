# Milestone 1 — CDC Foundation Report

Status: **IN PROGRESS** (this file is updated only with executed evidence)

```text
Implemented   : YES — all five foundation blocks + shared package
Verified      : see §2 (unit regression cycle executing)
Synthesized   : PENDING — OOC run queued after regression
CDC-clean     : PENDING — first report_cdc bundle not yet generated
Timing status : N/A yet — no implementation pass
Coverage      : functional coverage via directed + randomized TB checks;
                formal coverage not yet instrumented
Formal status : PENDING — yosys-smtbmc harnesses planned (mandate §37)
Known limitations : §5
Open blockers : OI-002 (Vitis), OI-004 (no board), OI-006 (ncurses shim,
                resolved out-of-repo)
Evidence      : build/sim/xsim/, build/reports/synth/ (once produced)
```

## 1. Implemented

| Block | RTL | Spec | TB |
|---|---|---|---|
| rst_sync | `rtl/cdc/reset/rst_sync.sv` | docs/modules/M1_RST_SYNC_SPEC.md | tb/cdc/tb_rst_sync.sv |
| cdc_level_sync | `rtl/cdc/level/cdc_level_sync.sv` | docs/modules/M1_LVL_SYNC_SPEC.md | tb/cdc/tb_cdc_level_sync.sv |
| cdc_pulse_sync | `rtl/cdc/pulse/cdc_pulse_sync.sv` | docs/modules/M1_PULSE_SYNC_SPEC.md | tb/cdc/tb_cdc_pulse_sync.sv |
| cdc_handshake | `rtl/cdc/handshake/cdc_handshake.sv` | docs/modules/M1_HS_SYNC_SPEC.md | tb/cdc/tb_cdc_handshake.sv |
| cdc_gray_sync (+pkg) | `rtl/cdc/gray/cdc_gray_sync.sv`, `rtl/common/clk_sync_cdc_pkg.sv` | docs/modules/M1_GRAY_SYNC_SPEC.md | tb/cdc/tb_cdc_gray_sync.sv |

Shared attribute/validation touchpoint: `rtl/common/clk_sync_attributes.vh`
(AD-002). Static gates: Verilator `-Wall` lint clean on all five modules
(2026-08-25).

## 2. Verified

Unit regressions execute under Vivado xsim with 3 fixed seeds per testbench
(`scripts/run_xsim_regression.sh`). Testbenches are self-checking with SVA +
watchdogs and sweep mandated clock ratios (§32 list incl. 100→99 / 100→101 MHz,
17→113 MHz, randomized destination periods).

| Module | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| tb_rst_sync | PENDING-RUN | PENDING-RUN | PENDING-RUN |
| tb_cdc_level_sync | PENDING-RUN | PENDING-RUN | PENDING-RUN |
| tb_cdc_pulse_sync | PENDING-RUN | PENDING-RUN | PENDING-RUN |
| tb_cdc_handshake | PENDING-RUN | PENDING-RUN | PENDING-RUN |
| tb_cdc_gray_sync | PENDING-RUN | PENDING-RUN | PENDING-RUN |

(This table is filled exclusively from `build/sim/xsim/<tb>/xsim_s<N>.log`.)

## 3. Synthesized / CDC

OOC synthesis per module (xc7z020clg484-1) via
`scripts/vivado_ooc_synth.sh m1`; produces utilization/timing/report_cdc/
methodology bundles under `build/reports/synth/<module>/`. First run queued
behind the unit regression (single workstation contention).

## 4. Traceability

Requirements → specs → RTL → TB mapping is recorded per module in
`docs/modules/M1_*_SYNC_SPEC.md` §6 tables against
`docs/requirements/REQUIREMENTS.md`. Consolidated matrix lands with Gate D
closure.

## 5. Known limitations

* Pulse synchronizer drops under-separated events by design (flagged).
* Handshake throughput limited to one word per 4-phase round trip.
* Gray synchronizer samples may skip source values at extreme ratios.
* No formal proofs yet; simulation + structural review only at this point.
