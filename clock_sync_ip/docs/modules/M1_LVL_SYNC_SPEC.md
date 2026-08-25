# M1 Module Specification — cdc_level_sync (Level Synchronizer)

- Requirement set: `docs/requirements/REQUIREMENTS.md` §CDC-LVL (CDC-LVL-REQ-001..006)
- RTL: `rtl/cdc/level/cdc_level_sync.sv`
- Testbench: `tb/cdc/tb_cdc_level_sync.sv`
- Architecture: `docs/architecture/CDC_ARCHITECTURE.md`, selection guide §"static level"
- Status: IMPLEMENTED / unit-verified (see `VERIFICATION_STATUS.md`)

## 1. Purpose

Transfer a single static / slowly-changing asynchronous level into one
destination clock domain with metastability-resolution flops, a deterministic
reset value, and documented latency. NOT suitable for pulses shorter than one
destination cycle — use `cdc_pulse_sync` for events.

## 2. Interface

| Port | Dir | Width | Description |
|---|---|---|---|
| `dst_clk` | in | 1 | Destination-domain clock |
| `dst_rst_n` | in | 1 | Destination-domain sync-release reset |
| `src_async` | in | 1 | Source-domain level (no phase relation to dst_clk) |
| `dst_data` | out | 1 | Synchronized destination representation |

Parameters:

| Name | Default | Constraint | Rationale |
|---|---|---|---|
| `STAGES` | 2 | `>= 2` | CDC-LVL-REQ-002; MTBF scales exponentially with depth |
| `OUT_REG` | 0 | bit | Extra registered output stage for timing closure (+1 latency) |
| `RESET_VALUE` | 0 | bit | Deterministic reset/init value on ALL stages (CDC-LVL-REQ-006) |

## 3. Behaviour

Shift chain of `STAGES` ASYNC_REG flops samples `src_async` every `posedge
dst_clk`; output = last stage (or the optional OUT_REG flop). Because each
stage is a plain flop fed by the previous stage, every observable output value
equals a value that was stable at some earlier sampling edge — intermediate
metastable states cannot propagate beyond stage 1 and are structurally
invisible at the output (CDC-LVL-REQ-004).

## 4. Timing / latency

* Latency: `STAGES` destination cycles ±1 (capture-phase alignment), hard upper
  bound `STAGES + 1` cycles from source change to settled output
  (CDC-LVL-REQ-005); +1 when `OUT_REG = 1`.
* Throughput: continuous level tracking; input must hold each level ≥ 1
  destination cycle to be guaranteed observed.

## 5. Reset behaviour

Async assert (`negedge dst_rst_n`) loads `RESET_VALUE` into all stages;
deassertion is synchronous to `dst_clk`. While in reset the output is exactly
`RESET_VALUE`.

## 6. Verification mapping

| Req | Check |
|---|---|
| CDC-LVL-REQ-001 | TB ratio sweep incl. §32 list + randomized final config |
| CDC-LVL-REQ-002 | elaboration check; STAGES=2/3/4 instantiated in TB |
| CDC-LVL-REQ-003 | structural review; synthesis attribute report |
| CDC-LVL-REQ-004 | TB final-value equality after quiesce across all configs |
| CDC-LVL-REQ-005 | TB latency-bound measurement on STAGES=4+OUT_REG config |
| CDC-LVL-REQ-006 | TB init check of RESET_VALUE=1 instance during reset |

SVA: outputs never X after reset release.

## 7. Known limitations

* No event/pulse guarantee (level semantics only).
* Multi-bit buses MUST NOT use per-bit instances of this module (see
  CDC_SELECTION_GUIDE.md decision tree; use handshake/gray instead).
