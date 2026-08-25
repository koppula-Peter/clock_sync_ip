// ---------------------------------------------------------------------------
// tb_cdc_pulse_sync — toggle pulse synchronizer across randomized clocks
// Covers CDC-PULSE-REQ-001..005: lossless transfer under the documented
// separation rule, violation flagging, both rate regimes, one-sided reset.
// ---------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_cdc_pulse_sync;

  import tb_util_pkg::*;

  logic src_clk = 1'b0, dst_clk = 1'b0;
  logic src_rst_n, dst_rst_n;
  logic src_pulse;
  logic src_busy, undersep_err, dst_pulse;

  int errors = 0, tests = 0;

  task automatic check(string name, bit cond);
    tests++;
    if (!cond) begin errors++; $display("[FAIL] %0t %s", $time, name); end
  endtask

  // MIN_SEP default = 3 source cycles
  cdc_pulse_sync #(.SYNC_STAGES(2), .MIN_SEP_SRC_CYCLES(3)) u_dut (
    .src_clk(src_clk), .src_rst_n(src_rst_n),
    .src_pulse_i(src_pulse), .src_busy_o(src_busy), .undersep_err_o(undersep_err),
    .dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .dst_pulse_o(dst_pulse)
  );

  process sp, dp;
  task automatic set_clocks(realtime s_half, realtime d_half,
                            realtime s_ph, realtime d_ph);
    if (sp != null && sp.status != process::FINISHED) sp.kill();
    if (dp != null && dp.status != process::FINISHED) dp.kill();
    src_clk = 1'b0; dst_clk = 1'b0;
    fork begin : s_th sp = process::self(); #(s_ph); forever #(s_half) src_clk = ~src_clk; end join_none
    fork begin : d_th dp = process::self(); #(d_ph); forever #(d_half) dst_clk = ~dst_clk; end join_none
  endtask

  // event counters via monitors (independent of stimulus)
  int unsigned sent_cnt = 0, recv_cnt = 0, rej_cnt = 0;
  always @(posedge src_clk) if (src_rst_n && src_pulse && !src_busy) sent_cnt++;
  always @(posedge src_clk) if (src_rst_n && undersep_err)            rej_cnt++;
  always @(posedge dst_clk) if (dst_rst_n && dst_pulse)               recv_cnt++;

  initial begin : main
    realtime sT, dT, sep_min;
    int unsigned i, n_ev;

    // ================= A. lossless sweep over mandated ratios ===============
    // ratio list {sT, dT}: fast->slow, slow->fast, near-equal, prime-ish
    for (int cfg = 0; cfg < 7; cfg++) begin
      case (cfg)
        0: begin sT = 10000.0; dT = 20000.0; end   // 100 -> 50 MHz
        1: begin sT = 20000.0; dT = 10000.0; end   // 50 -> 100 MHz
        2: begin sT = 10000.0; dT = 10101.0; end   // 100 -> 99 MHz class
        3: begin sT = 10000.0; dT =  9901.0; end   // 100 -> 101 MHz class
        4: begin sT = 30000.0; dT = 90000.0; end   // 33.3 -> 11.1 MHz
        5: begin sT = 58823.5; dT =  8849.6; end   // 17 -> 113 MHz
        6: begin sT = 12000.0 + real'(urand(91,9000));
                dT =  8000.0 + real'(urand(77,40000)); end // random pair
      endcase

      set_clocks(sT/2.0, dT/2.0,
                 real'(urand(cfg*13+1, int'(sT)))/2.0,
                 real'(urand(cfg*29+3, int'(dT)))/2.0);
      src_rst_n = 0; dst_rst_n = 0; src_pulse = 0;
      #3000;
      src_rst_n = 1; dst_rst_n = 1;
      #2000;

      // separation satisfying BOTH: >= MAX(MIN_SEP*T_src, 3*T_dst)
      sep_min = (3.0*sT > 3.0*dT) ? 3.0*sT : 3.0*dT;
      n_ev = 60;
      fork
        begin : events
          for (i = 0; i < n_ev; i++) begin
            src_pulse = 1'b1;
            #(sT/10.0);
            src_pulse = 1'b0;
            #(sep_min * (1.0 + real'(urand(i*7+cfg+2, 30))/10.0));
          end
        end
        begin : guard
          #(sep_min*n_ev*40 + 40_000_000);
        end
      join_any
      disable fork;
      #500_000;                                  // drain in-flight toggles
      check($sformatf("cfg%0d lossless count", cfg), recv_cnt == sent_cnt);
      check($sformatf("cfg%0d no rejects",     cfg), rej_cnt == 0);

      // reset counters for next config
      src_rst_n = 0; dst_rst_n = 0;
      #2000;
      sent_cnt = 0; recv_cnt = 0; rej_cnt = 0;
      src_rst_n = 1; dst_rst_n = 1;
      #1000;
    end

    // ================= B. under-separation violation flagging ==============
    begin
      set_clocks(5000.0, 5000.0, 1234.0, 4567.0);
      src_rst_n = 0; dst_rst_n = 0; src_pulse = 0;
      #2000; src_rst_n = 1; dst_rst_n = 1;
      sent_cnt = 0; recv_cnt = 0; rej_cnt = 0;
      #1000;
      // back-to-back pulses every 1 cycle => every other must be rejected
      repeat (20) begin
        src_pulse = 1'b1; #(10000.0/2.0);
        src_pulse = 1'b0; #(10000.0/2.0);
      end
      #1_000_000;
      check("violations flagged", rej_cnt > 5);
      check("accepted == received (merged/rejected not delivered)",
            recv_cnt == sent_cnt);
      src_rst_n = 0; #2000; src_rst_n = 1;
      sent_cnt = 0; recv_cnt = 0; rej_cnt = 0;
    end

    // ================= C. one-sided reset bounded anomaly ==================
    begin
      int before_sent, before_recv;
      set_clocks(5000.0, 7000.0, 999.0, 333.0);
      src_rst_n = 0; dst_rst_n = 0; src_pulse = 0;
      #2000; src_rst_n = 1; dst_rst_n = 1;
      #1000;
      // establish alignment with several spaced events
      for (i = 0; i < 10; i++) begin
        src_pulse = 1'b1; #(5000.0); src_pulse = 1'b0;
        #(50_000.0);
      end
      #500_000;
      before_sent = sent_cnt; before_recv = recv_cnt;
      check("aligned baseline", before_recv == before_sent);
      // one-sided source reset mid-operation
      src_rst_n = 0; #15000; src_rst_n = 1;
      #5000;
      for (i = 0; i < 10; i++) begin
        src_pulse = 1'b1; #(5000.0); src_pulse = 1'b0;
        #(50_000.0);
      end
      #500_000;
      // bounded anomaly: at most one deviation total, then exact tracking
      check("one-sided reset: <=1 anomaly",
            ((recv_cnt >= before_recv + (sent_cnt-before_sent) - 1) &&
             (recv_cnt <= before_recv + (sent_cnt-before_sent) + 1)));
      // after realignment the very next events track exactly
      sent_cnt = 0; recv_cnt = 0;
      for (i = 0; i < 10; i++) begin
        src_pulse = 1'b1; #(5000.0); src_pulse = 1'b0;
        #(50_000.0);
      end
      #500_000;
      check("re-aligned exact tracking", recv_cnt == sent_cnt);
    end

    $display("=================================================");
    $display("tb_cdc_pulse_sync: tests=%0d errors=%0d", tests, errors);
    if (errors == 0) $display("*** TEST PASSED ***");
    else             $display("*** TEST FAILED ***");
    $finish;
  end

  initial begin
    #80_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_cdc_pulse_sync
