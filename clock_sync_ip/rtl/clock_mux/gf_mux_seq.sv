// ---------------------------------------------------------------------------
// gf_mux_seq — Layer-1 glitch-free clock-mux switch sequencer
// Spec: docs/modules/M2_GFMUX_SPEC.md   Reqs: CLK-GFMUX-REQ-001..005
// Layer 1 (portable): owns ONLY the switching PROTOCOL. Clock gating itself
// happens in Layer-2 (BUFGCTRL CEs). Runs in a reference/safety domain that
// is alive whenever the mux output is required (typically PS 33MHz / board
// osc via monitor). See header table for guarantees and limits.
//
// Protocol (per transition old->new):
//   IDLE        : sel_i != active_sel -> begin switch (busy_o rises)
//   KILL_OLD    : deassert old source CE
//   QUIESCE     : wait until old source stops toggling into the gate
//                 (src<old>_alive fall) OR timeout; then settle 2 ref cycles
//   ARM_NEW     : drive S to new source, hold 2 ref cycles
//   GATE_NEW    : assert new CE -> DONE pulse -> IDLE
//
// Safety:
//   * ce0 & ce1 are NEVER high together (checked by construction + SVA).
//   * force_off_i asynchronously dominates: both CEs drop within one ref
//     cycle; FSM parks in OFF until released by a fresh sel_i write while
//     force_off_i == 0 (REQ-004).
//   * Stopped NEW source at ARM time: CE asserted anyway — output stays at
//     its last level until that source ticks (documented; monitor alarms).
//   * Reset state: both CEs low (output quiesced) until first legal switch.
//   * src*_alive MUST be valid in the clk_ref domain (monitor outputs are
//     synchronized by their provider — M3 clock monitors).
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none
`include "clk_sync_attributes.vh"

module gf_mux_seq #(
  parameter int unsigned TIMEOUT_REF_CYCLES = 64, // quiesce budget @ref_clk
  parameter int unsigned SETTLE_REF_CYCLES  = 2   // arm/settle guard
) (
  input  wire logic clk_ref,      // safety/reference domain clock
  input  wire logic rst_n,        // sync-release reset in ref domain
  // request interface
  input  wire logic sel_i,        // 0=source0, 1=source1 (level request)
  input  wire logic force_off_i,  // safety override, level (REQ-004)
  // source liveness (from clock monitors; level per source)
  input  wire logic src0_alive,
  input  wire logic src1_alive,
  // status
  output logic      busy_o,
  output logic      sw_done_o,    // one-ref-cycle pulse on completed switch
  output logic      off_o,        // safety override engaged
  // gate control to Layer-2 backend (BUFGCTRL)
  output logic      ce0_o,
  output logic      ce1_o,
  output logic      s_o           // 0/1 select lines to BUFGCTRL S0/S1
);

  `CLKSYNC_PARAM_CHECK(TIMEOUT_REF_CYCLES < 4, "gf_mux_seq: TIMEOUT_REF_CYCLES must be >= 4")
  `CLKSYNC_PARAM_CHECK(SETTLE_REF_CYCLES < 1,  "gf_mux_seq: SETTLE_REF_CYCLES must be >= 1")

  localparam int unsigned CNT_W = $clog2(TIMEOUT_REF_CYCLES + 1);
  localparam logic [CNT_W-1:0] ONE = {{(CNT_W-1){1'b0}}, 1'b1};

  typedef enum logic [2:0] {
    ST_IDLE, ST_KILL_OLD, ST_QUIESCE, ST_SETTLE, ST_ARM_NEW, ST_GATE_NEW, ST_OFF
  } state_e;

  state_e     st_q, st_d;
  logic       cur_q;              // currently selected source (0/1)
  logic [CNT_W-1:0] cnt_q;
  logic       old_alive;

  assign old_alive = cur_q ? src1_alive : src0_alive;

  // ---------------- FSM next-state ------------------------------------------
  always_comb begin
    st_d = st_q;
    unique case (st_q)
      ST_IDLE: begin
        if (force_off_i)                       st_d = ST_OFF;
        else if (sel_i != cur_q)               st_d = ST_KILL_OLD;
      end
      ST_KILL_OLD:  st_d = ST_QUIESCE;
      ST_QUIESCE:   st_d = (!old_alive || (cnt_q >= CNT_W'(TIMEOUT_REF_CYCLES)))
                            ? ST_SETTLE : ST_QUIESCE;
      ST_SETTLE:    st_d = (cnt_q >= CNT_W'(SETTLE_REF_CYCLES)) ? ST_ARM_NEW : ST_SETTLE;
      ST_ARM_NEW:   st_d = (cnt_q >= CNT_W'(SETTLE_REF_CYCLES)) ? ST_GATE_NEW : ST_ARM_NEW;
      ST_GATE_NEW:  st_d = ST_IDLE;
      // Release from safety-off re-arms the CURRENT selection through the
      // normal quiesce/arm sequence (output was quiesced, so this is safe);
      // if sel_i differs from cur_q, IDLE immediately begins the real switch.
      ST_OFF:       st_d = (!force_off_i) ? ST_KILL_OLD : ST_OFF;
      default:      st_d = ST_IDLE;
    endcase
  end

  // counter
  always_ff @(posedge clk_ref or negedge rst_n) begin
    if (!rst_n)                      cnt_q <= '0;
    else if (st_q != st_d)           cnt_q <= '0;
    else                             cnt_q <= cnt_q + ONE;
  end

  // state + control registers
  logic done_q;
  always_ff @(posedge clk_ref or negedge rst_n) begin
    if (!rst_n) begin
      st_q       <= ST_IDLE;
      cur_q      <= 1'b0;
      done_q     <= 1'b0;
    end else begin
      done_q <= 1'b0;
      st_q   <= st_d;

      unique case (st_q)
        ST_IDLE: begin
          if (!force_off_i && (sel_i != cur_q)) begin
            cur_q <= sel_i;                  // target locked at switch start
          end
        end
        ST_GATE_NEW: begin
          done_q <= 1'b1;
        end
        default: ;
      endcase
    end
  end

  // ---------------- gate outputs ---------------------------------------------
  logic ce0_q, ce1_q;
  always_ff @(posedge clk_ref or negedge rst_n) begin
    if (!rst_n) begin
      ce0_q <= 1'b0;                     // reset = quiesced output
      ce1_q <= 1'b0;
    end else if (force_off_i) begin
      ce0_q <= 1'b0;                     // async-dominant safety (REQ-004)
      ce1_q <= 1'b0;
    end else begin
      unique case (st_d)
        ST_KILL_OLD: begin               // drop old CE this cycle
          if (cur_q) ce1_q <= 1'b0; else ce0_q <= 1'b0;
        end
        ST_GATE_NEW: begin               // raise new CE as we enter GATE_NEW
          if (cur_q) ce1_q <= 1'b1; else ce0_q <= 1'b1;
        end
        default: ;
      endcase
    end
  end

  assign ce0_o   = ce0_q;
  assign ce1_o   = ce1_q;
  assign s_o     = cur_q;
  assign busy_o  = (st_q inside {ST_KILL_OLD, ST_QUIESCE, ST_SETTLE,
                                 ST_ARM_NEW, ST_GATE_NEW});
  assign sw_done_o = done_q;
  assign off_o   = (st_q == ST_OFF);

`ifdef CLKSYNC_SIM_ASSERT
  // Mutual exclusion invariant (mandate §37): never both CEs high.
  always_ff @(posedge clk_ref) begin
    if (rst_n) begin
      assert (!(ce0_q && ce1_q))
        else $error("gf_mux_seq: ce0 && ce1 both asserted");
    end
  end
`endif

endmodule : gf_mux_seq

`default_nettype wire
