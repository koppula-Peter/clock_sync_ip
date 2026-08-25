// ---------------------------------------------------------------------------
// tb_clk_divider — self-checking unit TB for clk_divider (CLK-DIV-REQ-001..007)
// Checks: tick period for several ratios incl. min/max/bypass, 50% waveform
// duty (even), glitch-free runtime update boundary, restart determinism,
// out-of-range write rejection + sticky error, status readback.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_clk_divider;

  localparam int unsigned DIVIDE_MAX = 64;

  logic clk = 1'b0;
  logic rst_n;
  logic [31:0] div_value;
  logic div_load, restart;
  logic config_err, update_pending;
  logic [$clog2(DIVIDE_MAX)-1:0] active_div;
  logic tick, wave;

  clk_divider #(.DIVIDE_MIN(1), .DIVIDE_MAX(DIVIDE_MAX), .DEFAULT_DIVIDE(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .div_value_i(div_value), .div_load_i(div_load), .restart_i(restart),
    .config_err_o(config_err), .update_pending_o(update_pending),
    .active_div_o(active_div),
    .clk_en_tick_o(tick), .div_ce_wave_o(wave)
  );

  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;                       // 100 MHz
  /* verilator lint_on BLKSEQ */
  default clocking cb @(posedge clk); endclocking

  int errors = 0, tests = 0;
  task automatic check(string n, bit c);
    tests++; if (!c) begin errors++; $display("[FAIL] %0t %s", $time, n); end
  endtask

  localparam int unsigned CW = $clog2(DIVIDE_MAX);
  localparam logic [CW-1:0] DIV_ONE  = {{(CW-1){1'b0}}, 1'b1};
  localparam logic [CW-1:0] DIV_TOP  = CW'(DIVIDE_MAX);

  // count cycles between rising tick edges
  task automatic measure_tick_period(input int unsigned events,
                                     inout longint unsigned worst_lo,
                                     inout longint unsigned worst_hi);
    longint unsigned lo, last_t, t;
    last_t = 0; worst_lo = 9999; worst_hi = 0;
    for (int e = 0; e < events; e++) begin
      @(posedge tick); #1;
      t = 64'($time);
      if (last_t != 0) begin
        lo = (t - last_t)/10;
        if (lo < worst_lo) worst_lo = lo;
        if (lo > worst_hi) worst_hi = lo;
      end
      last_t = t;
    end
  endtask

  initial begin : main
    div_value = 32'd4; div_load = 0; restart = 0;
    rst_n = 0;
    repeat (4) @(cb);
    rst_n = 1;
    repeat (2) @(cb);

    // ---- T1: default ratio 4 — measure 12 tick intervals --------------------
    begin
      longint unsigned wlo, whi;
      measure_tick_period(12, wlo, whi);
      check("T1 period==4 across 12 ticks", (wlo==4 && whi==4));
    end

    // ---- T2: divide-by-1 bypass ticks every cycle ---------------------------
    div_value = 32'd1; div_load = 1;
    @(cb); div_load = 0;
    // commit at terminal count of the running period (<= 4 cycles)
    repeat (6) @(cb);
    check("T2 active_div reads 1", active_div == DIV_ONE);
    begin
      int seen = 0;
      repeat (10) begin @(cb); #1; if (tick) seen++; end
      check("T2 bypass ticks every cycle", seen == 10);
    end

    // ---- T3: max ratio 64 ---------------------------------------------------
    div_value = 32'd64; div_load = 1;
    @(cb); div_load = 0;
    @(cb); #1;                               // status regs lag one edge
    check("T3 pending visible", update_pending == 1'b1);
    begin
      longint unsigned wlo, whi;
      // bypass commits immediately every cycle
      @(cb); #1;
      check("T3 active_div reads 64", active_div == CW'(64));
      check("T3 pending cleared", update_pending == 1'b0);
      @(posedge tick);                     // align to first committed tick
      measure_tick_period(4, wlo, whi);
      check("T3 period==64", (wlo==64 && whi==64));
    end

    // ---- T4: even-ratio waveform duty (ratio 8 -> 4 high / 4 low) -----------
    div_value = 32'd8; div_load = 1;
    @(cb); div_load = 0;
    repeat (10) @(cb);
    begin
      int high = 0, low = 0;
      // sample over one full period starting at a tick edge
      @(posedge tick);
      repeat (8) begin #1; if (wave) high++; else low++; @(cb); end
      check("T4 wave duty 4/4 at ratio 8", (high==4 && low==4));
    end

    // ---- T5: glitch-free runtime update: no interval <1 or >max(2*old,new) --
    div_value = 32'd16; div_load = 1;
    @(cb); div_load = 0;
    repeat (20) @(cb);                      // settle at ratio 16
    fork
      begin : stim
        div_value = 32'd5; div_load = 1;
        @(cb); div_load = 0;
      end
      begin : mon
        longint unsigned last_t = 0, t;
        int              gap;
        forever begin
          @(posedge tick); #1;
          t = 64'($time);
          if (last_t != 0) begin
            gap = int'((t - last_t) / 10ns / 1);
            check("T5 gap within [1..16]", (gap>=1 && gap<=16));
          end
          last_t = t;
        end
      end
    join_any
    disable fork;
    repeat (40) @(cb);

    // ---- T6: restart determinism --------------------------------------------
    restart = 1; @(cb); restart = 0;
    begin
      longint unsigned wlo, whi;
      measure_tick_period(3, wlo, whi);
      check("T6 period resumes 16 after restart", (wlo==16 && whi==16));
    end

    // ---- T7: out-of-range write rejected, sticky err, value unchanged -------
    div_value = 32'd100; div_load = 1;
    @(cb); div_load = 0; #1;
    check("T7 config_err asserted", config_err == 1'b1);
    check("T7 active unchanged", active_div == 16);
    div_value = 32'd7; div_load = 1;
    @(cb); div_load = 0; #1;
    check("T7 err cleared by valid load", config_err == 1'b0);
    repeat (10) @(cb);
    check("T7 active reads 7", active_div == 7);

    $display("=================================================");
    $display("tb_clk_divider: tests=%0d errors=%0d", tests, errors);
    if (errors == 0) $display("*** TEST PASSED ***");
    else             $display("*** TEST FAILED ***");
    $finish;
  end

  // Sampled invariant checks (portable immediate assertions)
  logic prev_tick;
  /* verilator lint_off BLKSEQ */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_tick <= 1'b0;
    end else begin
      if (prev_tick && tick && (active_div > DIV_ONE)) begin
        errors++; $error("[SVA] back-to-back tick with div>1 @%0t", $time);
      end
      if (!(active_div >= DIV_ONE && active_div <= DIV_TOP)) begin
        errors++; $error("[SVA] active_div out of range @%0t", $time);
      end
      prev_tick <= tick;
    end
  end
  /* verilator lint_on BLKSEQ */

  initial begin
    #50_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_clk_divider
