# AMD Clocking Reference Map — 7-Series / Zynq-7000 / ZC702

Purpose: bind every architectural decision of this IP suite to an authoritative
AMD/Xilinx document section, record the primitive used, why, its limitations,
and device-portability implications.

**Rule:** no device behaviour is invented here. Where a numeric device limit is
needed and has not yet been extracted from the installed 2025.2 tool data, the
gap is recorded in `OPEN_ISSUES.md` (OI-001) rather than guessed.

---

## 1. Source documents (identifiers verified)

| ID | Title | Revision | Used for |
|---|---|---|---|
| UG472 | 7 Series FPGAs Clocking Resources User Guide | v1.14 (2018-07-30), still the current 7-series clocking guide referenced by UG949 | BUFG/BUFGCTRL/BUFGCE/BUFGMUX semantics, MMCM/PLL architecture, clock routing regions |
| UG850 | ZC702 Evaluation Board for the Zynq-7000 XC7Z020 SoC User Guide | v1.7 (2019-03-27) | Board clocks, pins, I/O standards |
| UG585 | Zynq-7000 SoC Technical Reference Manual | current | PS clocks/PS-PL interfaces (M7) |
| DS190 | Zynq-7000 All Programmable SoC Overview | current | Device family context (XC7Z020 resources) |
| UG470 | 7 Series FPGAs Configuration User Guide | current | STARTUP/CLOCK feedback caveats for generated clocks at startup |
| UG903 | Vivado Design Suite User Guide: Using Constraints | installed 2025.2 version | `create_clock`, `create_generated_clock`, `set_clock_groups`, `set_max_delay -datapath_only`, `set_bus_skew` |
| UG949 | UltraFast Design Methodology Guide (contains "7 Series Device Clocking" chapter + CDC methodology) | installed 2025.2 version | CDC topology rules, synchronizer MTBF guidance, `report_cdc` usage |
| UG953 | Vivado Design Suite 7 Series FPGA and Zynq-7000 SoC Libraries Guide (XPM macros) | installed 2025.2 version | XPM_CDC_SINGLE / XPM_CDC_GRAY / XPM_CDC_HANDSHAKE attributes (`DEST_SYNC_FF` 2–10, ASYNC_REG handling, CDC-6 note for Gray buses) |

## 2. Primitive decision map

### 2.1 Synchronizer flops — M1 scope

| Decision | Reference | Detail |
|---|---|---|
| 2-FF (or deeper) destination-domain flops with `ASYNC_REG="TRUE"` for every level/pulse/handshake/gray crossing | UG949 CDC methodology; UG472 §“Clock Domain Crossing”; UG953 XPM_CDC_* | `ASYNC_REG` keeps the pair placed together in one SLICE (reduces skew between stages → maximizes resolution time) and marks them as synchronizers for `report_cdc` classification |
| No combinational logic between synchronizer stages | UG949 CDC rules | Combinational logic between stages defeats metastability resolution and confuses CDC analysis |
| Depth default 2, parameterizable to more | UG953 `DEST_SYNC_FF` range 2–10 | MTBF requirement drives depth; documented per-module, not claimed numerically without device/timing data |
| Reset: async assert / sync deassert inside each domain; reset synchronizers themselves use ASYNC_REG flops | UG949 reset methodology | Prevents recovery/removal violations on reset release |

### 2.2 Physical clock switching — M2/M3 scope

| Decision | Reference (UG472 v1.14) | Limitations recorded |
|---|---|---|
| Production glitch-free 2-input mux = **BUFGCTRL** (or BUFGMUX_CTRL configuration thereof) | Ch.2 “Global Clock Buffer Primitives”, Fig 2-3/2-4 | Default switching is falling-edge sensitive; output held Low until outgoing clock High→Low completes, then incoming begins. Switching latency therefore depends on both clock periods — must be measured/documented per instance |
| Clock gating = **BUFGCE** (completes pulse then gates Low) or BUFGCE_1 (gates High); never LUT-gated fabric clocks | Ch.2 “BUFGCE and BUFGCE_1” | CE has setup-time relationship to input clock (TBCCCK_CE); violating it risks glitches |
| Stopped-clock switch-over: if the outgoing clock stops mid-switch, standard BUFGCTRL edge-wait cannot complete → use the documented **asynchronous-mux use model with IGNORE pins** only when a supervisor guarantees safety | Ch.2 “Additional Use Models — Asynchronous MUX Using BUFGCTRL” | IGNORE disables glitch protection; our health manager must quiesce consumers first (M3 policy) |
| N-way selection via cascaded BUFGCTRLs | Ch.2 “Cascading BUFGs” (ring of 16 per half) | Cascading multiplies worst-case switch latency; document per build |
| `select` changes faster than the switching sequence are rejected by our wrapper FSM (busy/lockout) | consequence of TBCCCK_CE setup + edge-wait sequence | Rapid select toggling would otherwise produce undefined output states |

