// ---------------------------------------------------------------------------
// tb_cdc_gray_sync — Gray-coded counter observation across randomized clocks
// Covers CDC-GRAY-REQ-001..005:
//   * single-bit-change invariant (incl. wraparound)
//   * destination samples are always legal past source values (coherence)
//   * skip behaviour documented & tolerated; catch-up after quiescence
//   * inline conversions == package functions
// ---------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_cdc_gray_sync;

  import tb_util_pkg::*;
  import clk_sync_cdc_pkg::*;

  localparam int unsigned W = 6;

  logic src_clk = 1'b0, dst_clk = 1'b0;
  logic src_rst_n, dst_rst_n;
  logic inc, dec;
  logic [W-1:0] src_count, dst_count, dst_gray;

  int errors = 0, tests = 0;
  task automatic check(string name, bit cond);
    tests++;
    if (!cond) begin errors++; $display("[FAIL] %0t %s", $time, name); end
  endtask

  cdc_gray_sync #(.WIDTH(W), .SYNC_STAGES(2)) u_dut (
    .src_clk(src_clk), .src_rst_n(src_rst_n),
    .src_inc_i(inc), .src_dec_i(dec), .src_count_o(src_count),
    .dst_clk(dst_clk), .dst_rst_n(dst_rst_n),
    .dst_count_o(dst_count), .dst_gray_o(dst_gray)
  );

  process sp, dp;
  task automatic set_clocks(realtime s_half, realtime d_half,
                            realtime s_ph, realtime d_ph);
    if (sp != null && sp.status != process::FINISHED) sp.kill();
    if (dp != null && dp.status != process::FINISHED) dp.kill();
    src_clk = 0; dst_clk = 0;
    fork begin sp=process::self(); #(s_ph); forever #(s_half) src_clk=~src_clk; end join_none
    fork begin dp=process::self(); #(d_ph); forever #(d_half) dst_clk=~dst_clk; end join_none
  endtask

  // ---- legality tracking ----------------------------------------------------
  bit seen [64];                                  // every value src has held
  int unsigned legal_samples = 0, illegal_samples = 0;

  always @(posedge src_clk) begin
    if (!src_rst_n === 1'b0 && src_rst_n === 1'b1) begin
      seen[src_count] = 1'b1;
    end
  end

  always @(posedge dst_clk) begin
    if (dst_rst_n) begin
      if (seen[dst_count]) legal_samples++;
      else                 illegal_samples++;
    end
  end

  initial begin : main
    realtime sT, dT;
    int unsigned i, n_steps;

    for (int cfg = 0; cfg < 7; cfg++) begin
      case (cfg)
        0: begin sT = 10000.0; dT = 40000.0; end   // src 4x faster (skips!)
        1: begin sT = 40000.0; dT = 10000.0; end   // dst faster
        2: begin sT = 10000.0; dT = 10101.0; end
        3: begin sT = 10000.0; dT =  9901.0; end
        4: begin sT = 58823.5; dT =  8849.6; end   // 17 -> 113 MHz
        5: begin sT =  8849.6; dT = 58823.5; end   // 113 -> 17 MHz
        6: begin sT = 9500.0 + real'(urand(cfg*3+8, 8000));
                dT = 9000.0 + real'(urand(cfg*7+2, 35000)); end
      endcase
      set_clocks(sT/2.0, dT/2.0,
                 real'(urand(cfg*19+4, int'(sT)))/2.0,
                 real'(urand(cfg*37+1, int'(dT)))/2.0);
      src_rst_n = 0; dst_rst_n = 0; inc = 0; dec = 0;
      #3000;
      seen[0] = 1'b1;
      src_rst_n = 1; dst_rst_n = 1; #1000;

      // random walk incl. wraparound both directions
      n_steps = 400 + urand(cfg*53+6, 200);
      fork
        begin : walker
          for (i = 0; i < n_steps; i++) begin
            inc = (urand(i*11+cfg+1, 9) < 6);       // ~60% up
            dec = (urand(i*17+cfg+2, 9) < 4) && !inc;
            #(sT);
          end
          inc = 0; dec = 0;
        end
        begin : guard
          #(sT*n_steps*3 + 20_000_000);
        end
      join_any
      disable fork;

      // catch-up: once source is quiet, destination must equal it exactly
      repeat (30) @(posedge dst_clk); #1;
      check($sformatf("cfg%0d caught up", cfg), dst_count === src_count);

      src_rst_n = 0; dst_rst_n = 0;
      #2000; src_rst_n = 1; dst_rst_n = 1;
    end

    check("all dst samples were legal past source values",
          illegal_samples == 0 && legal_samples > 100);

    // ---- wraparound directed walk ------------------------------------------
    begin
      set_clocks(5000.0, 5000.0, 777.0, 333.0);
      src_rst_n = 0; dst_rst_n = 0; inc = 0; dec = 0;
      #2000; src_rst_n = 1; dst_rst_n = 1;
      // drive to top edge and across wrap upward
      repeat (63) begin @(posedge src_clk); inc <= 1'b1; end
      @(posedge src_clk); inc <= 1'b0;
      check("wrap up: at 0 again", src_count === '0);
      @(posedge src_clk); inc <= 1'b1;
      @(posedge src_clk); inc <= 1'b0;
      check("wrap up: then 1", src_count === 6'd1);
      // downward wrap
      repeat (2) begin @(posedge src_clk); dec <= 1'b1; end
      @(posedge src_clk); dec <= 1'b0;
      check("down to 63", src_count === 6'd63);
      @(posedge src_clk); dec <= 1'b1;
      @(posedge src_clk); dec <= 1'b0;
      check("wrap down: back to 62", src_count === 6'd62);
    end

    $display("=================================================");
    $display("tb_cdc_gray_sync: tests=%0d errors=%0d legal=%0d illegal=%0d",
             tests, errors, legal_samples, illegal_samples);
    if (errors == 0) $display("*** TEST PASSED ***");
    else             $display("*** TEST FAILED ***");
    $finish;
  end

  // SVA: Gray single-bit-change invariant on every counting step
  property p_gray_onebit;
    @(posedge src_clk) disable iff (!src_rst_n)
      (u_dut.count_q !== $past(u_dut.count_q)) |->
        ($countones(u_dut.gray_next ^ $past(u_dut.gray_next)) == 1);
  endproperty
  A_GRAY_ONEBIT : assert property (p_gray_onebit)
    else begin errors++; $error("gray multi-bit change on increment"); end

  // cross-check inline conversion vs package functions
  property p_pkg_match;
    @(posedge src_clk) (u_dut.gray_next === bin2gray(32'(src_count)));
  endproperty
  A_PKG_MATCH : assert property (p_pkg_match)
    else begin errors++; $error("inline bin2gray != pkg function"); end

  initial begin
    #120_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_cdc_gray_sync
