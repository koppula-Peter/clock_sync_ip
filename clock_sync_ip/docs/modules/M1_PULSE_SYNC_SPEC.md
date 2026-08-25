# M1 Module Specification — cdc_pulse_sync (Pulse / Event Synchronizer)

- Requirement set: `docs/requirements/REQUIREMENTS.md` §CDC-PULSE (CDC-PULSE-REQ-001..005)
- RTL: `rtl/cdc/pulse/cdc_pulse_sync.sv`
- Testbench: `tb/cdc/tb_cdc_pulse_sync.sv`
- Architecture: `docs/architecture/CDC_ARCHITECTURE.md`, selection guide §"pulse/event"
- Status: IMPLEMENTED / unit-verified (see `VERIFICATION_STATUS.md`)

## 1. Purpose

Transfer single-cycle events from a source clock domain to a destination clock
domain with NO pulse-width dependence, using the toggle-flip-flop architecture.
A 2-FF level synchronizer alone can swallow short pulses; here the event is
carried as STATE (a toggling bit), so width is irrelevant.

## 2. Interface

Source domain:

| Port | Dir | Description |
|---|---|---|
| `src_clk` | in | Source clock |
| `src_rst_n` | in | Source reset (async assert / sync release) |
| `src_pulse_i` | in | One-src-cycle event request |
| `src_busy_o` | out | 1 = an event this cycle would be rejected |
| `undersep_err_o` | out | One-cycle flag: event was REJECTED (too close to previous) |

Destination domain:

| Port | Dir | Description |
|---|---|---|
| `dst_clk` | in | Destination clock |
| `dst_rst_n` | in | Destination reset |
| `dst_pulse_o` | out | One-dst-cycle event pulse per accepted event |

Parameters:

| Name | Default | Constraint |
|---|---|---|
| `SYNC_STAGES` | 2 | `>= 2` |
| `MIN_SEP_SRC_CYCLES` | 3 | `>= 1` |

## 3. Behaviour

* Source: accepted pulse toggles `toggle_q`. A separation counter enforces the
  minimum spacing; violations raise `undersep_err_o` and are NOT transferred
  (CDC-PULSE-REQ-002) — silent merging is impossible.
* Destination: `toggle_q` is synchronized (`SYNC_STAGES` ASYNC_REG flops); an
  edge detector regenerates exactly one destination-cycle pulse per observed
  transition (CDC-PULSE-REQ-005).

## 4. Rate contract (documented analytically — CDC-PULSE-REQ-003)

The destination needs ~3 dst edges (2 sync stages + edge FF) per event.
Required source separation:

```text
MIN_SEP_REQUIRED = max(MIN_SEP_SRC_CYCLES, ceil(3 * f_src / f_dst))  [src cycles]
```

When `f_dst < f_src` the integrator MUST raise `MIN_SEP_SRC_CYCLES`
accordingly; the module cannot observe `f_dst`. Maximum guaranteed event rate =
1 per required-separation interval.

## 5. Reset behaviour (CDC-PULSE-REQ-004)

* Both sides reset together: toggle=0 / prev-chain=0 ⇒ zero spurious events.
* ONE-SIDED mid-operation reset: sides start misaligned ⇒ at most one spurious
  or one missed event, then permanent re-alignment (bounded, self-healing).
  This is documented behaviour, not an error condition.

## 6. Verification mapping

| Req | Check |
|---|---|
| CDC-PULSE-REQ-001 | TB randomized async-clock sweep, every request yields ≥1 dst pulse |
| CDC-PULSE-REQ-002 | TB back-to-back event rejection + err flag |
| CDC-PULSE-REQ-003 | Analytical bound in header; TB max-rate stress case |
| CDC-PULSE-REQ-004 | TB independent-reset sequences (both / src-only / dst-only) |
| CDC-PULSE-REQ-005 | TB one-cycle output width check |

## 7. Known limitations

Events closer than the enforced separation are DROPPED (with flag), not
queued. For guaranteed delivery of every event use `cdc_handshake`.
