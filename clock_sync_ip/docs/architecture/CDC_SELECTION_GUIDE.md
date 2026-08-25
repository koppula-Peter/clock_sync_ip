# CDC Selection Guide (decision tree)

Choose the crossing topology from **data semantics**, not convenience.

```
What crosses?
│
├─ Single bit, level (config bit, status flag, slow state)
│    → cdc_level_sync  [2+ ASYNC_REG stages]
│      Latency: STAGES dst cycles. No throughput constraint.
│
├─ Single bit, PULSE/event (irq request, tick, trigger)
│    ├─ Event separation ≥ 3 src cycles guaranteed?
│    │    → cdc_pulse_sync (toggle)   [flag on violation]
│    └─ Every event must be delivered regardless of spacing?
│         → cdc_handshake with DATA_WIDTH=1 (req/ack paces source)
│
├─ Multi-bit CONTROL word, changed rarely (divider ratio, thresholds)
│    → cdc_handshake (coherent capture), or
│      quasi-static + gray-safe update discipline ONLY if provably stable
│      for ≥ 3 dst cycles around each change (document per use!)
│
├─ Multi-bit DATA word, event-driven (sample, command)
│    → cdc_handshake (4-phase req/ack; data stable while req)
│
├─ Monotonic counter / FIFO pointer observation
│    → cdc_gray_sync (bin→gray→sync→gray→bin)
│      Sample = some past value; values may be SKIPPED at dst.
│      Never claim lossless observation. Never feed non-±1 buses!
│
├─ High-throughput stream (>1 word per ~10 cycles)
│    → asynchronous FIFO (M-later; xpm_fifo_async or custom w/ gray ptrs)
│
└─ RESET crossing
     → rst_sync in EVERY destination domain (async assert / sync release)
       One-sided resets must be survivable: see RESET_ARCHITECTURE.md
```

## Why not synchronize a binary bus bit-by-bit?

Sampling `bus[31:0]` with 32 independent 2-FF synchronizers lets bits resolve at
different destination edges (skew between crossings is unconstrained). The
destination can latch e.g. `0x000007FF→0x00000800` transition as `0x00000FFF`
or `0x00000000`. For control words such phantom values select illegal modes.
Coherence requires either protocol stability (handshake) or an encoding whose
any-time sample is legal (Gray for ±1 sequences).

## Anti-patterns (rejected by review)

| Anti-pattern | Why rejected |
|---|---|
| 32 parallel level syncs on a binary bus | Non-coherent sampling (above) |
| Pulse through plain 2-FF sync | Pulse may vanish entirely if shorter than dst cycle + resolution window |
| Stretching pulse "long enough" without proof | Works only under assumed min f_dst; breaks silently when clocking changes |
| False-pathing an unsafe path to silence report_cdc | Hides the problem, does not fix it |
| Multi-bit handshake where data changes while req high | Violates the stability contract; corruption |
