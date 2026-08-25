// ---------------------------------------------------------------------------
// cdc_handshake — Coherent multi-bit transfer, 4-phase request/acknowledge
// Spec: docs/modules/M1_HS_SYNC_SPEC.md   Reqs: CDC-HS-REQ-001..006
// Layer 1 (portable).
//
// Protocol (4-phase, return-to-zero):
//   SRC: valid pulse latches data, raises req  -> DST samples data, raises ack
//   SRC: sees ack, drops req                   -> DST sees !req, drops ack
//   SRC: sees !ack -> IDLE (ready for next)
//
// Guarantees:
//   * data coherent: held in a register from req rise until transfer complete
//   * exactly-once capture per completed handshake (both clocks running)
//   * backpressure: requests ignored while busy (src_ready_o = idle)
//   * independent resets: both sides return to IDLE; a transfer in flight may
//     be LOST but is never acknowledged-corrupt (CDC-HS-REQ-006)
//
// Timeout (optional, TIMEOUT_SRC_CYCLES > 0): if WAIT_ACK does not complete
// within the budget, timeout_err_o pulses once and the source FSM releases to
// IDLE. SEMANTICS AFTER TIMEOUT ARE DEGRADED: the word may still appear late on
// the destination side (dst_valid_o). Recommended recovery is resetting both
// domains. Timeout disabled when 0.
// ---------------------------------------------------------------------------
`default_nettype none
`include "clk_sync_attributes.vh"

module cdc_handshake #(
  parameter int unsigned DATA_WIDTH         = 8,
  parameter int unsigned SYNC_STAGES        = 2,   // >= 2, both directions
  parameter int unsigned TIMEOUT_SRC_CYCLES = 0    // 0 = disabled
) (
  // ---- source domain -------------------------------------------------------
  input  wire logic                   src_clk,
  input  wire logic                   src_rst_n,
  input  wire logic [DATA_WIDTH-1:0]  src_data_i,   // sampled on accepted request
  input  wire logic                   src_valid_i,  // one-cycle request pulse
  output logic                        src_ready_o,  // 1 = will accept request this cycle
  output logic                        src_busy_o,   // transfer in progress
  output logic                        src_done_o,   // one-cycle: transfer fully complete
  output logic                        timeout_err_o,// one-cycle: sequence timed out
  // ---- destination domain --------------------------------------------------
  input  wire logic                   dst_clk,
  input  wire logic                   dst_rst_n,
  output logic [DATA_WIDTH-1:0]       dst_data_o,   // stable while dst_valid_o
  output logic                        dst_valid_o,  // level: word available
  input  wire logic                   dst_accept_i  // one-cycle pulse consumes word
);

  `CLKSYNC_PARAM_CHECK(SYNC_STAGES < 2, "cdc_handshake: SYNC_STAGES must be >= 2")
  `CLKSYNC_PARAM_CHECK(DATA_WIDTH < 1,  "cdc_handshake: DATA_WIDTH must be >= 1")

  localparam logic [1:0] FS_IDLE    = 2'd0;
  localparam logic [1:0] FS_WAIT_ACK = 2'd1;
  localparam logic [1:0] FS_CLEAR   = 2'd2;

  // ================= source domain ==========================================
  logic [1:0]             fsm_q;
  logic [DATA_WIDTH-1:0]  data_q;
  logic                   req_q;
  logic                   done_q;
  logic                   timeout_q;
  logic [31:0]            tmo_cnt_q;

  logic                   ack_q;          // destination acknowledge (raw, async to src)

  // acknowledge synchronized into the source domain
  `CLKSYNC_ASYNC_REG logic [SYNC_STAGES-1:0] ack_sync_q;
  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      ack_sync_q <= '0;
    end else begin
      ack_sync_q <= {ack_sync_q[SYNC_STAGES-2:0], ack_q};
    end
  end
  logic ack_s;
  assign ack_s = ack_sync_q[SYNC_STAGES-1];

  assign src_ready_o   = (fsm_q == FS_IDLE);
  assign src_busy_o    = ~src_ready_o;
  assign src_done_o    = done_q;
  assign timeout_err_o = timeout_q;

  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      fsm_q     <= FS_IDLE;
      data_q    <= '0;
      req_q     <= 1'b0;
      done_q    <= 1'b0;
      timeout_q <= 1'b0;
      tmo_cnt_q <= '0;
    end else begin
      done_q    <= 1'b0;
      timeout_q <= 1'b0;

      unique case (fsm_q)
        FS_IDLE: begin
          tmo_cnt_q <= '0;
          if (src_valid_i) begin
            data_q <= src_data_i;
            req_q  <= 1'b1;
            fsm_q  <= FS_WAIT_ACK;
          end
        end

        FS_WAIT_ACK: begin
          if (ack_s) begin
            req_q     <= 1'b0;
            fsm_q     <= FS_CLEAR;
            tmo_cnt_q <= '0;
          end else if ((TIMEOUT_SRC_CYCLES != 0) &&
                       (tmo_cnt_q >= TIMEOUT_SRC_CYCLES[31:0])) begin
            timeout_q <= 1'b1;
            req_q     <= 1'b0;           // release interface (degraded; see header)
            fsm_q     <= FS_IDLE;
            tmo_cnt_q <= '0;
          end else begin
            tmo_cnt_q <= tmo_cnt_q + 32'd1;
          end
        end

        FS_CLEAR: begin
          if (!ack_s) begin
            done_q <= 1'b1;
            fsm_q  <= FS_IDLE;
          end
        end

        default: fsm_q <= FS_IDLE;
      endcase
    end
  end

  // ================= destination domain =====================================
  logic [DATA_WIDTH-1:0]  dst_data_q;
  logic                   dst_valid_q;

  // request synchronized into the destination domain
  `CLKSYNC_ASYNC_REG logic [SYNC_STAGES-1:0] req_sync_q;
  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      req_sync_q <= '0;
    end else begin
      req_sync_q <= {req_sync_q[SYNC_STAGES-2:0], req_q};
    end
  end
  logic req_s;
  logic req_s_prev;
  assign req_s      = req_sync_q[SYNC_STAGES-1];
  assign req_s_prev = (SYNC_STAGES > 1) ? req_sync_q[SYNC_STAGES-2] : 1'b1;

  // acknowledge returned to the source domain
  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      dst_data_q  <= '0;
      dst_valid_q <= 1'b0;
      ack_q       <= 1'b0;
    end else begin
      if (req_s && !req_s_prev && !dst_valid_q) begin
        dst_data_q  <= data_q;           // coherent capture on req RISE only
        dst_valid_q <= 1'b1;
        ack_q       <= 1'b1;
      end else if (dst_valid_q && dst_accept_i && !req_s) begin
        dst_valid_q <= 1'b0;             // consume only after src dropped req
        ack_q       <= 1'b0;
      end
    end
  end

  assign dst_data_o  = dst_data_q;
  assign dst_valid_o = dst_valid_q;

endmodule : cdc_handshake

`default_nettype wire
