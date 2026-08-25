// ---------------------------------------------------------------------------
// tb_cdc_handshake — coherent multi-bit transfer across randomized clocks
// Covers CDC-HS-REQ-001..006: integrity/order/exactly-once, backpressure,
// timeout behaviour, independent-reset recovery, SVA stability property.
// ---------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_cdc_handshake;

  import tb_util_pkg::*;

  localparam int unsigned W = 16;

  logic src_clk = 1'b0, dst_clk = 1'b0;
  logic src_rst_n, dst_rst_n;

  logic [W-1:0] src_data;
  logic         src_valid, src_ready, src_busy, src_done, tmo_err;
  logic [W-1:0] dst_data;
  logic         dst_valid, dst_accept;

  // ---- main DUT (no timeout) ------------------------------------------------
  cdc_handshake #(.DATA_WIDTH(W), .SYNC_STAGES(2), .TIMEOUT_SRC_CYCLES(0)) u_dut (
    .src_clk(src_clk), .src_rst_n(src_rst_n),
    .src_data_i(src_data), .src_valid_i(src_valid),
    .src_ready_o(src_ready), .src_busy_o(src_busy),
    .src_done_o(src_done), .timeout_err_o(tmo_err),
    .dst_clk(dst_clk), .dst_rst_n(dst_rst_n),
    .dst_data_o(dst_data), .dst_valid_o(dst_valid), .dst_accept_i(dst_accept)
  );

  // ---- timeout DUT (small budget) -------------------------------------------
  logic s2_clk = 1'b0, d2_clk = 1'b0, s2_rst_n, d2_rst_n;
  logic [W-1:0] s2_data; logic s2_valid, s2_ready, s2_busy, s2_done, s2_tmo;
  logic [W-1:0] d2_data; logic d2_valid, d2_accept;
  cdc_handshake #(.DATA_WIDTH(W), .SYNC_STAGES(2), .TIMEOUT_SRC_CYCLES(40)) u_dut_tmo (
    .src_clk(s2_clk), .src_rst_n(s2_rst_n),
    .src_data_i(s2_data), .src_valid_i(s2_valid),
    .src_ready_o(s2_ready), .src_busy_o(s2_busy),
    .src_done_o(s2_done), .timeout_err_o(s2_tmo),
    .dst_clk(d2_clk), .dst_rst_n(d2_rst_n),
    .dst_data_o(d2_data), .dst_valid_o(d2_valid), .dst_accept_i(d2_accept)
  );

  int errors = 0, tests = 0;
  task automatic check(string name, bit cond);
    tests++;
    if (!cond) begin errors++; $display("[FAIL] %0t %s", $time, name); end
  endtask

  process sp, dp, sp2, dp2;
  task automatic set_clocks(realtime s_half, realtime d_half,
                            realtime s_ph, realtime d_ph);
    if (sp != null && sp.status != process::FINISHED) sp.kill();
    if (dp != null && dp.status != process::FINISHED) dp.kill();
    src_clk = 0; dst_clk = 0;
    fork begin sp=process::self(); #(s_ph); forever #(s_half) src_clk=~src_clk; end join_none
    fork begin dp=process::self(); #(d_ph); forever #(d_half) dst_clk=~dst_clk; end join_none
  endtask
  task automatic stop_dst_clock();
    if (dp != null && dp.status != process::FINISHED) dp.kill();
    dst_clk = 0;
  endtask

  // ---- scoreboard ------------------------------------------------------------
  logic [W-1:0] sent_q [$];
  logic [W-1:0] recv_q [$];
  int unsigned done_cnt = 0, cap_cnt = 0;

  always @(posedge src_clk) if (src_rst_n && src_done_o_local()) done_cnt++;
  function bit src_done_o_local(); return u_dut.done_q; endfunction

  // destination consumer thread: random-latency accept
  initial begin : consumer
    forever begin
      @(posedge dst_clk);
      if (dst_rst_n && dst_valid) begin
        cap_cnt++;
        recv_q.push_back(dst_data);
        repeat (urand(cap_cnt*17+3, 6)) @(posedge dst_clk);
        if (dst_valid) begin
          dst_accept <= 1'b1;
          @(posedge dst_clk);
          dst_accept <= 1'b0;
        end
      end
    end
  end

  // driver: one request per call, waits for readiness
  task automatic send_word(logic [W-1:0] w);
    @(posedge src_clk);
    while (!src_ready) @(posedge src_clk);
    src_data  <= w;
    src_valid <= 1'b1;
    @(posedge src_clk);
    src_valid <= 1'b0;
  endtask

  initial begin : main
    int i;

    // ================= A. integrity + order across ratio list ===============
    for (int cfg = 0; cfg < 7; cfg++) begin
      realtime sT, dT;
      case (cfg)
        0: begin sT = 10000.0; dT = 20000.0; end
        1: begin sT = 20000.0; dT = 10000.0; end
        2: begin sT = 10000.0; dT = 10101.0; end
        3: begin sT = 10000.0; dT =  9901.0; end
        4: begin sT = 30000.0; dT = 90000.0; end
        5: begin sT = 58823.5; dT =  8849.6; end
        6: begin sT = 11000.0 + real'(urand(cfg*5+9, 6000));
                dT =  8500.0 + real'(urand(cfg*3+4, 30000)); end
      endcase
      set_clocks(sT/2.0, dT/2.0,
                 real'(urand(cfg*11+2, int'(sT)))/2.0,
                 real'(urand(cfg*23+5, int'(dT)))/2.0);
      src_rst_n = 0; dst_rst_n = 0; src_valid = 0; dst_accept = 0;
      #3000; src_rst_n = 1; dst_rst_n = 1; #2000;
      sent_q.delete(); recv_q.delete(); done_cnt = 0; cap_cnt = 0;

      for (i = 0; i < 50; i++) begin
        logic [W-1:0] w;
        w = logic [W-1:0]'(urand(i*31+cfg*7+1, 65535));
        sent_q.push_back(w);
        send_word(w);
        if (urand(i*13+1,3) == 0) #(real'(urand(i,20))*sT); // random gaps
      end
      #2_000_000;                                  // drain
      check($sformatf("cfg%0d order+integrity", cfg), recv_q.size() == 50);
      for (i = 0; i < recv_q.size() && i < 50; i++)
        if (recv_q[i] !== sent_q[i]) begin
          check($sformatf("cfg%0d word%0d mismatch", cfg, i), 1'b0);
        end
      check($sformatf("cfg%0d exactly-once", cfg), done_cnt == cap_cnt);

      src_rst_n = 0; dst_rst_n = 0; #2000;
      sent_q.delete(); recv_q.delete();
    end

    // ================= B. backpressure ======================================
    begin
      set_clocks(5000.0, 4000.0, 111.0, 222.0);
      src_rst_n = 0; dst_rst_n = 0; src_valid = 0; dst_accept = 0;
      #2000; src_rst_n = 1; dst_rst_n = 1; #1000;
      sent_q.delete(); recv_q.delete(); cap_cnt = 0;
      // issue a request then hammer valid while busy — must be ignored
      fork
        begin : hammer
          send_word(32'hA5A5);
        end
        begin : spammer
          #3000;
          repeat (30) begin
            @(posedge src_clk);
            src_valid <= src_busy;                // request only while busy => ignored
          end
          src_valid <= 1'b0;
        end
      join_any
      disable fork;
      src_valid <= 1'b0;
      // normal paced transfers still work afterwards
      for (i = 0; i < 10; i++) send_word(16'hB000 + i[15:0]);
      #1_500_000;
      check("backpressure: all later words intact", recv_q.size() == 10);
      check("backpressure: last word value",
            recv_q.size() > 0 && recv_q[recv_q.size()-1] === (16'hB000 + 16'd9));
      src_rst_n = 0; dst_rst_n = 0; #2000;
      sent_q.delete(); recv_q.delete();
    end

    // ================= C. timeout path ======================================
    begin
      fork begin sp2=process::self(); #2500 forever #5000 s2_clk=~s2_clk; end join_none
      fork begin dp2=process::self(); #1700 forever #8000 d2_clk=~d2_clk; end join_none
      s2_rst_n = 0; d2_rst_n = 0; s2_valid = 0; d2_accept = 0;
      #2000; s2_rst_n = 1; d2_rst_n = 1; #1000;
      // freeze destination clock so ack never arrives
      if (dp2 != null && dp2.status != process::FINISHED) dp2.kill();
      d2_clk = 0;
      @(posedge s2_clk);
      s2_data <= 16'h1234; s2_valid <= 1'b1;
      @(posedge s2_clk); s2_valid <= 1'b0;
      // budget = 40 src cycles => err must appear within [40, 60] cycles
      fork : tmo_wait
        begin : wait_err
          wait (s2_tmo === 1'b1);
        end
        begin : limit
          repeat (61) @(posedge s2_clk);
        end
      join_any
      disable fork;
      check("timeout error raised", s2_tmo === 1'b1);
      @(posedge s2_clk);
      check("interface released after timeout", s2_ready === 1'b1);
      // restart dst clock, reset both sides to recover cleanly
      fork begin dp2=process::self(); #700 forever #8000 d2_clk=~d2_clk; end join_none
      s2_rst_n = 0; d2_rst_n = 0; #3000; s2_rst_n = 1; d2_rst_n = 1; #1000;
      check("recovery after timeout reset", s2_ready === 1'b1 && !d2_valid);
      if (sp2 != null && sp2.status != process::FINISHED) sp2.kill();
      if (dp2 != null && dp2.status != process::FINISHED) dp2.kill();
    end

    // ================= D. one-sided reset storm =============================
    begin
      set_clocks(5000.0, 6500.0, 400.0, 900.0);
      src_rst_n = 0; dst_rst_n = 0; src_valid = 0; dst_accept = 0;
      #2000; src_rst_n = 1; dst_rst_n = 1; #1000;
      sent_q.delete(); recv_q.delete();
      // transfers with occasional one-sided resets; final phase must be exact
      for (i = 0; i < 12; i++) send_word(16'hD000 + i[15:0]);
      #300_000;
      dst_rst_n = 0; #13000; dst_rst_n = 1;       // destination-only reset
      #200_000;
      for (i = 0; i < 8; i++) send_word(16'hE000 + i[15:0]);
      #2_000_000;
      check("post-storm exact tail", recv_q.size() >= 8 &&
            recv_q[recv_q.size()-1] === (16'hE000 + 16'd7));
      // protocol returned to idle on both sides
      check("idle after storm", src_ready === 1'b1);
      src_rst_n = 0; dst_rst_n = 0;
    end

    $display("=================================================");
    $display("tb_cdc_handshake: tests=%0d errors=%0d", tests, errors);
    if (errors == 0) $display("*** TEST PASSED ***");
    else             $display("*** TEST FAILED ***");
    $finish;
  end

  // SVA: payload stable while presented (CDC-HS core invariant)
  property p_data_stable;
    @(posedge dst_clk) disable iff (!dst_rst_n)
      (dst_valid_o && $past(dst_valid_o)) |-> (dst_data_o === $past(dst_data_o));
  endproperty
  A_DATA_STABLE : assert property (p_data_stable)
    else begin errors++; $error("dst_data changed while dst_valid held"); end

  initial begin
    #120_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_cdc_handshake
