# CDC Architecture — M1 Foundation

## 1. Principles

1. **Topology follows semantics.** There is no universal "CDC module". The
   selection guide (`CDC_SELECTION_GUIDE.md`) maps data semantics → topology.
2. **Synchronizer flops only.** Every crossing lands on ASYNC_REG flops with no
   combinational logic between stages (UG949 methodology).
3. **Coherence by protocol or encoding**, never by independent bit
   synchronization of a binary bus: sampling a 32-bit binary bus with 32
   synchronizers can capture bits from different instants, producing a value
   that never existed at the source — silently corrupting control/data.
4. **Reset discipline** per `RESET_ARCHITECTURE.md`; every module defines its
   behaviour under independent domain resets.
5. **Latency and throughput documented per block**; nothing claims losslessness
   it cannot prove.

## 2. Pattern library implemented in M1

| Pattern | Module | Mechanism | Guaranteed properties |
|---|---|---|---|
| Static level | cdc_level_sync | N≥2 ASYNC_REG stage chain | Output ∈ sampled source states; latency bound |
| Pulse/event | cdc_pulse_sync | Toggle FF + edge detect; min-separation guard w/ error flag | No lost pulses when separation rule met; violations flagged |
| Coherent word / req-ack | cdc_handshake | 4-phase handshake, data held stable during req | Exactly-once capture per request; coherence by stability |
| Counter observation | cdc_gray_sync (+ bin2gray/gray2bin) | Gray-encoded bus + multi-stage sync | Sample = some past source value; single-bit-change invariant |

## 3. Attribute strategy

Vendor attribute isolated in one place:

```verilog
`ifdef SYNTHESIS
  `define CLKSYNC_ASYNC_REG (* ASYNC_REG = "TRUE" *)
`else
  `define CLKSYNC_ASYNC_REG
`endif
```

(`rtl/common/clk_sync_attributes.vh`). All synchronizer register declarations
use the macro so simulation tools ignore it and Vivado classifies crossings as
SAFE in report_cdc.

## 4. Verification architecture (M1)

- Each TB generates **independently configured free-running clocks**: period,
  phase offset, and duty randomized from directed lists plus fully random
  values, including the mandated ratio set
  (100→50, 50→100, 100→99, 100→101, 100→33.333, 17→113 MHz equivalents) and
  random pairs.
- Self-checking scoreboards assert end-to-end semantics (no reliance on cycle
  counts).
- SVA concurrent assertions encode local invariants (single-bit gray change,
  handshake stability while req, no X propagation after reset release).
- Metastability is **not** simulated: RTL is written so that a simulator's
  idealized flops demonstrate protocol correctness; immunity evidence comes
  from topology+attributes+report_cdc (mandate §33).
