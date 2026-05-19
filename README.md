# RISC-V Pipeline Verification Environment

## Overview

This project implements and verifies a 5-stage RV32I RISC-V pipeline using a UVM-based constrained-random verification environment in SystemVerilog. The verification flow includes a C++ DPI golden reference model, scoreboard-based checking, assertions, randomized instruction generation, functional coverage, and multi-seed regression testing executed on QuestaSim.

The project follows a realistic digital verification workflow:

- RTL pipeline implementation
- UVM testbench architecture
- Constrained-random stimulus generation
- Assertion-based verification
- DPI-C golden model integration
- Functional coverage collection
- Multi-seed regression execution
- Debug and closure of real pipeline hazard bugs

---

# Final Verification Status

## Regression Summary

| Metric | Result |
|---|---|
| Simulator | QuestaSim |
| ISA | RV32I |
| Pipeline Depth | 5 Stages |
| Random Regression Seeds | 20 |
| Total Instructions Checked | 800 |
| Scoreboard Mismatches | 0 |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| Final RTL Version | v7 |
| DPI-C Golden Model | Verified |

---

# Verification Features

## RTL Features

- 5-stage RV32I pipeline
- Instruction Fetch
- Decode
- Execute
- Memory
- Writeback
- Register file
- ALU operations
- Load/store support
- Branch handling
- Data forwarding
- Load-use hazard stall logic

---

## UVM Verification Architecture

### UVM Components

| Component | Purpose |
|---|---|
| Sequence Item | RV32I instruction transaction |
| Driver | Drives randomized instruction stream |
| Monitor | Captures committed writeback activity |
| Scoreboard | Compares RTL vs golden model |
| Coverage Collector | Functional instruction coverage |
| Agent | Encapsulates driver/monitor |
| Environment | Connects all verification components |
| Sequences | Directed and random stimulus |

---

## Test Types

| Test | Purpose |
|---|---|
| base_test | Basic pipeline sanity |
| hazard_test | RAW dependency verification |
| branch_test | Branch and control-flow behavior |
| random_instruction_test | Constrained-random RV32I regression |

---

# DPI-C Golden Reference Model

A C++ reference model is integrated using DPI-C.

The model:

- Decodes RV32I instructions
- Maintains architectural register state
- Models memory behavior
- Produces expected writeback results
- Serves as the golden reference for scoreboard comparison

The scoreboard compares:

- Program counter
- Destination register
- Writeback value

against the C++ model for every committed instruction.

---

# Assertions

SystemVerilog Assertions (SVA) included:

- PC progression checking
- Stall stability checking
- Forwarding correctness
- x0 write protection
- Pipeline control stability

---

# Functional Coverage

Functional coverage tracks:

- R-type instructions
- I-type instructions
- Load instructions
- Store instructions
- Branch instructions
- Hazard scenarios
- Register usage patterns

Observed random-regression coverage range:

```text
55.73% – 59.51%
```

---

# Real Debug Example

## Seed-10 Hazard Bug

During constrained-random regression, seed 10 exposed a real forwarding bug.

### Failure Observed

```text
RTL=0x00000000
EXP=0x00000001
```

### Root Cause

A younger RAW dependency writeback was incorrectly overridden by an older forwarding path.

### Fix Implemented

- Added youngest-writer priority
- Added decode-stage bypass handling
- Re-ran full regression on final v7 RTL

### Result

All 20 regression seeds passed after fix implementation.

This project intentionally preserves the real debug history because it demonstrates practical verification methodology and regression closure.

---

# Final 20-Seed Regression Results

| Seed | Result | Functional Coverage |
|---|---|---|
| 1 | PASS | 58.31% |
| 2 | PASS | 59.51% |
| 3 | PASS | 58.82% |
| 4 | PASS | 57.81% |
| 5 | PASS | 58.47% |
| 6 | PASS | 59.51% |
| 7 | PASS | 58.47% |
| 8 | PASS | 58.31% |
| 9 | PASS | 55.73% |
| 10 | PASS | 58.82% |
| 11 | PASS | 58.82% |
| 12 | PASS | 58.16% |
| 13 | PASS | 59.16% |
| 14 | PASS | 57.66% |
| 15 | PASS | 58.31% |
| 16 | PASS | 58.29% |
| 17 | PASS | 58.47% |
| 18 | PASS | 58.97% |
| 19 | PASS | 59.01% |
| 20 | PASS | 58.16% |

---

# Project Structure

```text
riscv_pipeline_verification/
├── rtl/
├── tb/
│   ├── interfaces/
│   ├── uvm/
│   └── tests/
├── assertions/
├── reference_model/
├── scripts/
├── reports/
└── README.md
```

---

# Example Simulation Command

## QuestaSim

```bash
qrun -batch -access=rw+/. -uvmhome uvm-1.2 \
-timescale 1ns/1ns -mfcu design.sv testbench.sv \
+UVM_TESTNAME=random_instruction_test -sv_seed 10 \
-do "run -all; exit"
```

---

# Skills Demonstrated

## Verification

- UVM
- Constrained-Random Verification
- SystemVerilog Assertions
- Functional Coverage
- Scoreboarding
- DPI-C Integration
- Regression Debugging
- Coverage Analysis

## Languages

- SystemVerilog
- Verilog
- C++
- Python

## Tools

- QuestaSim
- EDA Playground
- Git

---

# Future Improvements

Potential future extensions:

- UCDB merged coverage database
- Automated CI regression
- Branch prediction
- Cache subsystem verification
- Formal verification integration
- RV32M extension support
- Coverage closure optimization

---

# Key Takeaway

This project demonstrates a realistic RTL verification workflow including:

- UVM environment development
- DPI-C reference-model integration
- Constrained-random verification
- Functional coverage collection
- Assertion-based verification
- Real bug discovery and closure
- Multi-seed regression signoff

The final regression completed with:

```text
20/20 seeds PASS
0 UVM_ERROR
0 UVM_FATAL
800 committed instructions checked
```