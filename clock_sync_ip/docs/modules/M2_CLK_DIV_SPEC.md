# M2 Module Specification — clk_divider (Programmable Clock Divider)

- Requirements: `docs/requirements/REQUIREMENTS.md` §CLK-DIV (CLK-DIV-REQ-001..007)
- RTL: `rtl/clock_divider/clk_divider.sv`
- Testbench: `tb/clock_divider/tb_clk_divider.sv`
- Architecture: AD-003 (enable ticks over fabric clocks), mandate §8
- Status: IMPLEMENTED / lint-clean / unit sim queued

## 1. Purpose

Produce programmable integer clock division as **one-cycle enable ticks**
inside an existing domain (Mode A, the sanctioned architecture). The module
deliberately has NO clock output port: real divided clocks are the Layer-2
backend's job (BUFGCE_DIV class consuming this interface), preventing LUT
clock generation by construction (mandate §56).

## 2. Interface

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` / `rst_n` | in | 1 | Domain clock; async-assert/sync-release reset |
| `div_value_i` | in | 32 | Requested ratio |
| `div_load_i` | in | 1 | One-cycle load pulse |
| `restart_i` | in | 1 | One-cycle restart pulse |
| `config_err_o` | out | 1 | Sticky: rejected out-of-range write |
| `update_pending_o` | out | 1 | Shadow loaded, not yet committed |
| `active_div_o` | out | clog2(MAX) | Applied ratio (readback) |
| `clk_en_tick_o` | out | 1 | One-clk-cycle tick every DIVIDE cycles |
| `div_ce_wave_o` | out | 1 | Enable waveform high DIVIDE/2 cycles per period |

Parameters: `DIVIDE_MIN` (≥1), `DIVIDE_MAX` (≥MIN), `DEFAULT_DIVIDE`
(in range) — all elaboration-checked.

## 3. Behaviour

* **Tick:** counter wraps at `DIVIDE-1`; terminal count asserts
  `clk_en_tick_o`. Divide-by-1 bypass asserts tick every cycle (REQ-002).
* **Glitch-free runtime update (REQ-003):** `div_load_i` captures into a
  shadow register (`update_pending_o` set); commit to the active register
  happens ONLY at terminal count, so every observed interval is ≥1 and ≤max(old,new)
  cycles — no short/long periods during transitions.
* **Waveform:** `div_ce_wave_o` is high while `count < DIVIDE/2` (registered):
  exact 50% for even ratios, floor(DIVIDE/2) for odd (tick remains reference).
  Constant 0 at bypass.
* **Error handling (REQ-006):** out-of-range live writes ignored +
  sticky `config_err_o`; cleared by restart or valid load.

## 4. Timing

Latency of a load→commit ≤ one old-period; status outputs registered.
Throughput N/A (configuration interface).

## 5. Verification mapping

| Req | TB check |
|---|---|
| 001 | T1/T3/T6 measured tick period = DIVIDE for 4/64/16 |
| 002 | T2 ten consecutive cycles ticked at ratio 1 |
| 003 | T5 gap monitor across live 16→5 change: gaps ∈ [1..16] |
| 004 | T6 restart → period resumes exactly |
| 005 | T3/T7 readback + pending flag timing |
| 006 | T7 rejection, stickiness, clear-by-valid-load |
| 007 | Structural: no clock output port exists |

Sampled invariants: no back-to-back ticks when div>1; active_div always legal.

## 6. Known limitations

Odd-ratio waveform duty is floor(DIVIDE/2) by design. MAX ratio bounded by
counter width (clog2(DIVIDE_MAX)); fractional division out of scope (MMCM/DRP
backend covers it later).
