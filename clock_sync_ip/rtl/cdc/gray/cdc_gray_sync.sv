// ---------------------------------------------------------------------------
// cdc_gray_sync — Gray-coded counter observation across clock domains
// Spec: docs/modules/M1_GRAY_SYNC_SPEC.md   Reqs: CDC-GRAY-REQ-001..005
// Layer 1 (portable). Uses clk_sync_cdc_pkg::bin2gray / gray2bin.
//
// The module OWNS the counter so the ±1 discipline required for Gray coding is
// guaranteed by construction (an arbitrary external bus could jump by >1 and
// break single-bit-change legality).
//
// Guarantees:
//   * every dst_count_o sample equals SOME past src_count value (coherent),
//   * samples MAY SKIP values when f_src >> f_dst — never claim losslessness,
//   * wraparound handled naturally by modular arithmetic.
// ---------------------------------------------------------------------------
`default_nettype none
`include "clk_sync_attributes.vh"

module cdc_gray_sync #(
  parameter int unsigned WIDTH       = 8,   // 2..32 (CDC-GRAY-REQ-004)
  parameter int unsigned SYNC_STAGES = 2    // >= 2 resolution stages per bit
) (
  // ---- source domain -------------------------------------------------------
  input  wire logic             src_clk,
  input  wire logic             src_rst_n,
  input  wire logic             src_inc_i,    // count up   (one per cycle ok)
  input  wire logic             src_dec_i,    // count down (inc wins on tie)
  output logic [WIDTH-1:0]      src_count_o,  // binary view, source domain
  // ---- destination domain --------------------------------------------------
  input  wire logic             dst_clk,
  input  wire logic             dst_rst_n,
  output logic [WIDTH-1:0]      dst_count_o,  // sampled binary view (may skip)
  output logic [WIDTH-1:0]      dst_gray_o    // raw synchronized gray sample
);

  `CLKSYNC_PARAM_CHECK((WIDTH < 2) || (WIDTH > 32), "cdc_gray_sync: WIDTH must be 2..32")
  `CLKSYNC_PARAM_CHECK(SYNC_STAGES < 2,             "cdc_gray_sync: SYNC_STAGES must be >= 2")

  // ---------------- source: counter + Gray encoding --------------------------
  logic [WIDTH-1:0] count_q;

  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      count_q <= '0;
    end else if (src_inc_i && !src_dec_i) begin
      count_q <= count_q + {{(WIDTH-1){1'b0}}, 1'b1};
    end else if (src_dec_i && !src_inc_i) begin
      count_q <= count_q - {{(WIDTH-1){1'b0}}, 1'b1};
    end
  end

  assign src_count_o = count_q;

  logic [WIDTH-1:0] gray_next;
  assign gray_next = count_q ^ (count_q >> 1);   // == pkg::bin2gray at WIDTH

  // ---------------- destination: per-bit synchronizers + conversion ----------
  `CLKSYNC_ASYNC_REG logic [WIDTH-1:0] gray_sync_q [SYNC_STAGES];

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      for (int unsigned s = 0; s < SYNC_STAGES; s++) begin
        gray_sync_q[s] <= '0;
      end
    end else begin
      gray_sync_q[0] <= gray_next;
      for (int unsigned s = 1; s < SYNC_STAGES; s++) begin
        gray_sync_q[s] <= gray_sync_q[s-1];
      end
    end
  end

  logic [WIDTH-1:0] gray_sample;
  assign gray_sample = gray_sync_q[SYNC_STAGES-1];

  // gray -> binary, width-exact inline (== pkg::gray2bin at WIDTH)
  logic [WIDTH-1:0] bin_comb;
  always_comb begin
    bin_comb[WIDTH-1] = gray_sample[WIDTH-1];
    for (int i = WIDTH-2; i >= 0; i--) begin
      bin_comb[i] = bin_comb[i+1] ^ gray_sample[i];
    end
  end

  logic [WIDTH-1:0] bin_sample_q;
  logic [WIDTH-1:0] gray_out_q;

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      bin_sample_q <= '0;
      gray_out_q   <= '0;
    end else begin
      bin_sample_q <= bin_comb;
      gray_out_q   <= gray_sample;
    end
  end

  assign dst_count_o = bin_sample_q;
  assign dst_gray_o  = gray_out_q;

endmodule : cdc_gray_sync

`default_nettype wire
