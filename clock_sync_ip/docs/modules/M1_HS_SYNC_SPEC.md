# M1 Module Specification — cdc_handshake (4-Phase Handshake Synchronizer)

- Requirement set: `docs/requirements/REQUIREMENTS.md` §CDC-HS (CDC-HS-REQ-001..006)
- RTL: `rtl/cdc/handshake/cdc_handshake.sv`
- Testbench: `tb/cdc/tb_cdc_handshake.sv`
- Architecture: `docs/architecture/CDC_ARCHITECTURE.md`, selection guide §"coherent multi-bit"
- Status: IMPLEMENTED / unit-verified (see `VERIFICATION_STATUS.md`)

## 1. Purpose

Coherent multi-bit data transfer between independent clock domains via a
4-phase (full-handshake, return-to-zero) request/acknowledge protocol. The
ONLY sanctioned mechanism in this suite for arbitrary-width data whose bits
must remain correlated (per-bit synchronization of a binary bus is unsafe —
CDC_SELECTION_GUIDE.md).

## 2. Interface

Source domain:

| Port | Dir | Description |
|---|---|---|
| `src_data_i` | in [DATA_WIDTH-1:0] | Sampled on accepted request |
| `src_valid_i` | in | One-cycle request pulse |
| `src_ready_o` | out | 1 = will accept a request this cycle (idle) |
| `src_busy_o` | out | Transfer in progress |
| `src_done_o` | out | One-cycle: full 4-phase sequence completed |
| `timeout_err_o` | out | One-cycle: WAIT_ACK budget exhausted |

Destination domain:

| Port | Dir | Description |
|---|---|---|
| `dst_data_o` | out [DATA_WIDTH-1:0] | Stable while `dst_valid_o` |
| `dst_valid_o` | out | Level: word available |
| `dst_accept_i` | in | One-cycle consume pulse |

Parameters:

| Name | Default | Constraint |
|---|---|---|
| `DATA_WIDTH` | 8 | `>= 1` |
| `SYNC_STAGES` | 2 | `>= 2` (both directions) |
| `TIMEOUT_SRC_CYCLES` | 0 | 0 = disabled |

## 3. Protocol

```text
SRC: valid -> latch data, raise req      DST: sees req rise -> capture data,
                                              raise ack, dst_valid=1
SRC: sees ack -> drop req                DST: consumer accepts AND req==0 ->
SRC: sees !ack -> done, IDLE                  drop ack, dst_valid=0
```

* Data coherence: `data_q` is held from req rise until the destination capture
  edge; capture occurs ONLY on the synchronized req RISE (`req_s && !req_s_prev`)
  so late/duplicated edges cannot corrupt a word (CDC-HS-REQ-002).
* Exactly-once per handshake while both clocks run.
* Backpressure: requests during busy are ignored (`src_ready_o` low).

## 4. Latency / throughput

* Best-case transfer latency ≈ (SYNC_STAGES + 2) src cycles to ack-seen +
  (SYNC_STAGES + 2) dst cycles on the return path; dominated by clock-period
  quantization of the two domains.
* Throughput: one word per full 4-phase round trip. High-rate streaming should
  use an asynchronous FIFO (future M-module) instead.

## 5. Timeout & reset semantics

* Timeout (optional): if ack is not seen within `TIMEOUT_SRC_CYCLES`, source
  pulses `timeout_err_o` and returns to IDLE. DEGRADED state: the word may
  still arrive at the destination afterwards (`dst_valid_o` may assert late);
  recommended recovery is resetting both domains. Disabled when 0.
* Independent resets: both FSMs return to idle deterministically; a transfer
  in flight may be LOST but never half-captured (CDC-HS-REQ-006).

## 6. Verification mapping

| Req | Check |
|---|---|
| CDC-HS-REQ-001 | TB randomized-ratio sweep with data integrity compare |
| CDC-HS-REQ-002 | TB data-coherence monitor across all ratios |
| CDC-HS-REQ-003 | TB backpressure (requests while busy ignored) |
| CDC-HS-REQ-004 | TB timeout case with TIMEOUT_SRC_CYCLES>0 |
| CDC-HS-REQ-005 | TB throughput/latency measurement vs documented bound |
| CDC-HS-REQ-006 | TB independent reset sequences mid-transfer |

## 7. Known limitations

Low throughput (one word per round trip). No built-in FIFO buffering.
