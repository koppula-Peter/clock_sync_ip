# Requirements — M1 CDC Foundation

Requirement IDs follow mandate §47. Status: APPROVED for M1 scope.
Each requirement traces: Requirement → Architecture → RTL → Verification →
Result → Evidence (`docs/verification/TRACEABILITY_MATRIX.md`).

## CDC-RST — Reset Synchronizer

| ID | Requirement |
|---|---|
| CDC-RST-REQ-001 | The reset synchronizer shall assert its output reset asynchronously within 0 ns of input assertion (async assert). |
| CDC-RST-REQ-002 | It shall deassert its output synchronously to `clk`, no earlier than STAGES cycles after input deassertion. |
| CDC-RST-REQ-003 | STAGES shall be ≥ 2; values < 2 shall be rejected at elaboration. |
| CDC-RST-REQ-004 | Synchronizer flops shall carry ASYNC_REG=TRUE and contain no combinational logic between stages. |
| CDC-RST-REQ-005 | Polarity shall be parameterizable (active-low / active-high) without changing behaviour guarantees. |
| CDC-RST-REQ-006 | Output shall have a deterministic value through power-up simulation init (matches asserted state until first valid deassertion). |

## CDC-LVL — Level Synchronizer

| ID | Requirement |
|---|---|
| CDC-LVL-REQ-001 | Shall transfer one static/asynchronous level from source domain to destination domain using ≥2 ASYNC_REG stages. |
| CDC-LVL-REQ-002 | STAGES parameter ≥ 2, rejected at elaboration otherwise; default 2. |
| CDC-LVL-REQ-003 | No combinational logic between synchronizer stages; optional final output register stage separate from metastability-resolution stages. |
| CDC-LVL-REQ-004 | Destination value after any change shall equal a sampled source value that was stable for ≥ 1 destination cycle; intermediate illegal states are impossible by construction of the shift chain. |
| CDC-LVL-REQ-005 | Documented latency: STAGES destination cycles (±1 depending on capture alignment), deterministic upper bound STAGES+1. |
| CDC-LVL-REQ-006 | Deterministic reset/init state via RESET_VALUE parameter applied to all stages. |

## CDC-PULSE — Pulse Synchronizer (toggle architecture)

| ID | Requirement |
|---|---|
| CDC-PULSE-REQ-001 | Shall transfer single-cycle events from src to dst domain using toggle-FF + edge detection, robust against pulse loss at any clock ratio. |
| CDC-PULSE-REQ-002 | Events closer than MIN_SEP_SRC_CYCLES (parameter, default 3) source cycles are rejected with an overflow/error flag rather than merged silently. |
| CDC-PULSE-REQ-003 | Maximum guaranteed event rate = 1 per (MIN_SEP × T_src); documented analytically incl. destination-domain constraint. |
| CDC-PULSE-REQ-004 | After independent reset of either side, exactly zero spurious output events occur when both sides start at matching toggle states; mismatched mid-operation reset behaviour documented (may produce one spurious or lose up-to-one event — flagged as error status). |
| CDC-PULSE-REQ-005 | Destination output is a one-dst-cycle pulse per accepted event. |

## CDC-HS — Handshake Synchronizer (4-phase req/ack)

| ID | Requirement |
|---|---|
| CDC-HS-REQ-001 | Shall transfer a coherent DATA_WIDTH payload across domains with request/acknowledge; data stable while req asserted. |
| CDC-HS-REQ-002 | Source busy output prevents overwriting undelivered data; new request while busy is ignored (backpressure). |
| CDC-HS-REQ-003 | Full 4-phase return-to-zero protocol so back-to-back transfers are possible. |
| CDC-HS-REQ-004 | Optional timeout: if ack not seen within TIMEOUT_SRC_CYCLES, error flag asserts and interface releases (documented data-loss semantics). Timeout disabled when parameter = 0. |
| CDC-HS-REQ-005 | Every accepted request produces exactly one destination captured-word event, assuming both clocks run; verified across randomized ratios/phases. |
| CDC-HS-REQ-006 | Independent resets recover deterministically: protocol returns to idle on both sides; a transfer in flight during reset may be lost but never corrupted-and-acknowledged. |

## CDC-GRAY — Gray-Code Synchronizer

