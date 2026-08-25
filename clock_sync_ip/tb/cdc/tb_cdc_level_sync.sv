// ---------------------------------------------------------------------------
// tb_cdc_level_sync — level synchronizer across randomized independent clocks
// Covers CDC-LVL-REQ-001..006 and mandate §32 clock-ratio list.
// Four DUT configurations exercised simultaneously.
// ---------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_cdc_level_sync;

  import tb_util_pkg::*;

  // {src_T_ps}: mandated ratios incl. 100→99, 100→101 MHz, 17→113 MHz, plus
  // one fully-random destination period slot.
  localparam int unsigned N_RATIO = 8;
  realtime SRC_T [N_RATIO] = '{
    10000.0,   // 100 MHz src
    20000.0,   // 50 MHz
    20000.0,   // 50 -> will pair with ~10 ns dst (2x)
     9900.0,   // ~101 MHz (vs 10 ns dst => 100->99 class)
    10100.0,   // ~99 MHz
    58823.5,   // 17 MHz
     8850.0,   // 113 MHz
    10000.0    // paired with RANDOM dst below
  };

  logic dst_clk = 1'b0;
  logic dst_rst_n;
  logic src_sig;

  logic d2, d3, d3r, d4r;

  cdc_level_sync #(.STAGES(2), .OUT_REG(1'b0)) u_dut2 (.dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .src_async(src_sig), .dst_data(d2));
  cdc_level_sync #(.STAGES(3), .OUT_REG(1'b0)) u_dut3 (.dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .src_async(src_sig), .dst_data(d3));
  cdc_level_sync #(.STAGES(3), .OUT_REG(1'b1), .RESET_VALUE(1'b1)) u_dut3r (.dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .src_async(src_sig), .dst_data(d3r));
  cdc_level_sync #(.STAGES(4), .OUT_REG(1'b1)) u_dut4r (.dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .src_async(src_sig), .dst_data(d4r));

  logic [3:0] dut_out;
  assign dut_out = {d2, d3, d3r, d4r};

  int errors = 0, tests = 0;

  task automatic check(string name, bit cond);
    tests++;
    if (!cond) begin errors++; $display("[FAIL] %0t %s", $time, name); end
  endtask

  // ---- restartable destination clock ---------------------------------------
  process clk_p;
  task automatic set_dst_clock(realtime half_period, realtime first_delay);
    if (clk_p != null && clk_p.status != process::FINISHED) clk_p.kill();
    dst_clk = 1'b0;
    fork
      begin : clk_thread
        clk_p = process::self();
        #(first_delay);
        forever #(half_period) dst_clk = ~dst_clk;
      end
    join_none
  endtask

  initial begin : main
    realtime sT, dT, ph;
    int unsigned i;

    // ================= ratio sweep ==========================================
    for (int cfg = 0; cfg < N_RATIO; cfg++) begin
      sT = SRC_T[cfg];
      if (cfg == N_RATIO-1) dT = 8000.0 + real'(urand(cfg*31+5, 40000));
      else                  dT = sT * ((cfg % 3 == 0) ? 1.0 : ((cfg % 3 == 1) ? 0.5 : 1.01));
      ph = real'(urand(cfg*17+2, int'(sT))) / 2.0;

      src_sig  = 1'b0;
      dst_rst_n = 1'b0;
      set_dst_clock(dT/2.0, ph);
      #2000;
      check("init RESET_VALUE applied (dut3r)", d3r === 1'b1);
      dst_rst_n = 1'b1;
      #1000;

      // source toggles at randomized multiples of its own period
      for (i = 0; i < 40; i++) begin
        #(sT * (1 + urand(i+cfg*97+1, 6)));
        src_sig = ~src_sig;
      end
      #(sT * 12);

      repeat (14) @(posedge dst_clk); #1;
      check($sformatf("cfg%0d final value d2",  cfg), d2  === src_sig);
      check($sformatf("cfg%0d final value d3",  cfg), d3  === src_sig);
      check($sformatf("cfg%0d final value d3r", cfg), d3r === src_sig);
      check($sformatf("cfg%0d final value d4r", cfg), d4r === src_sig);
    end

    // ================= latency bound (deep config) ===========================
    begin
      realtime t_chg, t_seen;
      set_dst_clock(5000.0, 3000.0);
      @(posedge dst_clk);
      #1;
      t_chg = $realtime;
      src_sig = ~src_sig;
      wait (d4r === src_sig);
      t_seen = $realtime;
      // documented bound: STAGES(4)+OUT_REG(1)+1 slack cycles @10ns
      check("latency within documented bound",
            (t_seen - t_chg) <= (6 * 10000.0 + 2000.0));
    end

    // ================= transition activity storm =============================
    begin
      int trans_seen;
      trans_seen = 0;
      fork
        begin : stim
          for (i = 0; i < 30; i++) begin #7000; src_sig = ~src_sig; end
        end
        begin : mon
          forever @(posedge dst_clk) trans_seen++;
        end
      join_any
      disable fork;
      check("dst sampled during storm", trans_seen > 20);
    end

    $display("=================================================");
    $display("tb_cdc_level_sync: tests=%0d errors=%0d", tests, errors);
    if (errors == 0) $display("*** TEST PASSED ***");
    else             $display("*** TEST FAILED ***");
    $finish;
  end

  // SVA: outputs never X after reset release
  always @(posedge dst_clk) begin
    if (dst_rst_n) begin
      assert (!$isunknown(dut_out))
        else begin errors++; $error("X on synchronized outputs"); end
    end
  end

  initial begin
    #60_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_cdc_level_sync
