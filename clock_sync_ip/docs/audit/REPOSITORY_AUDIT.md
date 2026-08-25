# Repository Audit — Clocking and Synchronization IP Suite

| Field | Value |
|---|---|
| Audit date | 2026-08-25 |
| Auditor | Principal FPGA architect (automated first-pass, per mandate §1) |
| Repository path | `/home/peter/Desktop/IP_dev/clocking` |
| Git status | Part of the `IP_dev` monorepo (`main`), remote `github.com/koppula-Peter/IP_dev.git`. At original audit time this directory was standalone and not under version control; consolidated into `IP_dev` 2026-08-25 (see §9). |
| Project root created | `<repo>/clock_sync_ip/` |
| Version | v0.0.0-audit (pre-M1) |

---

## 1. Method

Performed before writing any RTL (mandate §1):

1. Full recursive listing of the working directory.
2. Git status / log inspection.
3. Tool-chain discovery on host (`PATH` scan of all relevant EDA tools).
4. Vivado installation inspection (`2025.2` tree, XPM availability).
5. Cross-check of board/device documentation identifiers against AMD published
   sources (see `docs/reference/AMD_CLOCKING_REFERENCE_MAP.md`).

## 2. Repository state

**The working directory was completely empty** at audit time:

```
/home/peter/Desktop/IP_dev/clocking/
    (no files, no directories)
```

Consequences:

- There is no existing RTL, testbench, constraint file, TCL script, software,
  driver, documentation, TODO/FIXME marker, placeholder, stub, generated
  artifact, duplicate implementation, partially implemented IP, or failing test
  to preserve, migrate, or deprecate.
- No previous architectural decisions exist. All architecture decisions start
  from this document forward and are recorded in `DECISIONS.md`.
- No user code can be damaged by restructuring; nothing needs deletion.
- Traceability obligation: this document is the baseline "empty" evidence. All
  later components are traceable to requirements written after this point.

## 3. Component inventory and classification

Classification per mandate §1: COMPLETE / VERIFIED / PARTIAL / PLACEHOLDER /
BROKEN / UNTESTED / MISSING / DEPRECATED.

### 3.1 The sixteen mandated IP blocks

| # | Block | Classification | Notes |
|---|---|---|---|
| IP-01 | Clock Divider | MISSING | To be built in M2 (Mode A clock-enable divider preferred) |
| IP-02 | Clock Multiplier Control | MISSING | Requires MMCM/PLL + DRP backend (M6) |
| IP-03 | Clock Mux | MISSING | Production path must use BUFGCTRL-class resources (M2) |
| IP-04 | Glitch-Free Clock Mux | MISSING | BUFGCTRL semantics verified against UG472 v1.14 (M2) |
| IP-05 | Clock Monitor | MISSING | M3 |
| IP-06 | Clock-Frequency Monitor | MISSING | M3 |
| IP-07 | Clock-Failure Detector | MISSING | M3 |
| IP-08 | Phase Detector | MISSING | M4 |
| IP-09 | Digital PLL | MISSING | Mathematical model required before RTL (M5) |
| IP-10 | Software PLL | MISSING | PS-based; bare-metal vs Linux split required (M7) |
| IP-11 | Frequency-Locked Loop | MISSING | M5 |
| IP-12 | CDC Framework | MISSING | Pattern library; begins M1 |
| IP-13 | Level Synchronizer | MISSING | M1 |
| IP-14 | Pulse Synchronizer | MISSING | M1 |
| IP-15 | Handshake Synchronizer | MISSING | M1 |
| IP-16 | Gray-Code Synchronizer | MISSING | M1 |

### 3.2 Supporting blocks

All supporting blocks listed in the mandate (reset synchronizers, timeout
engines, frequency counters, configuration registers, AXI4-Lite wrapper,
interrupt controller, health manager, etc.) are **MISSING**. None exist in any
form.

### 3.3 Verification assets

| Asset | Classification |
|---|---|
| Unit testbenches | MISSING |
| Assertions / formal properties | MISSING |
| Coverage model | MISSING |
| Reference models (Python) for DPLL/FLL | MISSING |
| CDC structural analysis runs | MISSING |
| Timing analysis runs | MISSING |

### 3.4 Documentation

| Document | Classification |
|---|---|
| Requirements / traceability | MISSING (created from M1 onward) |
| Architecture documents | MISSING |
| Interface/register maps | MISSING |
| Build/validation guides | MISSING |
| This audit + reference map | CREATED (this milestone) |

## 4. Environment audit (verified by execution)

