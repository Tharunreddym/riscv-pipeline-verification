// Reusable low-power control and clock-gating wrapper for the 5-stage RISC-V core.
// The power controller runs from the always-on clock; only the CPU clock is gated.

module riscv_power_ctrl #(
  parameter integer WAKEUP_CYCLES = 2,
  parameter integer COUNT_WIDTH = (WAKEUP_CYCLES <= 1) ? 1 : $clog2(WAKEUP_CYCLES)
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       idle_req,
  input  logic       sleep_req,
  input  logic       wake_event,
  input  logic       pipeline_empty,
  input  logic       memory_idle,
  output logic [2:0] state,
  output logic       core_clk_enable,
  output logic       quiesce_req,
  output logic       sleep_active,
  output logic       retention_save,
  output logic       retention_restore,
  output logic       wake_done
);
  localparam logic [2:0] ST_RUN    = 3'd0;
  localparam logic [2:0] ST_DRAIN  = 3'd1;
  localparam logic [2:0] ST_IDLE   = 3'd2;
  localparam logic [2:0] ST_SLEEP  = 3'd3;
  localparam logic [2:0] ST_WAKEUP = 3'd4;

  logic [2:0] state_q;
  logic [COUNT_WIDTH-1:0] wake_count_q;

  assign state = state_q;
  assign core_clk_enable = (state_q == ST_RUN) ||
                           (state_q == ST_DRAIN) ||
                           (state_q == ST_WAKEUP);
  assign quiesce_req = (state_q == ST_DRAIN);
  assign sleep_active = (state_q == ST_SLEEP);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= ST_RUN;
      wake_count_q      <= '0;
      retention_save    <= 1'b0;
      retention_restore <= 1'b0;
      wake_done         <= 1'b0;
    end else begin
      retention_save    <= 1'b0;
      retention_restore <= 1'b0;
      wake_done         <= 1'b0;

      case (state_q)
        ST_RUN: begin
          if (idle_req || sleep_req)
            state_q <= ST_DRAIN;
        end

        ST_DRAIN: begin
          // Requests are held by the requester until IDLE or SLEEP is reached.
          if (!(idle_req || sleep_req)) begin
            state_q <= ST_RUN;
          end else if (pipeline_empty && memory_idle) begin
            if (sleep_req) begin
              state_q        <= ST_SLEEP;
              retention_save <= 1'b1;
            end else begin
              state_q <= ST_IDLE;
            end
          end
        end

        ST_IDLE: begin
          if (sleep_req) begin
            state_q        <= ST_SLEEP;
            retention_save <= 1'b1;
          end else if (wake_event) begin
            state_q           <= ST_WAKEUP;
            wake_count_q      <= '0;
            retention_restore <= 1'b1;
          end
        end

        ST_SLEEP: begin
          if (wake_event) begin
            state_q           <= ST_WAKEUP;
            wake_count_q      <= '0;
            retention_restore <= 1'b1;
          end
        end

        ST_WAKEUP: begin
          if (WAKEUP_CYCLES <= 1 ||
              wake_count_q == WAKEUP_CYCLES - 1) begin
            state_q   <= ST_RUN;
            wake_done <= 1'b1;
          end else begin
            wake_count_q <= wake_count_q + 1'b1;
          end
        end

        default: begin
          state_q      <= ST_RUN;
          wake_count_q <= '0;
        end
      endcase
    end
  end
endmodule

// Latch-based integrated clock-gating model. Replace this model with the
// foundry/library ICG cell during technology mapping; do not AND clocks directly.
module riscv_icg (
  input  logic clk,
  input  logic enable,
  input  logic test_enable,
  output logic gclk
);
  logic enable_latched;
  always_latch begin
    if (!clk)
      enable_latched <= enable || test_enable;
  end
  assign gclk = clk && enable_latched;
endmodule

module riscv_pipeline_lp #(
  parameter integer IMEM_WORDS = 1024,
  parameter integer DMEM_WORDS = 1024,
  parameter integer WAKEUP_CYCLES = 2
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        idle_req,
  input  logic        sleep_req,
  input  logic        wake_event,
  input  logic        memory_idle,
  input  logic        instr_load_en,
  input  logic [31:0] instr_load_addr,
  input  logic [31:0] instr_load_data,
  output logic        ready,
  output logic [31:0] pc_dbg,
  output logic        stall,
  output logic        branch_taken,
  output logic        commit_valid,
  output logic [31:0] commit_pc,
  output logic [31:0] commit_instr,
  output logic [4:0]  commit_rd,
  output logic [31:0] commit_wdata,
  output logic        commit_reg_we,
  output logic        commit_mem_we,
  output logic [31:0] commit_mem_addr,
  output logic [31:0] commit_mem_wdata,
  output logic [31:0] if_id_pc_dbg,
  output logic [31:0] if_id_instr_dbg,
  output logic        pipeline_empty,
  output logic [2:0]  power_state,
  output logic        sleep_active,
  output logic        retention_save,
  output logic        retention_restore,
  output logic        wake_done,
  output logic        core_clk_enable,
  output logic        core_clk_gated
);
  logic quiesce_req;
  logic effective_wake_event;

  // Instruction preload is also a wake source so memory initialization cannot
  // be stranded while the CPU clock is gated.
  assign effective_wake_event = wake_event || instr_load_en;

  riscv_power_ctrl #(.WAKEUP_CYCLES(WAKEUP_CYCLES)) u_power_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .idle_req(idle_req),
    .sleep_req(sleep_req),
    .wake_event(effective_wake_event),
    .pipeline_empty(pipeline_empty),
    .memory_idle(memory_idle),
    .state(power_state),
    .core_clk_enable(core_clk_enable),
    .quiesce_req(quiesce_req),
    .sleep_active(sleep_active),
    .retention_save(retention_save),
    .retention_restore(retention_restore),
    .wake_done(wake_done)
  );

  riscv_icg u_core_icg (
    .clk(clk),
    .enable(core_clk_enable),
    .test_enable(1'b0),
    .gclk(core_clk_gated)
  );

  riscv_pipeline #(
    .IMEM_WORDS(IMEM_WORDS),
    .DMEM_WORDS(DMEM_WORDS)
  ) u_core (
    .clk(core_clk_gated),
    .rst_n(rst_n),
    .quiesce_req(quiesce_req),
    .instr_load_en(instr_load_en),
    .instr_load_addr(instr_load_addr),
    .instr_load_data(instr_load_data),
    .ready(ready),
    .pc_dbg(pc_dbg),
    .stall(stall),
    .branch_taken(branch_taken),
    .commit_valid(commit_valid),
    .commit_pc(commit_pc),
    .commit_instr(commit_instr),
    .commit_rd(commit_rd),
    .commit_wdata(commit_wdata),
    .commit_reg_we(commit_reg_we),
    .commit_mem_we(commit_mem_we),
    .commit_mem_addr(commit_mem_addr),
    .commit_mem_wdata(commit_mem_wdata),
    .if_id_pc_dbg(if_id_pc_dbg),
    .if_id_instr_dbg(if_id_instr_dbg),
    .pipeline_empty(pipeline_empty)
  );
endmodule
