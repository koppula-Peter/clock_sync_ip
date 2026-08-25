// ---------------------------------------------------------------------------
// gf_mux_bufgctrl_7series — Layer-2 AMD 7-Series backend for the glitch-free
// clock mux. Maps gf_mux_seq protocol outputs onto a BUFGCTRL primitive.
// Spec: docs/modules/M2_GFMUX_SPEC.md   Reqs: CLK-GFMUX-REQ-001..004
// Reference: UG472 (7-Series Clocking Resources, BUFGCTRL chapter); AD-004.
//
// Wiring contract (UG472):
//   * CE0/CE1 gate their respective sources; IGNORE* tied LOW so CEs are
//     honoured (asserting IGNORE would force selection regardless of CE —
//     reserved for debug only).
//   * S0/S1 select lines driven by the sequencer; PRESELECT_* unused.
//   * Force-fail-safe: sequencer guarantees ce0&ce1 mutual exclusion, so the
//     BUFGCTRL "both CE" hazard mode is never entered.
// ---------------------------------------------------------------------------
`default_nettype none

module gf_mux_bufgctrl_7series (
  input  wire logic clk0_i,       // source 0 (any domain)
  input  wire logic clk1_i,       // source 1 (any domain)
  input  wire logic ce0_i,        // from gf_mux_seq
  input  wire logic ce1_i,
  input  wire logic s_i,          // 0 -> clk0, 1 -> clk1
  output logic      clk_o         // buffered output clock
);

  BUFGCTRL u_bufgctrl (
    .O          (clk_o),
    .CE0        (ce0_i),
    .CE1        (ce1_i),
    .S0         (!s_i),            // BUFGCTRL: S0 selects I0 when asserted
    .S1         (s_i),
    .I0         (clk0_i),
    .I1         (clk1_i),
    .IGNORE0    (1'b0),
    .IGNORE1    (1'b0),
    .PRESELECT_I0(1'b0),
    .PRESELECT_I1(1'b0)
  );

endmodule : gf_mux_bufgctrl_7series

`default_nettype wire
