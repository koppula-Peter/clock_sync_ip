// ---------------------------------------------------------------------------
// rst_sync — Reset synchronizer (async assert / sync deassert)
// Spec: docs/modules/M1_RST_SYNC_SPEC.md   Reqs: CDC-RST-REQ-001..006
// Layer 1 (portable). ASYNC_REG via clk_sync_attributes.vh.
// Contract:
//   * rst_n_a asserted (low)  -> rst_n_o low immediately, asynchronously.
//   * rst_n_a released        -> rst_n_o rises STAGES clk edges later,
//                                synchronously to clk.
//   * Power-up/init value = asserted state until first legal release.
// ---------------------------------------------------------------------------
`default_nettype none
`include "clk_sync_attributes.vh"

module rst_sync #(
  parameter int unsigned STAGES = 2            // >= 2 (CDC-RST-REQ-003)
) (
  input  wire logic clk,                       // destination-domain clock
  input  wire logic rst_n_a,                   // asynchronous reset, active-low
  output logic      rst_n_o                    // synchronized release, active-low
);

  `CLKSYNC_PARAM_CHECK(STAGES < 2, "rst_sync: STAGES must be >= 2")

  `CLKSYNC_ASYNC_REG logic [STAGES-1:0] sync_q = '0;  // init = in-reset

  always_ff @(posedge clk or negedge rst_n_a) begin
    if (!rst_n_a) begin
      sync_q <= '0;
    end else begin
      sync_q <= {sync_q[STAGES-2:0], 1'b1};
    end
  end

  assign rst_n_o = sync_q[STAGES-1];

endmodule : rst_sync

`default_nettype wire