### 2.3 Clock generation — M6 scope

| Decision | Reference | Notes |
|---|---|---|
| Multiplication/division/phase only through **MMCM/PLL** hard primitives; DRP port for runtime reconfig | UG472 Ch.3 (MMCM/PLL), DRP sections | Fabric-NCO outputs are timing ticks/enables, never distributed as global clocks (mandate §16) |
| Lock monitoring via LOCKED pin + qualification counter before releasing outputs | UG472 lock behaviour; mandate §9 flow | Loss-of-lock → safe state |
| Input buffering IBUFDS→MMCM (MRCC-capable pins on ZC702: SYSCLK D18/C19 bank35, USRCLK Y9/Y8 bank13) | UG850 Table 1-12; UG472 MMCM input options | Compensation/buffering chosen by tools; do not hand-instantiate conflicting buffers |

### 2.4 Board facts (ZC702, from UG850 v1.7)

| Clock | Source | Pins / bank | Standard | Tolerance |
|---|---|---|---|---|
| System clock | SiT9102 fixed LVDS oscillator, 200 MHz | SYSCLK_P=D18, SYSCLK_N=C19, MRCC bank 35 | LVDS_25 | ±50 ppm |
| User clock | Si570 programmable LVDS, default 156.250 MHz (10–810 MHz via I²C) | USRCLK_P=Y9, USRCLK_N=Y8, MRCC bank 13 | LVDS_25 | per Si570 spec |
| PS clock | SiT8103 fixed 33.333 MHz single-ended | F7 (PS bank 500) | — | ±50 ppm |

These two independent PL oscillators (200 MHz fixed + Si570 programmable) give
us genuine asynchronous source pairs for hardware validation of muxes,
monitors, and loops.

### 2.5 Timing/CDC constraint mapping (per UG903)

| Crossing type | Constraint pattern | Why safe |
|---|---|---|
| Single-bit level sync | `set_false_path -to [get_pins ...sync_ff_reg[*]/D]` (or ASYNC_REG-driven report_cdc SAFE classification) | Data semantics tolerate arbitrary capture delay; synchronizer resolves metastability |
| Multi-bit coherent (handshake) | `set_max_delay -datapath_only <min period>` on data path + false path on req/ack control | Data held stable while req high; max_delay bounds skew so the sampled word is coherent |
| Gray pointer/counter | `set_max_delay -datapath_only` + `set_bus_skew` on gray bus | One-bit-change property makes any sample legal; bus-skew bound prevents illegal multi-bit mix |
| Async reset assert | async path by construction; deassertion synchronized per domain | Recovery/removal timed normally after sync stage |

Every exception gets an entry in `docs/implementation/TIMING_CONSTRAINTS.md`
with reason + supporting verification when first applied.

## 3. Device-portability statement

Layer-1 portable RTL (all M1 modules, monitors, counters, loops' math cores)
uses pure synthesizable Verilog-2001/SystemVerilog subset with a single
vendor-specific touchpoint: the `ASYNC_REG` attribute, isolated behind
parameterized attribute declarations so other families can remap it. Layer-2
(`rtl/xilinx_7series/`) contains all BUFG/MMCM/DRP instantiations. A future
backend family replaces only Layer-2 plus constraints.

## 4. Known limitations carried forward

1. Simulation cannot prove metastability immunity (mandate §33). Evidence =
   topology review + ASYNC_REG + placement + `report_cdc` + MTBF discussion;
   never a simulation claim.
2. BUFGCTRL switch latency is data-dependent (both clock periods); each
   integration must re-measure/document it.
3. Gray-code observation may skip values at the destination when source runs
   much faster; correctness must never depend on seeing every intermediate
   value.
4. Exact XC7Z020-1 MMCM/VCO windows pending extraction (OI-001).
