# M2 Module Specification — Glitch-Free Clock Mux (gf_mux_seq + backend)

- Requirements: `docs/requirements/REQUIREMENTS.md` §CLK-GFMUX, §CLK-MUXREF
- RTL Layer-1: `rtl/clock_mux/gf_mux_seq.sv` (switch protocol)
- RTL Layer-2: `rtl/xilinx_7series/gf_mux_bufgctrl_7series.sv` (BUFGCTRL map)
- Reference:   `rtl/clock_mux/clock_mux_generic_ref.sv` (education only, AD-004)
- Testbench:   `tb/clock_mux/tb_gf_mux.sv`
- References:  UG472 BUFGCTRL chapter; mandate §10/§11/§34
- Status: IMPLEMENTED / lint-clean / unit sim queued

## 1. Architecture

```text
            sel_i  force_off_i
              │         │
        ┌─────▼─────────▼─────┐  ce0/ce1/s   ┌──────────────────┐
ref_clk │     gf_mux_seq      ├─────────────►│ BUFGCTRL (7s)    ├──► clk_o
        │  (kill→quiesce→arm→ │              └───┬──────────┬───┘
        │   gate, safety FSM) │              I0  │          │  I1
        └─────▲─────────▲──────┘          clk0 ──┘          └── clk1
           src0_alive  src1_alive        (from clock monitors, M3)
```

Layer separation per AD-002: the sequencer contains zero vendor primitives;
all clock gating happens in BUFGCTRL whose CE inputs are sampled by their own
source clocks (UG472) — the hardware property that makes switching glitch-free.
The TB replicates that sampling semantics behaviourally so protocol bugs are
detectable pre-synthesis.

## 2. Switching protocol (per transition)

| Stage | Action | Exit condition |
|---|---|---|
| KILL_OLD | deassert old CE | immediate |
| QUIESCE | wait for old source to stop driving the gate | `old_alive` fall **or** `TIMEOUT_REF_CYCLES` |
| SETTLE | guard band (≥2 ref cycles) | counter |
| ARM_NEW | S lines stable on new source | counter |
| GATE_NEW | assert new CE; pulse `sw_done_o` | → IDLE |

Guarantees: no runt pulses, no double pulses, S never moves under an open gate,
`ce0 & ce1` mutual exclusion by construction + sampled invariant.

## 3. Edge cases

* **Selected source dies** with no new request: mux does NOT act on its own —
  failover is the health manager's job (M3) issuing a new `sel_i`. Documented
  division of responsibility (mandate §14 "measurement before reaction").
* **Dead target at arm time**: switch completes onto dead source; output holds
  last level until that source ticks. Monitor alarm covers the window.
* **force_off_i** (REQ-004): both CEs drop within one ref cycle; FSM parks in
  OFF; release re-arms current selection through the normal quiesce/arm path.
* **Reset**: output quiesced until first legal selection.
* **Rapid retargeting**: requests during busy are folded; final state matches
  the last request observed at IDLE.

## 4. Timing

Switch latency ≤ `TIMEOUT_REF_CYCLES + 6` ref cycles (quiesce timeout dominates);
missing-cycle window on the output documented as such. With dead-selected-source
timeout the worst case is bounded and alarmed upstream.

## 5. Verification mapping (tb_gf_mux)

| Req | Check |
|---|---|
| 001 | structural: production path is seq+BUFGCTRL; generic_ref exists separately |
| 002 | monitors: every high/low ≥7 ns, rise-rise ≥18 ns across phase-random switches |
| 003 | T2 (near-edge random), T3 (selected death), T4 (dead target), T5/T6 |
| 004 | force-off drops CEs in 1 ref cycle; release re-arms |
| 005 | TB gate model = CE-sampled behavioural BUFGCTRL; synthesis uses real primitive |

## 6. Known limitations

Two sources in this stage (N-way via hierarchy planned). Alive inputs must be
clk_ref-domain-valid (monitors synchronize). No automatic failover policy here —
that subsystem lands in M3 (clock health manager).
