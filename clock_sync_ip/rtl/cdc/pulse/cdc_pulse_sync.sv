// ---------------------------------------------------------------------------
// cdc_pulse_sync — Event transfer across clock domains (toggle architecture)
// Spec: docs/modules/M1_PULSE_SYNC_SPEC.md   Reqs: CDC-PULSE-REQ-001..005
// Layer 1 (portable).
//
// Mechanism: source pulse toggles a state FF; destination synchronizes the
// state bit (>= 2 ASYNC_REG stages) and regenerates a one-cycle pulse on every
// observed change. A pulse can never be "lost" by being too short, because the
// information is carried as state, not width.
//
// Rate contract (documented, enforced source-side):
//   Events must be separated by >= MAX(MIN_SEP_SRC_CYCLES,
//   ceil(3 * f_src / f_dst)) SOURCE cycles so the destination observes each
//   toggle transition separately (2 sync stages + edge FF => ~3 dst edges).
//   Violations of the source-local limit are flagged on undersep_err_o and
//   NOT transferred. When f_dst < f_src the user MUST raise
//   MIN_SEP_SRC_CYCLES accordingly; this module cannot observe f_dst.
//
// Reset behaviour: both sides initialize aligned (toggle=0 / prev=0) => zero
// spurious events. A ONE-SIDED reset during operation leaves the two sides
// misaligned until the next transfer: exactly <= 1 spurious or <= 1 missed
// event, then permanently re-aligned (bounded, self-healing; no sticky error).
// ---------------------------------------------------------------------------
`default_nettype none
`include "clk_sync_attributes.vh"

module cdc_pulse_sync #(
  parameter int unsigned SYNC_STAGES       = 2,  // >= 2 resolution stages
  parameter int unsigned MIN_SEP_SRC_CYCLES = 3 // min src cycles between events
) (
  // ---- source domain -------------------------------------------------------
  input  wire logic src_clk,
  input  wire logic src_rst_n,
  input  wire logic src_pulse_i,        // one-src-cycle event request
  output logic      src_busy_o,         // 1 = an event now would be rejected
  output logic      undersep_err_o,     // one-cycle flag: event was rejected
  // ---- destination domain --------------------------------------------------
  input  wire logic dst_clk,
  input  wire logic dst_rst_n,
  output logic      dst_pulse_o          // one-dst-cycle event pulse
);

  `CLKSYNC_PARAM_CHECK(SYNC_STAGES < 2,        "cdc_pulse_sync: SYNC_STAGES must be >= 2")
  `CLKSYNC_PARAM_CHECK(MIN_SEP_SRC_CYCLES < 1, "cdc_pulse_sync: MIN_SEP_SRC_CYCLES must be >= 1")

  // ---------------- source side ---------------------------------------------
  logic toggle_q;
  logic [31:0] sep_cnt_q;
  logic accept;

  assign accept = (sep_cnt_q >= MIN_SEP_SRC_CYCLES[31:0]);
  assign src_busy_o    = ~accept;
  assign undersep_err_o = src_pulse_i & ~accept;

  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      toggle_q  <= 1'b0;
      sep_cnt_q <= '1;                    // allow immediately after reset
    end else begin
      sep_cnt_q <= accept ? 32'd1 : (sep_cnt_q < '1 ? sep_cnt_q + 32'd1 : sep_cnt_q);
      if (src_pulse_i && accept) begin
        toggle_q <= ~toggle_q;
      end
    end
  end

  // ---------------- destination side ----------------------------------------
  `CLKSYNC_ASYNC_REG logic [SYNC_STAGES-1:0] sync_q;
  logic prev_q;
  logic pulse_q;

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      sync_q <= '0;
    end else begin
      sync_q <= {sync_q[SYNC_STAGES-2:0], toggle_q};
    end
  end

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      prev_q  <= 1'b0;
      pulse_q <= 1'b0;
    end else begin
      prev_q  <= sync_q[SYNC_STAGES-1];
      pulse_q <= (sync_q[SYNC_STAGES-1] != prev_q);
    end
  end

  assign dst_pulse_o = pulse_q;

`ifdef CLKSYNC_SIM_ASSERT
  // Local invariant checks (simulation only)
  always_ff @(posedge src_clk) begin
    if (!src_rst_n === 1'b1 && $past(src_rst_n) === 1'b1 && src_pulse_i) begin
      assert (!$past(undersep_err_o))
        else $error("cdc_pulse_sync: inconsistent accept/err state");
    end
  end
`endif

endmodule : cdc_pulse_sync

`default_nettype wire
