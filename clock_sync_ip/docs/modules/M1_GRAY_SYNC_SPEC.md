# M1 Module Specification — cdc_gray_sync (Gray-Code Counter Synchronizer)

- Requirement set: `docs/requirements/REQUIREMENTS.md` §CDC-GRAY (CDC-GRAY-REQ-001..005)
- RTL: `rtl/cdc/gray/cdc_gray_sync.sv`
- Testbench: `tb/cdc/tb_cdc_gray_sync.sv`
- Architecture: `docs/architecture/CDC_ARCHITECTURE.md`, selection guide §"counter observation"
- Status: IMPLEMENTED / unit-verified (see `VERIFICATION_STATUS.md`)

## 1. Purpose

Observe a monotonically ±1-incrementing counter across clock domains coherently
(never a torn/hybrid value) by Gray-coding before the crossing. Primary uses:
pointer transfer for async FIFO infrastructure, counter/timestamp observation.

## 2. Interface

Source domain:

| Port | Dir | Description |
|---|---|---|
| `src_clk`, `src_rst_n` | in | Source clock / reset |
| `src_inc_i` | in | Count up |
| `src_dec_i` | in | Count down (`inc` wins on tie) |
| `src_count_o` | out [WIDTH-1:0] | Binary view, source domain |

Destination domain:

| Port | Dir | Description |
|---|---|---|
| `dst_clk`, `dst_rst_n` | in | Destination clock / reset |
| `dst_count_o` | out [WIDTH-1:0] | Sampled binary view (MAY SKIP values) |
| `dst_gray_o` | out [WIDTH-1:0] | Raw synchronized Gray sample |

Parameters:

| Name | Default | Constraint |
|---|---|---|
| `WIDTH` | 8 | `2..32` |
| `SYNC_STAGES` | 2 | `>= 2` per bit |

## 3. Design decision — module owns the counter

The module instantiates its own counter so the ±1 discipline required for
single-bit-change legality is guaranteed BY CONSTRUCTION. An arbitrary
external bus could jump by >1 and break the Gray property silently; that misuse
is therefore impossible in the sanctioned API.

## 4. Behaviour

* Source: binary counter → `gray = bin ^ (bin >> 1)` registered combinationally
  at the source flop output boundary.
* Crossing: each Gray bit gets an independent `SYNC_STAGES` ASYNC_REG chain.
  Because successive legal values differ in exactly ONE bit, any sampling phase
  yields either the old or the new code — never a mixture.
* Destination: synchronized Gray sample → binary conversion (iterative XOR),
  plus one final register stage for both outputs.

## 5. Guarantees and non-guarantees

* GUARANTEED (CDC-GRAY-REQ-001): every `dst_count_o` equals SOME past
  `src_count_o` value — coherent, monotone-consistent samples.
* NOT GUARANTEED: observing every intermediate value. When
  `f_src >> f_dst` samples skip values (CDC-GRAY-REQ-005 documentation duty).
* Wraparound: modular arithmetic; the Gray single-bit property holds across
  wrap for ±1 sequences of any width (CDC-GRAY-REQ-002).
* Simultaneous inc+dec is resolved deterministically (inc wins) to keep the
  ±1 discipline.

## 6. Verification mapping

| Req | Check |
|---|---|
| CDC-GRAY-REQ-001 | TB randomized-ratio sweep: dst ∈ {past src values}, never torn |
| CDC-GRAY-REQ-002 | TB wraparound stress (up/down around 0 and 2^W-1) |
| CDC-GRAY-REQ-003 | SVA/formal: `$countones(gray ^ $past(gray)) <= 1` on legal increments (mandate §37) |
| CDC-GRAY-REQ-004 | Parameter bounds elaboration checks |
| CDC-GRAY-REQ-005 | Skip behaviour documented + TB demonstrates skips at extreme ratios |

## 7. Known limitations

Counter is internal (no external-bus mode by design). Not a FIFO; no
overflow/underflow flags here — those belong to the future async-FIFO module
built on this primitive.
