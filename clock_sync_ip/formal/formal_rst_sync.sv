// ---------------------------------------------------------------------------
// formal_rst_sync — rst_sync safety properties (CDC-RST-REQ-001/002/006)
// STAGES=2 default config. rst_n_a is FREE stimulus (* anyseq *): every
// property below must hold for ALL possible reset waveforms.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module formal_rst_sync;

  localparam int STAGES = 2;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  (* anyseq *) reg rst_n_a;
  wire         rst_n_o;

  rst_sync #(.STAGES(STAGES)) dut (.clk(clk), .rst_n_a(rst_n_a), .rst_n_o(rst_n_o));

  // history of raw reset samples
  reg [STAGES-1:0] hist_q = '0;
  wire             release_stable = &{hist_q[STAGES-2:0], rst_n_a};

  integer cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    hist_q <= {hist_q[STAGES-2:0], rst_n_a};

    // REQ-001/006: while raw reset is asserted the output IS asserted
    a_low_when_reset: assert (!rst_n_a || rst_n_o == 1'b0 || hist_q[0]);

    // REQ-002 upper bound: after STAGES consecutive released cycles the output
    // MUST be released (shift chain full of ones).
    if (&{hist_q[STAGES-2:0], rst_n_a})
      a_released_in_time: assert (rst_n_o == 1'b1);

    // REQ-002 lower bound / no early release: output high implies the raw
    // reset has been continuously released for >= STAGES samples.
    if (rst_n_o && cyc > STAGES)
      a_not_early: assert (release_stable);
  end

endmodule
