# RISC-V CPU Formal Verification

This directory formal-checks reusable control/storage units that are instantiated by the actual five-stage CPU RTL. It does not claim full sequential proof of the complete processor.

## Current proof targets

| Harness | RTL unit | Properties |
|---|---|---|
| `riscv_hazard.sby` | Load-use interlock | Exact stall decode for source dependencies; valid load and consumer qualification; x0 exclusion |
| `riscv_forwarding.sby` | Forwarding priority | EX/MEM over MEM/WB; x0 suppression; no premature forwarding of load results |
| `riscv_fetch_control.sby` | PC / IF-ID next-state control | Stall stability; branch redirect/flush priority; normal fetch; quiesce behavior |
| `riscv_regfile.sby` | Architectural register file | x0 remains zero; nonzero writes are observable through read ports |
| `riscv_memory.sby` | Word-addressed data memory | Write/read consistency; byte-offset alias within a word; stability when no write targets the read word |

The fetch-control, register-file, and data-memory modules are instantiated by `riscv_pipeline`. The formal harnesses model their sequential state and prove the module properties under symbolic inputs.

## Run all positive proofs and covers

Install Yosys, SymbiYosys (SBY), and Boolector through the OSS CAD Suite, then run:

```bash
sby -f formal/riscv_hazard.sby prove
sby -f formal/riscv_hazard.sby cover
sby -f formal/riscv_forwarding.sby prove
sby -f formal/riscv_forwarding.sby cover
sby -f formal/riscv_fetch_control.sby prove
sby -f formal/riscv_fetch_control.sby cover
sby -f formal/riscv_regfile.sby prove
sby -f formal/riscv_regfile.sby cover
sby -f formal/riscv_memory.sby prove
sby -f formal/riscv_memory.sby cover
```

## Counterexample-driven negative control

`formal/negative_control/` contains an intentionally broken forwarding implementation where the older MEM/WB assignment overrides a newer EX/MEM producer. It is not instantiated by the CPU.

Run:

```bash
bash scripts/run_formal_negative_control.sh
```

The script expects SBY to fail the buggy proof, requires a generated VCD counterexample, and copies it to `formal/negative_control/artifacts/forwarding_priority_counterexample.vcd`. This expected failure is treated as a successful negative-control test. The production forwarding unit remains youngest-producer-first and is separately proven by `riscv_forwarding.sby`.

## Scope and limitations

- Proofs cover the combinational hazard and forwarding units, plus bounded-sequential state properties for fetch control, register file, and data memory.
- Fetch-control checks use unconstrained symbolic stall, branch, quiesce, redirect and instruction inputs; they do not prove the branch comparator or full pipeline interaction.
- Register-file proof checks x0 protection and write/read behavior of the extracted architectural register file.
- Memory proof is parameterized to four words and proves address-index behavior and read/write consistency for that scope.
- These are not a full sequential proof of the whole five-stage CPU, full RV32I compliance, external memory protocol, or silicon signoff.

GitHub Actions runs all positive proofs and covers, then the negative-control test and uploads the failing trace as an artifact.
