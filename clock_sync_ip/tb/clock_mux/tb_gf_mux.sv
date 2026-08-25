// ---------------------------------------------------------------------------
// tb_gf_mux — glitch-free mux verification (CLK-GFMUX-REQ-001..005)
// Layer-1 sequencer + behavioural BUFGCTRL gates (CE sampled by each source
// clock; output changes only at source edges, HOLDS when CE low — the UG472
// property that makes real switching glitch-free).
// Monitors every output high/low width and rise-rise spacing: no runts, no
// double pulses. Cases: first-gate, phase-random switches, selected-source
// death failover (via new request), dead-target arm, safety override,
// rapid retargeting storm.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_gf_mux;

  localparam realtime REF_HALF  = 5.0;    // 100 MHz reference/safety domain
  localparam realtime SRC0_HALF = 10.0;   // 50 MHz
  localparam realtime SRC1_HALF = 16.5;   // ~30.3 MHz
  localparam int      TIMEOUT   = 64;

  logic clk_ref = 1'b0, clk_src0 = 1'b0, clk_src1 = 1'b0;
  logic run0 = 1'b1, run1 = 1'b1;
  logic alive0 = 1'b1, alive1 = 1'b1;
  logic rst_n;
  logic sel, force_off, busy, done, off_st;
  /* verilator lint_off MULTIDRIVEN */
  logic ce0, ce1, s, mclk;
  /* verilator lint_on MULTIDRIVEN */

  /* verilator lint_off BLKSEQ */
  always #(REF_HALF)  clk_ref = ~clk_ref;
  always #SRC0_HALF if (run0) clk_src0 = ~clk_src0;
  always #SRC1_HALF if (run1) clk_src1 = ~clk_src1;
  /* verilator lint_on BLKSEQ */

  // alive flags trail their run enables by one ref cycle
  always_ff @(posedge clk_ref) begin
    alive0 <= run0; alive1 <= run1;
  end

  // behavioural BUFGCTRL x2 (UG472: CE sampled by its source clock)
  logic ce0_s = 1'b0, ce1_s = 1'b0;
  always @(posedge clk_src0) ce0_s <= ce0;
  always @(posedge clk_src1) ce1_s <= ce1;
  /* verilator lint_off BLKSEQ */
  always @(posedge clk_src0) if (ce0_s) mclk <= 1'b1;
  always @(negedge clk_src0) if (ce0_s) mclk <= 1'b0;
  always @(posedge clk_src1) if (ce1_s) mclk <= 1'b1;
  always @(negedge clk_src1) if (ce1_s) mclk <= 1'b0;
  /* verilator lint_on BLKSEQ */

  gf_mux_seq #(.TIMEOUT_REF_CYCLES(TIMEOUT)) dut (
    .clk_ref(clk_ref), .rst_n(rst_n),
    .sel_i(sel), .force_off_i(force_off),
    .src0_alive(alive0), .src1_alive(alive1),
    .busy_o(busy), .sw_done_o(done), .off_o(off_st),
    .ce0_o(ce0), .ce1_o(ce1), .s_o(s)
  );

  // ---------------- monitors / checks ---------------------------------------
  int errors = 0, tests = 0;
  task automatic check(string n, bit c);
    tests++; if (!c) begin errors++; $display("[FAIL] %0t %s", $time, n); end
  endtask

  realtime t_rise = 0.0, t_fall = 0.0, t_prev_rise = 0.0;
  int runt_hi = 0, runt_lo = 0, dbl = 0;

  /* verilator lint_off BLKSEQ */
  always @(posedge mclk) begin
    if (t_fall != 0.0 && ($realtime - t_fall) < 7.0) runt_lo++;
    if (t_prev_rise != 0.0) begin
      realtime gap;
      gap = $realtime - t_prev_rise;
      if (gap < 18.0 && gap > 2.0) dbl++;
    end
    t_prev_rise = $realtime;
    t_rise      = $realtime;
  end
  always @(negedge mclk) begin
    if (t_rise != 0.0 && ($realtime - t_rise) < 7.0) runt_hi++;
    t_fall = $realtime;
  end
  /* verilator lint_on BLKSEQ */

  task automatic wait_done(input int max_ns);
    int waited;
    waited = 0;
    while (!done && waited < max_ns) begin
      #(REF_HALF*2); waited += 10;
    end
    check("switch completed in time", done == 1'b1);
  endtask

  initial begin : main
    sel = 0; force_off = 0; rst_n = 0;
    repeat (4) @(posedge clk_ref);
    rst_n = 1;
    repeat (2) @(posedge clk_ref);

    // ---- T1: reset quiesced; first request gates source 0 ------------------
    check("T1 quiesced after reset", ce0 == 0 && ce1 == 0);
    sel = 1'b0;
    wait_done(20000);
    check("T1 ce0 asserted", ce0 == 1'b1 && ce1 == 1'b0);
    repeat (20) @(posedge mclk);

    // ---- T2: phase-random switches 0<->1 ------------------------------------
    repeat (6) begin
      #(($random % 19));
      sel = ~sel;
      wait_done(TIMEOUT*10 + 30000);
      repeat (15) @(posedge mclk);
    end
    check("T2 no runt high pulses", runt_hi == 0);
    check("T2 no runt low pulses",  runt_lo == 0);
    check("T2 no double pulses",    dbl == 0);

    // ---- T3: SELECTED source dies -> health/software issues new request -----
    sel = 1'b0;
    wait_done(TIMEOUT*10 + 30000);
    repeat (10) @(posedge mclk);
    run0 = 1'b0;                                  // selected clock stops
    #(REF_HALF*6);
    sel = 1'b1;                                   // failover request
    wait_done(TIMEOUT*10 + 30000);
    check("T3 failed over to src1", ce1 == 1'b1 && ce0 == 1'b0 && s == 1'b1);
    run0 = 1'b1;
    repeat (10) @(posedge mclk);

    // ---- T4: TARGET dead at arm time; output resumes when revived -----------
    run0 = 1'b0;                                  // kill target before request
    #(REF_HALF*4);
    sel = 1'b0;
    wait_done(TIMEOUT*10 + 30000);
    check("T4 completed onto dead target", ce0 == 1'b1 && ce1 == 1'b0);
    #(REF_HALF*8);                                // output held (no edges)
    begin
      int seen;
      run0 = 1'b1;                                // revive
      seen = 0;
      fork
        begin : w
          #200000;
        end
        begin : c
          while (seen < 5) begin @(posedge mclk); seen++; end
        end
      join_any
      disable fork;
      check("T4 output resumed after revive", seen >= 5);
    end

    // ---- T5: safety override -------------------------------------------------
    force_off = 1'b1;
    @(posedge clk_ref); #1;
    check("T5 both CEs dropped within 1 ref cycle", ce0 == 1'b0 && ce1 == 1'b0);
    check("T5 off status visible", off_st == 1'b1);
    force_off = 1'b0;
    wait_done(TIMEOUT*10 + 30000);
    check("T5 re-armed after release", ((ce0 ^ ce1) == 1'b1) && !off_st);
    repeat (10) @(posedge mclk);

    // ---- T6: rapid retarget storm settles on last request -------------------
    fork
      begin : storm
        repeat (4) begin #700; sel = ~sel; end
        sel = 1'b1;
      end
      begin : drain
        #6000;
      end
    join_any
    disable fork;
    while (busy) @(posedge clk_ref);
    #1;
    check("T6 settled on last request", s == 1'b1 && ce1 == 1'b1 && ce0 == 1'b0);

    check("T7 global no runt hi", runt_hi == 0);
    check("T7 global no runt lo", runt_lo == 0);
    check("T7 global no doubles", dbl == 0);

    $display("=================================================");
    $display("tb_gf_mux: tests=%0d errors=%0d", tests, errors);
    if (errors == 0) $display("*** TEST PASSED ***");
    else             $display("*** TEST FAILED ***");
    $finish;
  end

  // sampled invariant: CEs never both high (mandate §37 mux property)
  /* verilator lint_off BLKSEQ */
  /* verilator lint_off SYNCASYNCNET */
  always @(posedge clk_ref) begin
    if (rst_n) begin
      assert (!(ce0 && ce1))
        else begin errors++; $error("[SVA] ce0&&ce1 both high @%0t", $time); end
    end
  end
  /* verilator lint_on BLKSEQ */
  /* verilator lint_on SYNCASYNCNET */

  initial begin
    #80_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_gf_mux
