// ---------------------------------------------------------------------------
// clk_divider — programmable integer divider, enable-tick architecture
// Spec: docs/modules/M2_CLK_DIV_SPEC.md   Reqs: CLK-DIV-REQ-001..007
// Layer 1 (portable). AD-003: slow events are one-cycle ENABLE TICKS in an
// existing domain. This module never emits a fabric clock (CLK-DIV-REQ-007);
// an actual divided clock is a Layer-2 backend concern (BUFGCE_DIV class).
//
// Outputs:
//   clk_en_tick_o : one-clk-cycle pulse every DIVIDE cycles (Mode A).
//   div_ce_wave_o : enable WAVEFORM high for DIVIDE/2 cycles per period
//                   (even ratios => exact 50%; odd => floor(DIVIDE/2), the
//                   tick strobe remains the reference event). NOT a clock.
//
// Runtime updates: div_load_i latches div_value_i into a shadow register;
// the new ratio is applied AT TERMINAL COUNT so no tick interval can be
// shorter than one cycle or longer than old/new DIVIDE (REQ-003).
// Out-of-range live writes are ignored and raise sticky config_err_o (REQ-006);
// restart_i or a subsequent in-range load clears it.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none
`include "clk_sync_attributes.vh"

module clk_divider #(
  parameter int unsigned DIVIDE_MIN     = 1,    // >= 1
  parameter int unsigned DIVIDE_MAX     = 64,   // >= DIVIDE_MIN
  parameter int unsigned DEFAULT_DIVIDE = 4     // within [MIN..MAX]
) (
  input  wire logic                     clk,
  input  wire logic                     rst_n,        // async assert / sync release
  input  wire logic [31:0]              div_value_i,  // requested ratio
  input  wire logic                     div_load_i,   // one-cycle load pulse
  input  wire logic                     restart_i,    // one-cycle restart pulse
  output logic                          config_err_o, // sticky range violation
  output logic                          update_pending_o,
  output logic [$clog2(DIVIDE_MAX)-1:0] active_div_o,
  output logic                          clk_en_tick_o,
  output logic                          div_ce_wave_o
);

  localparam int unsigned CNT_W = $clog2(DIVIDE_MAX);
  localparam logic [CNT_W-1:0] ONE = {{(CNT_W-1){1'b0}}, 1'b1};

  `CLKSYNC_PARAM_CHECK(DIVIDE_MIN < 1,                 "clk_divider: DIVIDE_MIN must be >= 1")
  `CLKSYNC_PARAM_CHECK(DIVIDE_MAX < DIVIDE_MIN,        "clk_divider: DIVIDE_MAX must be >= DIVIDE_MIN")
  `CLKSYNC_PARAM_CHECK((DEFAULT_DIVIDE < DIVIDE_MIN) || (DEFAULT_DIVIDE > DIVIDE_MAX),
                       "clk_divider: DEFAULT_DIVIDE out of range")

  // ---------------- configuration interface ---------------------------------
  logic range_bad;
  assign range_bad = (div_value_i < 32'(DIVIDE_MIN)) || (div_value_i > 32'(DIVIDE_MAX));

  logic [CNT_W-1:0] active_q, shadow_q;
  logic             pending_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q       <= CNT_W'(DEFAULT_DIVIDE);
      shadow_q       <= CNT_W'(DEFAULT_DIVIDE);
      pending_q      <= 1'b0;
      config_err_o   <= 1'b0;
      update_pending_o <= 1'b0;
    end else begin
      if (div_load_i) begin
        if (range_bad) begin
          config_err_o <= 1'b1;                    // rejected, sticky (REQ-006)
        end else begin
          shadow_q           <= div_value_i[CNT_W-1:0];
          pending_q          <= 1'b1;
          config_err_o       <= 1'b0;              // good load clears error
        end
      end else if (restart_i) begin
        config_err_o <= 1'b0;
      end

      // commit shadow -> active only at terminal count (glitch-free, REQ-003)
      if (pending_q && ((active_q == ONE) || (count_q >= active_q - ONE))) begin
        active_q         <= shadow_q;
        pending_q        <= 1'b0;
      end
      update_pending_o <= pending_q;
    end
  end

  assign active_div_o = active_q;

  // ---------------- period counter ------------------------------------------
  logic [CNT_W-1:0] count_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_q <= '0;
    end else if (restart_i || (active_q == ONE) || (count_q >= active_q - ONE)) begin
      count_q <= '0;                               // wrap (divide-by-1 idles at 0)
    end else begin
      count_q <= count_q + ONE;
    end
  end

  logic last_count;
  assign last_count = (active_q == ONE) || (count_q >= active_q - ONE);

  // ---------------- outputs ---------------------------------------------------
  // REQ-001/002: tick every DIVIDE cycles; bypass ticks every cycle.
  assign clk_en_tick_o = last_count;

  // Enable waveform: high while count < DIVIDE/2 (registered). Even ratios give
  // exact 50% duty; odd ratios give floor(DIVIDE/2) — tick strobe is the
  // reference event (see header). Constant 0 for divide-by-1 bypass.
  logic wave_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)    wave_q <= 1'b0;
    else           wave_q <= !restart_i && (count_q < CNT_W'(active_q >> 1));
  end
  assign div_ce_wave_o = wave_q;

endmodule : clk_divider

`default_nettype wire
