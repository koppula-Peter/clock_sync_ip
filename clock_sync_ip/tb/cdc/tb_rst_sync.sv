// ---------------------------------------------------------------------------
// tb_rst_sync — self-checking unit testbench for rst_sync
// Covers CDC-RST-REQ-001..006 (async assert, sync deassert, depth sweep,
// polarity fixed active-low here, deterministic init).
// ---------------------------------------------------------------------------
`timescale 1ps/1ps

module tb_rst_sync;

  import tb_util_pkg::*;

  localparam int unsigned NUM_DUTS = 3;
  logic clk = 1'b0;
  logic rst_n_a = 1'b0;
  logic [NUM_DUTS-1:0] rst_out;

  int errors = 0;
  int tests  = 0;

  // three depths: minimum legal (2), default-ish (3), deeper (4)
  rst_sync #(.STAGES(2)) u_dut2 (.clk(clk), .rst_n_a(rst_n_a), .rst_n_o(rst_out[0]));
  rst_sync #(.STAGES(3)) u_dut3 (.clk(clk), .rst_n_a(rst_n_a), .rst_n_o(rst_out[1]));
  rst_sync #(.STAGES(4)) u_dut4 (.clk(clk), .rst_n_a(rst_n_a), .rst_n_o(rst_out[2]));

  always #5000 clk = ~clk;             // 100 MHz equivalent @ 1ps resolution

  task automatic check(string name, bit cond);
    tests++;
    if (!cond) begin
      errors++;
      $display("[FAIL] %0t %s", $time, name);
    end
  endtask

  // ---- T1: power-up / init state ------------------------------------------
  initial begin : main
    realtime t_in, t_out[NUM_DUTS];
    int unsigned exp_cycles[NUM_DUTS];
    int unsigned i;

    exp_cycles[0] = 2; exp_cycles[1] = 3; exp_cycles[2] = 4;

    repeat (10) @(posedge clk);
    for (i = 0; i < NUM_DUTS; i++)
      check("T1 init: output asserted during reset", rst_out[i] === 1'b0);

    // ---- T2: synchronous release timing (release just before a rising edge)
    #1234;                                // off-edge release
    t_in = $realtime;
    fork
      for (i = 0; i < NUM_DUTS; i++) begin
        wait (rst_out[i] === 1'b1);
        t_out[i] = $realtime;
      end
    join
    for (i = 0; i < NUM_DUTS; i++) begin
      realtime lo = t_in + (exp_cycles[i]-1)*10000 - 1;
      realtime hi = t_in +  exp_cycles[i]   *10000 + 1;
      check("T2 release inside [S-1, S] cycles",
            (t_out[i] > lo) && (t_out[i] < hi));
    end

    // ---- T3: asynchronous assertion (immediate, off-edge)
    #25000;                               // land mid-half-period
    t_in = $realtime;
    rst_n_a = 1'b0;
    #100;                                 // tiny delta for propagation
    for (i = 0; i < NUM_DUTS; i++)
      check("T3 async assert immediate", rst_out[i] === 1'b0);

    // ---- T4: randomized reset-pulse storm ----------------------------------
    for (int k = 0; k < 200; k++) begin
      int unsigned w, d;
      bit was_out[NUM_DUTS];
      w = urand(k*13+7, 40);              // pulse width in ps bucket -> below
      // random width between 0.2 and 5 clock cycles
      w = 2000 + urand(k*7+1, 48000);
      d = urand(k*11+3, 60000);
      #(real'(d));
      for (i = 0; i < NUM_DUTS; i++) was_out[i] = (rst_out[i] === 1'b1);
      rst_n_a = 1'b0;
      #100;
      for (i = 0; i < NUM_DUTS; i++)
        check("T4 output follows assertion", rst_out[i] === 1'b0);
      #(real'(w));
      rst_n_a = 1'b1;
      // wait past deepest pipeline then confirm released again
      repeat (6) @(posedge clk);
      #1;
      for (i = 0; i < NUM_DUTS; i++)
        if (was_out[i]) check("T4 releases after pulse storm", rst_out[i] === 1'b1);
    end

    $display("=================================================");
    $display("tb_rst_sync: tests=%0d errors=%0d", tests, errors);
    $display(errors == 0 ? "*** TEST PASSED ***" : "*** TEST FAILED ***");
    $finish;
  end

  // watchdog
  initial begin
    #20_000_000;
    $display("*** TEST FAILED (watchdog timeout) ***");
    $finish;
  end

endmodule : tb_rst_sync
