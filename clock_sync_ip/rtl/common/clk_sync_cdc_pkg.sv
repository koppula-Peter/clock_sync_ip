// clk_sync_cdc_pkg.sv — Gray-code conversion helpers shared across the suite.
// Gray property: successive values of a ±1-incrementing binary sequence map to
// codes differing in exactly ONE bit, making any-time sampling coherent.
package clk_sync_cdc_pkg;

  // Binary -> Gray (combinational, pure)
  function automatic logic [31:0] bin2gray(input logic [31:0] b);
    return b ^ (b >> 1);
  endfunction

  // Gray -> Binary (combinational, pure)
  function automatic logic [31:0] gray2bin(input logic [31:0] g);
    logic [31:0] b;
    b[31] = g[31];
    for (int i = 30; i >= 0; i--) begin
      b[i] = b[i+1] ^ g[i];
    end
    return b;
  endfunction

endpackage : clk_sync_cdc_pkg
