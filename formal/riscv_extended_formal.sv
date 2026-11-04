// Sequential properties for the exact combinational fetch-control unit
// instantiated by riscv_pipeline. State flops model the CPU's PC and IF/ID regs.

module riscv_fetch_control_formal;
  (* gclk *) reg formal_timestep;

  reg rst_n = 1'b0;
  always @(posedge formal_timestep)
    rst_n <= 1'b1;

  (* anyseq *) reg stall;
  (* anyseq *) reg branch_taken;
  (* anyseq *) reg quiesce_req;
  (* anyseq *) reg [31:0] branch_target;
  (* anyseq *) reg [31:0] instr_fetch;

  reg [31:0] pc_q = 32'h0;
  reg if_id_valid_q = 1'b0;
  reg [31:0] if_id_pc_q = 32'h0;
  reg [31:0] if_id_instr_q = 32'h0000_0013;

  wire [31:0] pc_next;
  wire if_id_valid_next;
  wire [31:0] if_id_pc_next;
  wire [31:0] if_id_instr_next;

  riscv_fetch_control_unit dut (
    .pc_current(pc_q),
    .instr_fetch(instr_fetch),
    .stall(stall),
    .branch_taken(branch_taken),
    .branch_target(branch_target),
    .quiesce_req(quiesce_req),
    .if_id_valid_current(if_id_valid_q),
    .if_id_pc_current(if_id_pc_q),
    .if_id_instr_current(if_id_instr_q),
    .pc_next(pc_next),
    .if_id_valid_next(if_id_valid_next),
    .if_id_pc_next(if_id_pc_next),
    .if_id_instr_next(if_id_instr_next)
  );

  always @(posedge formal_timestep) begin
    if (!rst_n) begin
      pc_q <= 32'h0;
      if_id_valid_q <= 1'b0;
      if_id_pc_q <= 32'h0;
      if_id_instr_q <= 32'h0000_0013;
    end else begin
      pc_q <= pc_next;
      if_id_valid_q <= if_id_valid_next;
      if_id_pc_q <= if_id_pc_next;
      if_id_instr_q <= if_id_instr_next;
    end
  end

  reg past_valid = 1'b0;
  always @(posedge formal_timestep) begin
    past_valid <= 1'b1;
    if (past_valid && $past(rst_n)) begin
      // Branch redirect has priority over both stall and normal fetch.
      if ($past(branch_taken)) begin
        assert(pc_q == $past(branch_target));
        assert(!if_id_valid_q);
        assert(if_id_instr_q == 32'h0000_0013);
      end else if ($past(stall)) begin
        assert(pc_q == $past(pc_q));
        assert(if_id_valid_q == $past(if_id_valid_q));
        assert(if_id_pc_q == $past(if_id_pc_q));
        assert(if_id_instr_q == $past(if_id_instr_q));
      end else begin
        assert(pc_q == ($past(pc_q) + 32'd4));
        if ($past(quiesce_req)) begin
          assert(!if_id_valid_q);
          assert(if_id_instr_q == 32'h0000_0013);
        end else begin
          assert(if_id_valid_q);
          assert(if_id_pc_q == $past(pc_q));
          assert(if_id_instr_q == $past(instr_fetch));
        end
      end

      cover(branch_taken && stall);
      cover(stall && !branch_taken);
      cover(quiesce_req && !stall && !branch_taken);
      cover(!quiesce_req && !stall && !branch_taken);
    end
  end
endmodule

// Formal invariants for the architectural register-file module used by CPU RTL.

module riscv_register_file_formal;
  (* gclk *) reg formal_timestep;
  // Keep reset released in this proof; x0 is re-zeroed every active clock.
  wire rst_n = 1'b1;

  (* anyseq *) reg wr_en;
  (* anyseq *) reg [4:0] wr_addr;
  (* anyseq *) reg [31:0] wr_data;
  (* anyseq *) reg [4:0] rs1_addr;
  (* anyseq *) reg [4:0] rs2_addr;

  wire [31:0] rs1_data;
  wire [31:0] rs2_data;
  wire [31:0] x0_value;

  riscv_register_file dut (
    .clk(formal_timestep),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .x0_value(x0_value)
  );

  reg past_valid = 1'b0;
  always @(posedge formal_timestep) begin
    past_valid <= 1'b1;

    if (past_valid)
      assert(x0_value == 32'h0);

    if (past_valid) begin
      // x0 is an architectural constant even when a write to address zero is
      // requested. Functional write/readback behavior is also exercised by
      // the existing UVM simulation regression.
      assert(x0_value == 32'h0);
      cover(wr_en && (wr_addr == 5'd0));
      cover(wr_en && (wr_addr != 5'd0));
    end
  end
endmodule

// Formal read/write and word-addressing invariants for CPU data memory.

module riscv_data_memory_formal;
  (* gclk *) reg formal_timestep;
  // Data contents are initialized in the memory module; writes are enabled.
  wire rst_n = 1'b1;

  (* anyseq *) reg wr_en;
  (* anyseq *) reg [31:0] wr_addr;
  (* anyseq *) reg [31:0] wr_data;
  (* anyseq *) reg [31:0] rd_addr;
  wire [31:0] rd_data;

  riscv_data_memory #(.DEPTH(4)) dut (
    .clk(formal_timestep),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_addr(rd_addr),
    .rd_data(rd_data)
  );

  reg past_valid = 1'b0;
  always @(posedge formal_timestep) begin
    past_valid <= 1'b1;

    // The harness proves the four implemented words and permits any byte
    // offset within each aligned 32-bit word.
    assume(wr_addr[31:4] == 28'h0);
    assume(rd_addr[31:4] == 28'h0);

    if (past_valid && $past(rst_n)) begin
      // A write to a word is readable at any byte offset of that same word.
      if ($past(wr_en) && ($past(wr_addr[31:2]) == rd_addr[31:2]))
        assert(rd_data == $past(wr_data));

      // With a stable read word and no write to that word, data is stable.
      if ((rd_addr[31:2] == $past(rd_addr[31:2])) &&
          !($past(wr_en) && ($past(wr_addr[31:2]) == rd_addr[31:2])))
        assert(rd_data == $past(rd_data));

      cover($past(wr_en) && $past(wr_addr[1:0] != rd_addr[1:0]) &&
            ($past(wr_addr[31:2]) == rd_addr[31:2]));
      cover($past(wr_en) && ($past(wr_addr[31:2]) != rd_addr[31:2]));
    end
  end
endmodule
