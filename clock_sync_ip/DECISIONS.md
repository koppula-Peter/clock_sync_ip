# Architecture Decision Log

Each entry: ID, date, status, context, decision, consequences, traceability.

---

## AD-001 — Greenfield baseline confirmed
Date: 2026-08-25 · Status: ACCEPTED
Context: Repository audit found an empty directory (docs/audit/REPOSITORY_AUDIT.md).
Decision: Build the mandated suite from zero in dependency order; no legacy migration needed.
Consequences: Requirements authored from scratch; audit doc is the empty-baseline evidence.

## AD-002 — Two-layer architecture (portable core / AMD backend)
Status: ACCEPTED
Decision: Layer-1 portable RTL contains all CDC/measurement/control logic; Layer-2
`rtl/xilinx_7series/` owns every BUFG/MMCM/DRP primitive. The single sanctioned
vendor touchpoint inside Layer-1 is the ASYNC_REG attribute macro, so other
families remap one definition.
Consequences: Portability preserved; CDC attributes remain effective for report_cdc.
Traceability: mandate §4; reference map §3.

## AD-003 — Clock-enable ticks over fabric clocks (standing rule)
Status: ACCEPTED
Decision: Slow internal events (kHz-range sampling, monitors, loops) use
one-cycle enable pulses from counters in an existing domain; no LUT-generated
global clocks anywhere. Exceptions must be documented individually.
Traceability: mandate §3; UG472 routing rules.

## AD-004 — Production clock mux = BUFGCTRL class only
Status: ACCEPTED (implementation M2)
Decision: `assign clk = sel ? a : b;` exists solely as an educational reference
model (`rtl/clock_mux/clock_mux_generic_ref.v`, simulation/non-clock use only,
clearly marked). Production switching instantiates BUFGCTRL-derived primitives;
stopped-source handling follows the documented asynchronous-mux model but is
only reachable through the health manager's quiesce policy.
Traceability: mandate §10/§11; UG472 Ch.2.

## AD-005 — Verification stack: xsim primary, Verilator lint, yosys-smtbmc formal
Status: ACCEPTED
Decision: Self-checking SV testbenches run under xsim (primary, full SVA),
Verilator --lint-only as static gate, formal properties checked with
yosys+smtbmc(z3). cocotb optional (OI-003).
Consequences: Reproducible scripts only; no manual GUI steps in flow.

## AD-006 — Reset policy: async assert, sync deassert, per domain
Status: ACCEPTED
Detail in docs/architecture/RESET_ARCHITECTURE.md.
Consequence: Every CDC protocol module defines behaviour under independent
domain resets and is tested for it.

## AD-007 — Gray/handshake data-path constraints use set_max_delay -datapath_only (+ set_bus_skew where applicable)
Status: ACCEPTED (applied from first synthesis onward)
Rationale: bounds skew so sampled multi-bit words are coherent; false paths only
on control bits whose semantics tolerate delay. Each exception logged when used.
Traceability: UG903; UG949 CDC methodology.