| ID | Requirement |
|---|---|
| CDC-GRAY-REQ-001 | Provide bin2gray/gray2bin conversion functions plus an integrated counter-observation channel (src binary counter → gray → multi-stage sync → gray→bin sample in dst). |
| CDC-GRAY-REQ-002 | Successive legal counter values differ in exactly one gray bit (asserted in TB/formal). Wraparound handled naturally by modular arithmetic; property holds across wrap. |
| CDC-GRAY-REQ-003 | Destination sample always equals some past source counter value (never an illegal mixture); may skip values when f_src/f_dst high — documented, not claimed lossless. |
| CDC-GRAY-REQ-004 | WIDTH parameter 2..32 (matching XPM_CDC_GRAY supported range for cross-checking); invalid widths rejected. |
| CDC-GRAY-REQ-005 | Optional increment/decrement direction support (for FIFO pointers). |

## Common

| ID | Requirement |
|---|---|
| CDC-CMN-REQ-001 | All M1 modules: `default_nettype none`, explicit widths, no latches, no delays, synthesizable subset only. |
| CDC-CMN-REQ-002 | Parameter validation via elaboration-time checks ($fatal in SV / guarded generate). |
| CDC-CMN-REQ-003 | Each module has self-checking SV testbench incl. randomized independent clocks (mandate §32 list) and SVA assertions. |
| CDC-CMN-REQ-004 | Each module synthesizes clean OOC in Vivado 2025.2; report_cdc shows SAFE classification for every crossing; methodology/CDC criticals = 0 unexplained. |

## CLK-DIV — Clock Divider (M2)

| ID | Requirement |
|---|---|
| CLK-DIV-REQ-001 | Shall divide an input reference by any integer in [DIVIDE_MIN..DIVIDE_MAX], producing one-clk-cycle enable ticks at 1/DIVIDE rate (Mode A, preferred per AD-003). |
| CLK-DIV-REQ-002 | Divide-by-1 shall bypass counting and assert the tick every cycle. |
| CLK-DIV-REQ-003 | Runtime divide changes shall take effect only at a deterministic boundary (terminal count) when GLITCH_FREE_UPDATE=1; no tick interval shorter than one clk cycle or longer than 2×DIVIDE cycles during transition. |
| CLK-DIV-REQ-004 | Synchronous clear/restart shall reload the counter deterministically on the next clk edge. |
| CLK-DIV-REQ-005 | Active divide value shall be readable (status) and pending-update state visible. |
| CLK-DIV-REQ-006 | Values outside [DIVIDE_MIN..DIVIDE_MAX] shall be rejected at elaboration; live writes outside range while in reset-free operation shall be ignored with sticky config_err flag. |
| CLK-DIV-REQ-007 | The module shall NOT emit a fabric clock signal; actual clock-output mode is delegated to the Layer-2 backend (BUFGCE_DIV class), which consumes the enable/tick interface. |

## CLK-GFMUX — Glitch-Free Clock Mux (M2)

| ID | Requirement |
|---|---|
| CLK-GFMUX-REQ-001 | Production source selection shall use BUFGCTRL-class primitives (Layer-2); no combinational clock muxing (AD-004). |
| CLK-GFMUX-REQ-002 | Switch sequencing shall guarantee: no runt pulses, no double pulses, no output glitches, with documented maximum switch latency in cycles of the OUTPUT clock domain. |
| CLK-GFMUX-REQ-003 | Behaviour defined and tested for: select change near either clock edge, stopped currently-selected source, stopped incoming source, rapid select toggling, reset during switch. |
| CLK-GFMUX-REQ-004 | A safety override shall force the output off (both enables low) on health-manager request; software cannot re-enable without explicit release. |
| CLK-GFMUX-REQ-005 | Layer-1 sequencer shall be portable/testable with behavioural clock models; Layer-2 wrapper maps CE0/CE1/S0/S1 onto BUFGCTRL with force-fail-safe wiring. |

## CLK-MUXREF — Generic Mux Reference Model

| ID | Requirement |
|---|---|
| CLK-MUXREF-REQ-001 | A combinational `assign` mux exists solely as simulation/education reference (`clock_mux_generic_ref`), marked non-synthesizable-for-clocks; any synthesis attempt in a clock path must trigger a methodology error via attribute/comment contract. |
