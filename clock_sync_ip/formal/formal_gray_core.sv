// ---------------------------------------------------------------------------
// formal_gray_core — exhaustive formal proof of the Gray encoding core
// Mandate §37: $countones(gray ^ $past(gray)) <= 1 for legal ±1 increments.
// WIDTH=8 => complete 256-state space covered by induction/bmc(256+).
// Also proves gray2bin ∘ bin2gray = identity (decode correctness).
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
module formal_gray_core;

  localparam int W = 8;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg [W-1:0] cnt   = 8'd0;
  reg         inc_i = 1'b0;
  reg         dec_i = 1'b0;

  wire [W-1:0] g_now  = clk_sync_cdc_pkg::bin2gray(32'(cnt));
  wire [W-1:0] b_rt   = clk_sync_cdc_pkg::gray2bin(g_now);   // round trip

  integer cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;

    // ---- decode identity: holds for EVERY reachable state ------------------
    ident: assert (b_rt == cnt);

    if (cyc > 0) begin : step_check
      wire [W-1:0] d  = cnt - $past(cnt);
      wire         legal_step = (d == {{(W-1){1'b0}},1'b1}) || (&d) || (d == '0);
      wire [W-1:0] gd = g_now ^ clk_sync_cdc_pkg::bin2gray(32'($past(cnt)));
      // ---- single-bit change on every legal ±1/hold step (mandate §37) -----
      always if (legal_step) ones: assert ($countones(gd) <= 1);
    end

    // stimulus freedom: any combination each cycle
    inc_i <= $anyseq;
    dec_i <= $anyseq;
    if (!$past(inc_i) && !$past(dec_i)) ;
    if ($past(inc_i) && !$past(dec_i))       cnt <= cnt + 8'd1;
    else if ($past(dec_i) && !$past(inc_i))  cnt <= cnt - 8'd1;
  end

endmodule
