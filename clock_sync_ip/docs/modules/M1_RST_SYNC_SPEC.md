# M1 Module Specification — rst_sync (Reset Synchronizer)

- Requirement set: `docs/requirements/REQUIREMENTS.md` §CDC-RST (CDC-RST-REQ-001..006)
- RTL: `rtl/cdc/reset/rst_sync.sv`
- Testbench: `tb/cdc/tb_rst_sync.sv`
- Architecture: `docs/architecture/RESET_ARCHITECTURE.md`, `docs/architecture/CDC_ARCHITECTURE.md`
- Status: IMPLEMENTED / unit-verified (see `VERIFICATION_STATUS.md`)

## 1. Purpose

Produce a destination-domain reset (`rst_n_o`) that asserts asynchronously with
the raw asynchronous reset input and releases synchronously to `clk`, so that
every flop in the domain exits reset within one clock edge of each other
(recovery/removal-safe release; AD-006).

## 2. Interface

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Destination-domain clock |
| `rst_n_a` | in | 1 | Asynchronous reset, active-low (assert-dominant) |
| `rst_n_o` | out | 1 | Synchronized release, active-low |

Parameters:

| Name | Default | Constraint | Rationale |
|---|---|---|---|
| `STAGES` | 2 | `>= 2` (elaboration `$fatal`) | CDC-RST-REQ-003; depth sets MTBF + release latency |

## 3. Behaviour

* **Assertion (async):** `rst_n_a` low ⇒ `rst_n_o` low immediately, independent
  of `clk` (CDC-RST-REQ-001).
* **Release (sync):** after `rst_n_a` rises, a `STAGES`-deep shift chain fills
  with `1'b1`; `rst_n_o` rises on the `STAGES`-th `posedge clk`
  (CDC-RST-REQ-002).
* **Init:** shift chain initializes to all-zero (= asserted). Simulation power-up
  state matches hardware GSR behaviour for the asserted-active-low convention
  (CDC-RST-REQ-006).
* **Structure:** flops only between stages — no combinational logic
  (CDC-RST-REQ-004); ASYNC_REG applied via the single sanctioned touchpoint
  `clk_sync_attributes.vh` (AD-002).

## 4. Timing / latency

* Release latency: exactly `STAGES` cycles of `clk`, measured from the first
  posedge sampling `rst_n_a == 1`.
* No throughput concept; combinational output from final stage.

## 5. Reset assumptions

`rst_n_a` must itself be a valid asynchronous reset source (e.g. POR, external
RC, supervisor). This module never *creates* an async reset; it only
synchronizes its RELEASE.

## 6. Verification mapping

| Req | Check |
|---|---|
| CDC-RST-REQ-001 | TB: async assertion at random phase (no clk edge required) |
| CDC-RST-REQ-002 | TB: release delay == STAGES cycles across randomized clocks/seeds |
| CDC-RST-REQ-003 | Elaboration check + negative compile case documented in module report |
| CDC-RST-REQ-004 | Structural review + synthesis attribute report |
| CDC-RST-REQ-005 | Polarity fixed active-low by design decision (AD-006); wrappers may invert |
| CDC-RST-REQ-006 | TB: init value checked before first release |

## 7. Known limitations

Single-clock destination only. Multi-domain release ordering is achieved by
instantiating one `rst_sync` per destination domain (RESET_ARCHITECTURE.md §3).
