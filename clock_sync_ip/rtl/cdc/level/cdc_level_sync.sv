// ---------------------------------------------------------------------------
// cdc_level_sync — Single-bit level CDC synchronizer
// Spec: docs/modules/M1_LVL_SYNC_SPEC.md   Reqs: CDC-LVL-REQ-001..006
// Layer 1 (portable).
//   * STAGES >= 2 ASYNC_REG resolution stages (no combinational logic between)
//   * optional OUT_REG output stage (timing-friendly, +1 cycle latency)
//   * deterministic reset value on all stages
// Latency: STAGES (+1 if OUT_REG) dst_clk cycles, bounded ±1 by capture phase.
// ---------------------------------------------------------------------------
`default_nettype none
`include "clk_sync_attributes.vh"

module cdc_level_sync #(
  parameter int unsigned STAGES      = 2,     // >= 2
  parameter bit          OUT_REG     = 1'b0,  // extra registered output stage
  parameter bit          RESET_VALUE = 1'b0   // value while in reset / at init
) (
  input  wire logic dst_clk,                  // DESTINATION domain clock
  input  wire logic dst_rst_n,                // destination-domain sync-release reset
  input  wire logic src_async,                // source-domain signal (or async level)
  output logic      dst_data                   // destination-domain representation
);

  `CLKSYNC_PARAM_CHECK(STAGES < 2, "cdc_level_sync: STAGES must be >= 2")

  `CLKSYNC_ASYNC_REG logic [STAGES-1:0] sync_q;

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      sync_q <= {STAGES{RESET_VALUE}};
    end else begin
      sync_q <= {sync_q[STAGES-2:0], src_async};
    end
  end

generate
  if (OUT_REG) begin : g_outreg
    logic out_q;
    always_ff @(posedge dst_clk or negedge dst_rst_n) begin
      if (!dst_rst_n) out_q <= RESET_VALUE;
      else            out_q <= sync_q[STAGES-1];
    end
    assign dst_data = out_q;
  end else begin : g_direct
    assign dst_data = sync_q[STAGES-1];
  end
endgenerate

endmodule : cdc_level_sync

`default_nettype wire
