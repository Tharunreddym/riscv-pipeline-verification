# RISC-V Pipeline Control — Formal Verification

This formal target proves the two combinational control units instantiated by the CPU RTL:

1. `riscv_load_use_hazard_unit`: determines when the IF/ID instruction must stall behind a load in ID/EX.
2. `riscv_forwarding_unit`: selects the newest eligible operand producer, excludes x0, and does not forward a load from EX/MEM before its data is available.

The units are defined in `eda_playground/design.sv` and instantiated by `riscv_pipeline`. The formal harness targets those same module definitions rather than a separately reimplemented example.

## Properties checked

### Load-use hazard unit

- Stall behavior for R-type, store, branch, I-type, load, and JALR source dependencies.
- No stall without a valid load producer, valid consumer, or nonzero destination register.
- Two-source consumers are checked on rs1 and rs2; one-source consumers are checked on rs1.

### Forwarding unit

- Both forwarded outputs select the newest eligible producer or the register-file/base value.
- EX/MEM wins over MEM/WB when both target the same source register.
- EX/MEM load results are not forwarded prematurely.
- x0 is not treated as a producer.

The harness includes cover targets for dependency, priority, load-interlock, and x0 corner cases.

## Run locally

Install Yosys, SymbiYosys (SBY), and Boolector through the OSS CAD Suite, then run:

```bash
sby -f formal/riscv_hazard.sby prove
sby -f formal/riscv_hazard.sby cover
sby -f formal/riscv_forwarding.sby prove
sby -f formal/riscv_forwarding.sby cover
```

## Scope

These are formal checks of the combinational load-use and forwarding units as instantiated by the CPU. They are not a full sequential proof of the five-stage processor, ISA compliance proof, or memory-system proof. The existing UVM simulation regression remains a separate validation layer.
