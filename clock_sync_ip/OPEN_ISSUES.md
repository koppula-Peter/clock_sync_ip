# Open Issues & Temporary Assumptions

Format per mandate §65.

---

## OI-001
ID: OI-001
Missing information: Exact MMCM/PLL/VCO input-output frequency window values for XC7Z020-CLG484-1 (-1 speed grade).
Temporary assumption: none yet — no RTL consumes these numbers.
Why assumption is reasonable: M1/M2 divider and mux logic is frequency-agnostic; validation of requested configurations will use tool-extracted data.
Modules affected: IP-02 (M6), glitch-free mux parameter checks (M2), clock health manager thresholds (M3).
Risk: Low until M2/M6; misquoted windows would allow invalid MMCM requests.
How to resolve: Extract from installed 2025.2 timing models / DS181 tables during M2; record in reference map §2.3.
Evidence required: Tool-generated datasheet excerpt or timing report snippet stored under build/reports/.

## OI-002
ID: OI-002
Missing information: Vitis 2025.2 not installed on this workstation.
Temporary assumption: PS software (driver, SPLL loop, CLI) will be developed against register-map headers and reviewed; executable validation deferred.
Why assumption is reasonable: PL milestones A–F need no Vitis; AXI register map is fixed before driver coding (M7 plan).
Modules affected: sw/*, IP-10 Software PLL execution evidence.
Risk: Medium for M7 schedule only; no hardware risk.
How to resolve: Install Vitis 2025.2 or validate on the ZC702 host machine when board access begins (see OI-004).
Evidence required: Compiled+run bare-metal test log from ZC702.

## OI-003
ID: OI-003
Missing information: cocotb not installed.
Temporary assumption: SystemVerilog/xsim is the sole verification path for now.
Why assumption is reasonable: All mandated verification (self-checking TBs, SVA, randomized clocks) achievable in SV; cocotb was explicitly optional.
Modules affected: tb/.
Risk: None.
How to resolve: `pip install cocotb` if Python-driven tests are later demanded.

## OI-004
ID: OI-004
Missing information: No physical ZC702 attached to this development host.
Temporary assumption: Gates A–H executed here; Gate I (hardware validation) deferred with a prepared validation design + test plan.
Why assumption is reasonable: Board bring-up requires physical access; all pre-silicon evidence is independent of it.
Modules affected: docs/validation/*, ZC702 top-level (M8/final).
Risk: Release blocked at Gate I until hardware runs complete.
How to resolve: Schedule board session; scripts prepared so bring-up is mechanical.

## OI-005
ID: OI-005
Missing information: MTBF numbers cannot be claimed without device/timing parameters of a specific integration.
Temporary assumption: Documentation states synchronizer depth guidance + methodology instead of universal MTBT figures.
Why assumption is reasonable: Mandate §20/§33 explicitly forbids universal MTBF claims.
Modules affected: cdc level/pulse/handshake/gray documentation.
Risk: None (documentation-only).
How to resolve: Provide per-integration MTBF estimate once placement/timing exists.
Evidence required: Vivado report_timing on synchronizer paths from an integration build.
