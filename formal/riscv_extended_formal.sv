// Sequential formal harnesses for the reusable CPU control/storage modules.
// formal_timestep is the SBY global clock. formal_clk is a real derived
// design clock that toggles once every global formal step pair.

module riscv_fetch_control_formal;
  (* gclk *) reg formal_timestep;
  reg formal_clk = 1'b0;
  always @(posedge formal_timestep)
    formal_clk <= !formal_clk;

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

  always @(posedge formal_clk) begin
    pc_q <= pc_next;
    if_id_valid_q <= if_id_valid_next;
    if_id_pc_q <= if_id_pc_next;
    if_id_instr_q <= if_id_instr_next;
  end

  reg past_valid = 1'b0;
  reg prev_stall = 1'b0;
  reg prev_branch = 1'b0;
  reg prev_quiesce = 1'b0;
  reg [31:0] prev_pc = 32'h0;
  reg [31:0] prev_target = 32'h0;
  reg [31:0] prev_fetch = 32'h0;
  reg prev_if_id_valid = 1'b0;
  reg [31:0] prev_if_id_pc = 32'h0;
  reg [31:0] prev_if_id_instr = 32'h0000_0013;

  always @(posedge formal_clk) begin
    if (past_valid) begin
      // Branch redirect has priority over both stall and sequential fetch.
      if (prev_branch) begin
        assert(pc_q == prev_target);
        assert(!if_id_valid_q);
        assert(if_id_pc_q == 32'h0);
        assert(if_id_instr_q == 32'h0000_0013);
      end else if (prev_stall) begin
        assert(pc_q == prev_pc);
        assert(if_id_valid_q == prev_if_id_valid);
        assert(if_id_pc_q == prev_if_id_pc);
        assert(if_id_instr_q == prev_if_id_instr);
      end else begin
        assert(pc_q == (prev_pc + 32'd4));
        if (prev_quiesce) begin
          assert(!if_id_valid_q);
          assert(if_id_instr_q == 32'h0000_0013);
        end else begin
          assert(if_id_valid_q);
          assert(if_id_pc_q == prev_pc);
          assert(if_id_instr_q == prev_fetch);
        end
      end
    end

    past_valid <= 1'b1;
    prev_stall <= stall;
    prev_branch <= branch_taken;
    prev_quiesce <= quiesce_req;
    prev_pc <= pc_q;
    prev_target <= branch_target;
    prev_fetch <= instr_fetch;
    prev_if_id_valid <= if_id_valid_q;
    prev_if_id_pc <= if_id_pc_q;
    prev_if_id_instr <= if_id_instr_q;

    cover(branch_taken && stall);
    cover(stall && !branch_taken);
    cover(quiesce_req && !stall && !branch_taken);
    cover(!quiesce_req && !stall && !branch_taken);
  end
endmodule

module riscv_register_file_formal;
  (* gclk *) reg formal_timestep;
  reg formal_clk = 1'b0;
  always @(posedge formal_timestep)
    formal_clk <= !formal_clk;

  wire rst_n = 1'b1;
  (* anyseq *) reg wr_en;
  (* anyseq *) reg [4:0] wr_addr;
  (* anyseq *) reg [31:0] wr_data;
  (* anyseq *) reg [4:0] rs1_addr;
  (* anyseq *) reg [4:0] rs2_addr;

  wire [31:0] rs1_data, rs2_data, x0_value;
  wire accepted_write_en;

  riscv_register_file_write_guard u_write_guard (
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .accepted_write_en(accepted_write_en)
  );

  riscv_register_file dut (
    .clk(formal_clk),
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
  reg prev_wr_en = 1'b0;
  reg [4:0] prev_wr_addr = 5'd0;
  reg [31:0] prev_wr_data = 32'h0;

  always @(posedge formal_clk) begin
    if (past_valid) begin
      assert(accepted_write_en == (wr_en && (wr_addr != 5'd0)));
      assert(!(wr_addr == 5'd0 && accepted_write_en));

      // After the first active edge, x0 is stored as zero and read as zero.
      assert(x0_value == 32'h0);
      assert(rs1_addr != 5'd0 || rs1_data == 32'h0);
      assert(rs2_addr != 5'd0 || rs2_data == 32'h0);

      // A nonzero write from the prior edge is visible on either async read port.
      if (prev_wr_en && (prev_wr_addr != 5'd0) && (rs1_addr == prev_wr_addr))
        assert(rs1_data == prev_wr_data);
      if (prev_wr_en && (prev_wr_addr != 5'd0) && (rs2_addr == prev_wr_addr))
        assert(rs2_data == prev_wr_data);
    end

    past_valid <= 1'b1;
    prev_wr_en <= wr_en && (wr_addr != 5'd0);
    prev_wr_addr <= wr_addr;
    prev_wr_data <= wr_data;

    cover(wr_en && (wr_addr == 5'd0) && !accepted_write_en);
    cover(wr_en && (wr_addr != 5'd0) && accepted_write_en);
    cover((rs1_addr == 5'd0) && (rs1_data == 32'h0));
  end
endmodule

module riscv_data_memory_formal;
  (* gclk *) reg formal_timestep;
  reg formal_clk = 1'b0;
  always @(posedge formal_timestep)
    formal_clk <= !formal_clk;

  wire rst_n = 1'b1;
  (* anyseq *) reg wr_en;
  (* anyseq *) reg [31:0] wr_addr;
  (* anyseq *) reg [31:0] wr_data;
  (* anyseq *) reg [31:0] rd_addr;
  wire [31:0] rd_data;

  riscv_data_memory #(.DEPTH(4)) dut (
    .clk(formal_clk),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_addr(rd_addr),
    .rd_data(rd_data)
  );

  reg past_valid = 1'b0;
  reg prev_wr_valid = 1'b0;
  reg [31:0] prev_wr_addr = 32'h0;
  reg [31:0] prev_wr_data = 32'h0;

  always @(posedge formal_clk) begin
    // Restrict the memory proof to its four implemented words.
    assume(wr_addr[31:4] == 28'h0);
    assume(rd_addr[31:4] == 28'h0);

    if (past_valid) begin
      // A write to a word is visible at the next sampled edge for every byte
      // offset within that same word, matching [31:2] addressing in the RTL.
      if (prev_wr_valid && (prev_wr_addr[31:2] == rd_addr[31:2]))
        assert(rd_data == prev_wr_data);

      cover(prev_wr_valid && (prev_wr_addr[1:0] != rd_addr[1:0]) &&
            (prev_wr_addr[31:2] == rd_addr[31:2]));
      cover(prev_wr_valid && (prev_wr_addr[31:2] != rd_addr[31:2]));
    end

    past_valid <= 1'b1;
    prev_wr_valid <= wr_en && (wr_addr[31:2] < 4);
    prev_wr_addr <= wr_addr;
    prev_wr_data <= wr_data;
  end
endmodule
