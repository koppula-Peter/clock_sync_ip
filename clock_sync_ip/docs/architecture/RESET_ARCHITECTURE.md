# Reset Architecture

## Policy

```
rst_n_async ──▶ [ASYNC_REG flop chain, STAGES ≥ 2] ──▶ rst_n_sync
   assertion: asynchronous (immediate)
   removal:   synchronous to clk, STAGES cycles later
```

Rationale: asynchronous assertion guarantees fastest possible reset of logic;
synchronous removal eliminates recovery/removal timing violations that would
otherwise make reset release non-deterministic across PVT (UG949 reset
methodology).

## Rules for this IP suite

1. **Every clock domain owns its reset synchronizer.** A raw external/board
   reset is never distributed directly to domain logic.
2. **Independent resets are legal.** CDC protocols (pulse sync, handshake,
   gray observation) must define and be tested for one-sided reset:
   - pulse sync: matching init toggle states ⇒ zero spurious events after
     simultaneous reset; one-sided mid-operation reset may cause ≤1 spurious or
     ≤1 missed event, surfaced as error status.
   - handshake: both sides return to idle; an in-flight transfer may be lost,
     never acknowledged-but-corrupt.
3. **No combinational logic between reset-synchronizer stages**; same placement
   discipline (ASYNC_REG) as data synchronizers.
4. **Reset ordering:** deassertion order between domains must not be relied upon
   by any protocol; protocols tolerate arbitrary interleaving.
5. **Polarity parameterization** without changing guarantees (active-low
   default).

## Reset-domain crossing (RDC)

A reset asserted in the destination while source runs can freeze a protocol
mid-sequence. Rules above ensure recovery to idle within a bounded number of
destination cycles once reset releases; testbenches inject one-sided resets
randomly to prove bounded recovery.
