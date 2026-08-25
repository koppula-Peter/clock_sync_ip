// clk_sync_attributes.vh — single sanctioned vendor touchpoint for CDC attributes
// See DECISIONS.md AD-002 and docs/architecture/CDC_ARCHITECTURE.md
`ifndef CLK_SYNC_ATTRIBUTES_VH
`define CLK_SYNC_ATTRIBUTES_VH

`ifdef SYNTHESIS
  `define CLKSYNC_ASYNC_REG (* ASYNC_REG = "TRUE" *)
`else
  `define CLKSYNC_ASYNC_REG
`endif

// Elaboration-time parameter validation. Formal backend (yosys) gets checks
// disabled; they remain enforced in simulation and synthesis flows.
`ifndef CLKSYNC_FORMAL
  `define CLKSYNC_PARAM_CHECK(cond, msg) \
    /* verilator lint_off GENUNNAMED */ \
    if (cond) $fatal(1, "%m: %s", msg); \
    /* verilator lint_on GENUNNAMED */
`else
  `define CLKSYNC_PARAM_CHECK(cond, msg)
`endif

`endif // CLK_SYNC_ATTRIBUTES_VH
