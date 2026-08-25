// ===========================================================================
// clock_mux_generic_ref — EDUCATIONAL REFERENCE ONLY (AD-004, REQ CLK-MUXREF)
// ===========================================================================
// This combinational mux exists solely to demonstrate WHY LUT-based clock
// selection is unsafe: when sel changes near a source edge, or sources are
// asynchronous, the output can produce runt pulses, double edges, or static
// glitches. It must NEVER drive a clock pin, BUFG input, or clocked logic in
// real hardware. The production implementation is gf_mux_seq +
// gf_mux_bufgctrl_7series (BUFGCTRL class).
//
// Simulation-only usage:
//   * non-clock signal selection,
//   * side-by-side comparison in tb_gf_mux to exhibit glitch behaviour.
// ===========================================================================
`default_nettype none

(* dont_touch = "true", shreg_extract = "no" *)
module clock_mux_generic_ref (
  input  wire logic clk0_i,
  input  wire logic clk1_i,
  input  wire logic sel_i,          // 0 -> clk0, 1 -> clk1
  output logic      clk_o           // GLITCH-PRONE — see header
);

  assign clk_o = sel_i ? clk1_i : clk0_i;

endmodule : clock_mux_generic_ref

`default_nettype wire
