# Clocking and Synchronization IP Suite

Industrial-grade, reusable clocking/CDC soft-IP for AMD Zynq-7000 / 7-Series
(first target: ZC702, XC7Z020-CLG484-1, Vivado 2025.2).

- Status tracking: [`CURRENT_STATUS.md`](CURRENT_STATUS.md) (always reflects reality)
- Open issues / assumptions: [`OPEN_ISSUES.md`](OPEN_ISSUES.md)
- Architecture decision log: [`DECISIONS.md`](DECISIONS.md)
- Verification state: [`VERIFICATION_STATUS.md`](VERIFICATION_STATUS.md)
- Audit baseline: [`docs/audit/REPOSITORY_AUDIT.md`](docs/audit/REPOSITORY_AUDIT.md)

## Layout

```
rtl/            Layer-1 portable RTL + rtl/xilinx_7series/ (Layer-2 backend)
tb/             Self-checking SystemVerilog testbenches
formal/         SVA property files + yosys/smtbmc scripts
sim/            Simulator runners and artifacts
constraints/    XDC per module/integration
scripts/        Deterministic build/test TCL+shell entry points
vivado/         Vivado project generators (OOC synthesis etc.)
sw/             baremetal | linux | applications
models/         Python reference models (DPLL/FLL math)
docs/           Requirements, architecture, interfaces, verification,
                implementation, software, validation, maintenance, milestones
build/          Generated outputs only — never committed
```

## Quick start

```bash
cd sim && ./run_m1_regression.sh        # xsim regression, M1 modules
./../formal/run_formal.sh               # yosys-smtbmc formal checks
./../scripts/vivado_ooc_synth.sh m1     # OOC synthesis + report_cdc bundle
```

Versioning: semantic (`v0.1.0-development` … `v1.0.0-release`), tracked in
`VERSION` and mirrored into hardware ID registers when the integration layer
lands.
