EDA Playground single-file version
==================================

Use these two files for the browser simulator bring-up:

1. Paste design.sv into the EDA Playground design panel.
2. Paste testbench.sv into the EDA Playground testbench panel.
3. Select:
   - Language: SystemVerilog/Verilog
   - Methodology: UVM
   - Simulator: Mentor Questa
   - Top entity/module: tb_top
4. Run option for first test:
   +UVM_TESTNAME=base_test

Then try:
   +UVM_TESTNAME=hazard_test
   +UVM_TESTNAME=branch_test
   +UVM_TESTNAME=random_instruction_test

Notes:
- This EDA version uses a SystemVerilog-only scoreboard so you do not need C++ DPI linking.
- The full GitHub project can still keep the C++ DPI golden model version.
- The design.sv here includes a small testbench-friendly patch that allows instruction memory preload while reset is active.
- Do not claim coverage/pass-rate evidence until you run the simulations and save logs.


V4 fix notes:
- Added same-cycle WB-to-ID register bypass in design.sv.
- Relaxed PC increment assertion across reset release using $past(rst_n).


Version v5 note:
- random_instruction_test uses an EDA-friendly constrained-random stream.
- Random load/store operations are limited to aligned in-range addresses.
- Random branches/jumps are excluded from this specific random test because branch behavior is already covered by branch_test.


V6 update: corrected EX/MEM vs MEM/WB forwarding priority after seed 10 exposed a RAW hazard with repeated writes to the same source register.


Version v7: Adds decode-stage youngest-writer bypass for seed-10 RAW corner case.