| Tool | Version / Path | Status | Role in project |
|---|---|---|---|
| Vivado | 2025.2 — `~/Desktop/xilinx_tools/2025.2/Vivado/bin/vivado` | PRESENT | Synthesis, implementation, timing, `report_cdc`, DRC, xsim |
| xsim / xvlog | same install | PRESENT | Primary SystemVerilog simulator (SVA support) |
| Verilator | 5.032 (Debian) | PRESENT | Lint + fast regression cross-check |
| Icarus Verilog | 12.0 stable | PRESENT | Secondary simulator |
| Yosys | 0.52 (git fee39a32) | PRESENT | Structural synthesis checks, formal prep |
| yosys-smtbmc | bundled with Yosys | PRESENT | Formal property checking engine |
| Z3 / Boolector | present | PRESENT | SMT solvers for formal |
| Python | 3.14.4 | PRESENT | Reference models, regression scripting |
| GNU make / gcc | 4.4.1 / 15.2.0 | PRESENT | Software builds (bare-metal cross-toolchain arrives with Vitis work in M7) |
| GTKWave | present | PRESENT | Waveform debugging |
| cocotb | not installed | ABSENT | Optional; SV-first strategy makes it non-blocking (OPEN_ISSUE OI-003) |
| SymbiYosys (sby) | not installed | ABSENT | Replaced by direct `yosys write_smt2` + `yosys-smtbmc` flow (documented) |
| Vitis | **not found in this environment** | ABSENT | Required only from M7 (PS software). Recorded as open issue OI-002 |
| ZC702 board | not attached to this machine | ABSENT | Hardware validation (Gate I) is gated on physical access; all pre-silicon gates are executable here |

Vivado batch-mode operability will be proven by the M1 out-of-context synthesis
run (Gate C evidence); if licensing blocks it, that becomes a blocking open
issue.

## 5. Hardware reference facts established (authoritative)

Verified against AMD-published documents (full map:
`docs/reference/AMD_CLOCKING_REFERENCE_MAP.md`):

- **UG472 (v1.14)** — 7 Series clocking: BUFGCTRL switches between two
  asynchronous clocks glitch-free (falling-edge sensitive, output held Low until
  the newly selected clock transitions High→Low→drives; `INIT_OUT` selects
  polarity); BUFGCE completes the current pulse then gates; BUFGMUX select has a
  setup-time requirement (violations cause glitches); asynchronous-mux use model
  via IGNORE pins disables glitch protection.
- **UG850 (v1.7)** — ZC702: system clock = fixed 200 MHz LVDS oscillator
  (SiT9102, ±50 ppm) on MRCC pins `SYSCLK_P=D18 / SYSCLK_N=C19`, bank 35,
  I/O standard LVDS_25; programmable user clock Si570 default 156.250 MHz
  (10–810 MHz range) on `USRCLK_P=Y9 / USRCLK_N=Y8` bank 13; PS_CLK 33.333 MHz
  single-ended on F7.

Exact MMCM/PLL frequency-window numbers for XC7Z020-CLG484-1 will be extracted
from the installed 2025.2 timing models when M2/M6 need them (tracked as
OI-001); they are deliberately **not** quoted here from memory.

## 6. Unsupported assumptions found

None inherited — greenfield. Assumptions going forward are tracked in
`OPEN_ISSUES.md`:

| ID | Issue | Disposition |
|---|---|---|
| OI-001 | Exact MMCM/VCO window values for -1 speed grade not yet extracted from installed tool data | Extract during M2; no RTL depends on them yet |
| OI-002 | Vitis 2025.2 not present on this host | Blocks M7 software execution only; driver code can be developed and reviewed earlier |
| OI-003 | cocotb absent | Non-blocking; SV/xsim primary verification path |
| OI-004 | No physical ZC702 attached to this workstation | Gates Gate I (hardware validation), not Gates A–H |

## 7. Conclusion

Greenfield project, empty baseline, full toolchain except Vitis/board. Nothing
to preserve or refactor. Development proceeds exactly per the mandated order:
M1 CDC Foundation next (reset, level, pulse, handshake, gray synchronizers),
each with spec → RTL → self-checking TB → randomized async-clock tests →
assertions/formal → Vivado synthesis → `report_cdc`/timing review →
documentation → qualification report.

## 9. Provenance & repository-lineage record

* 2026-08-25 (audit time): suite developed in a standalone directory, **not**
  under version control.
* 2026-08-25 (consolidation): imported into the `IP_dev` monorepo under
  `IP_dev/clocking/clock_sync_ip/`; sources recovered from workspace snapshot
  branch `divergent-backup` after a repo realignment dropped them from the
  working tree.
* 2026-08-25 (extraction, current home): moved back out to a dedicated
  standalone repository to isolate it from monorepo churn:

```text
local : /home/peter/Desktop/clock_sync_ip            (branch main)
remote: github.com/koppula-Peter/clock_sync_ip       (private)
lineage: git subtree split of IP_dev main prefix clocking/
         IP_dev@c9a753c7 -> clock_sync_ip@a18ad2b1
         full per-commit file history preserved; removal commit
         IP_dev@3ddad5f1 records the handoff on the monorepo side
```

* Non-project files that had been parked alongside the IP (`clocking/ncurses5/`,
  `clocking/xilinx_env.sh`) were intentionally NOT carried into this repository.
  `scripts/run_xsim_regression.sh` bootstraps the environment itself: it sources
  Vivado `settings64.sh` from `$XILINX_TOOLS` or well-known locations. NOTE:
  xsim requires the `libncurses.so.5` soname which this OS does not ship; a
  compat-shim directory of symlinks to the system ncurses6 is maintained
  OUTSIDE the repo at `/home/peter/Desktop/xilinx_tools/ncurses5/` and picked up
  automatically (tracked as OI-006).
