# RISC-V Low-Power Extension

This folder adds a low-power control path around the existing five-stage CPU.

## Implemented

- RUN, DRAIN, IDLE, SLEEP, and WAKEUP states in an always-on power controller.
- Fetch quiescence during DRAIN; the CPU stops admitting new instructions while valid pipeline entries retire.
- Entry to IDLE/SLEEP only after pipeline_empty and memory_idle are both asserted.
- A latch-based integrated clock-gating simulation model for the CPU clock.
- Retention-save and retention-restore request pulses, plus a parameterized wake-up interval.
- A wrapper that instantiates the original riscv_pipeline and connects the manager to its pipeline-empty status.

The base UVM flow remains available and ties quiesce_req low. The low-power wrapper is an additional integration path.

## Run

From the repository root:

    make -C low_power test

The test checks pipeline drain, clock stoppage in IDLE, PC stability while gated, memory-idle qualification before SLEEP, retention signaling, and wake-up.

## Integration notes

The clock-gating module is a behavioral latch-based ICG model. Replace it with a characterized library ICG cell during implementation and perform clock-tree / STA checks. The memory_idle input must be driven by the actual memory or interconnect outstanding-transaction status. Retention outputs are control requests; this RTL does not instantiate retention flops or power switches.

No physical power reduction, silicon measurement, UPF implementation, or post-layout result is claimed. Capture VCD/SAIF and run a library-based power flow before making a power-saving claim.
