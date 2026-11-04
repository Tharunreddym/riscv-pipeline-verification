module riscv_pipeline_lp_tb;
  logic clk = 1'b0;
  logic rst_n;
  logic idle_req, sleep_req, wake_event, memory_idle;
  logic instr_load_en;
  logic [31:0] instr_load_addr, instr_load_data;
  logic ready, stall, branch_taken, commit_valid, commit_reg_we, commit_mem_we;
  logic [31:0] pc_dbg, commit_pc, commit_instr, commit_wdata;
  logic [4:0] commit_rd;
  logic [31:0] commit_mem_addr, commit_mem_wdata;
  logic [31:0] if_id_pc_dbg, if_id_instr_dbg;
  logic pipeline_empty, sleep_active, retention_save, retention_restore;
  logic wake_done, core_clk_enable, core_clk_gated;
  logic [2:0] power_state;
  integer core_edges;
  integer saved_edges;
  logic [31:0] saved_pc;

  localparam logic [2:0] ST_RUN=3'd0, ST_DRAIN=3'd1, ST_IDLE=3'd2, ST_SLEEP=3'd3, ST_WAKEUP=3'd4;

  always #5 clk = ~clk;
  always @(posedge core_clk_gated) core_edges = core_edges + 1;

  riscv_pipeline_lp #(.WAKEUP_CYCLES(2)) dut (
    .clk(clk), .rst_n(rst_n),
    .idle_req(idle_req), .sleep_req(sleep_req), .wake_event(wake_event),
    .memory_idle(memory_idle),
    .instr_load_en(instr_load_en), .instr_load_addr(instr_load_addr),
    .instr_load_data(instr_load_data),
    .ready(ready), .pc_dbg(pc_dbg), .stall(stall), .branch_taken(branch_taken),
    .commit_valid(commit_valid), .commit_pc(commit_pc), .commit_instr(commit_instr),
    .commit_rd(commit_rd), .commit_wdata(commit_wdata), .commit_reg_we(commit_reg_we),
    .commit_mem_we(commit_mem_we), .commit_mem_addr(commit_mem_addr),
    .commit_mem_wdata(commit_mem_wdata), .if_id_pc_dbg(if_id_pc_dbg),
    .if_id_instr_dbg(if_id_instr_dbg), .pipeline_empty(pipeline_empty),
    .power_state(power_state), .sleep_active(sleep_active),
    .retention_save(retention_save), .retention_restore(retention_restore),
    .wake_done(wake_done), .core_clk_enable(core_clk_enable),
    .core_clk_gated(core_clk_gated)
  );

  initial begin
    core_edges = 0;
    rst_n = 1'b0;
    idle_req = 1'b0;
    sleep_req = 1'b0;
    wake_event = 1'b0;
    memory_idle = 1'b1;
    instr_load_en = 1'b0;
    instr_load_addr = '0;
    instr_load_data = 32'h0000_0013;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // Request idle. The pipeline must stop fetching and drain before gating.
    @(negedge clk);
    idle_req = 1'b1;
    wait (power_state == ST_DRAIN);
    wait (power_state == ST_IDLE);
    #1;
    if (!pipeline_empty || core_clk_enable)
      $fatal(1, "CPU entered IDLE before the pipeline drained or clock gating engaged");
    saved_pc = pc_dbg;
    @(negedge clk);
    idle_req = 1'b0;
    saved_edges = core_edges;
    repeat (4) @(posedge clk);
    #1;
    if (core_edges != saved_edges || pc_dbg != saved_pc)
      $fatal(1, "CPU clock or PC changed while in IDLE");

    // Wake and confirm the programmed wake-up interval.
    @(negedge clk);
    wake_event = 1'b1;
    @(negedge clk);
    wake_event = 1'b0;
    wait (wake_done);
    wait (power_state == ST_RUN);
    repeat (2) @(posedge core_clk_gated);

    // Deep sleep is permitted only after the core and memory path are idle.
    @(negedge clk);
    memory_idle = 1'b0;
    sleep_req = 1'b1;
    wait (power_state == ST_DRAIN);
    repeat (3) @(posedge clk);
    if (power_state == ST_SLEEP)
      $fatal(1, "CPU entered SLEEP while memory was not idle");
    @(negedge clk);
    memory_idle = 1'b1;
    wait (power_state == ST_SLEEP);
    #1;
    if (!sleep_active || !retention_save || core_clk_enable)
      $fatal(1, "SLEEP entry did not assert retention and gate the core clock");

    @(negedge clk);
    sleep_req = 1'b0;
    wake_event = 1'b1;
    @(negedge clk);
    wake_event = 1'b0;
    wait (wake_done);
    if (power_state != ST_RUN)
      $fatal(1, "Core failed to return to RUN after wake-up");

    $display("PASS: RISC-V low-power controller drained, gated, retained, and woke the CPU.");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "Timeout in riscv_pipeline_lp_tb");
  end
endmodule
