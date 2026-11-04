// -----------------------------------------------------------------------------
// Fetch / pipeline-control next-state unit. Instantiated by riscv_pipeline and
// sequentially checked by formal/riscv_fetch_control.sby.
// -----------------------------------------------------------------------------
module riscv_fetch_control_unit #(
  parameter [31:0] NOP = 32'h0000_0013
) (
  input  logic [31:0] pc_current,
  input  logic [31:0] instr_fetch,
  input  logic        stall,
  input  logic        branch_taken,
  input  logic [31:0] branch_target,
  input  logic        quiesce_req,
  input  logic        if_id_valid_current,
  input  logic [31:0] if_id_pc_current,
  input  logic [31:0] if_id_instr_current,
  output logic [31:0] pc_next,
  output logic        if_id_valid_next,
  output logic [31:0] if_id_pc_next,
  output logic [31:0] if_id_instr_next
);
  always_comb begin
    pc_next = pc_current;
    if (branch_taken)
      pc_next = branch_target;
    else if (!stall)
      pc_next = pc_current + 32'd4;

    if_id_valid_next = if_id_valid_current;
    if_id_pc_next = if_id_pc_current;
    if_id_instr_next = if_id_instr_current;

    if (branch_taken) begin
      if_id_valid_next = 1'b0;
      if_id_pc_next = 32'h0;
      if_id_instr_next = NOP;
    end else if (!stall) begin
      if_id_valid_next = !quiesce_req;
      if_id_pc_next = pc_current;
      if_id_instr_next = quiesce_req ? NOP : instr_fetch;
    end
  end
endmodule

// -----------------------------------------------------------------------------
// Architectural register-file write guard. The same guard is used by the
// register-file sequential block and formally checked for x0 protection.
// -----------------------------------------------------------------------------
module riscv_register_file_write_guard #(
  parameter integer ADDR_WIDTH = 5
) (
  input  logic                  wr_en,
  input  logic [ADDR_WIDTH-1:0] wr_addr,
  output logic                  accepted_write_en
);
  assign accepted_write_en = wr_en && (wr_addr != '0);
endmodule

// -----------------------------------------------------------------------------
// Architectural register file. x0 reads are hardwired to zero.
// This exact module is instantiated by riscv_pipeline and formally checked.
// -----------------------------------------------------------------------------
module riscv_register_file #(
  parameter integer DATA_WIDTH = 32,
  parameter integer ADDR_WIDTH = 5
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  wr_en,
  input  logic [ADDR_WIDTH-1:0] wr_addr,
  input  logic [DATA_WIDTH-1:0] wr_data,
  input  logic [ADDR_WIDTH-1:0] rs1_addr,
  input  logic [ADDR_WIDTH-1:0] rs2_addr,
  output logic [DATA_WIDTH-1:0] rs1_data,
  output logic [DATA_WIDTH-1:0] rs2_data,
  output logic [DATA_WIDTH-1:0] x0_value
);
  logic [DATA_WIDTH-1:0] regs [0:(1 << ADDR_WIDTH)-1];
  logic accepted_write_en;
  integer rf_i;

  riscv_register_file_write_guard #(.ADDR_WIDTH(ADDR_WIDTH)) u_write_guard (
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .accepted_write_en(accepted_write_en)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (rf_i = 0; rf_i < (1 << ADDR_WIDTH); rf_i = rf_i + 1)
        regs[rf_i] <= '0;
    end else begin
      if (accepted_write_en)
        regs[wr_addr] <= wr_data;
      regs[0] <= '0;
    end
  end

  assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];
  assign x0_value = regs[0];
endmodule

// -----------------------------------------------------------------------------
// Word-addressed CPU data memory. Byte address bits [1:0] are ignored, matching
// the original CPU RTL. Out-of-range reads return X and writes are discarded.
// -----------------------------------------------------------------------------
module riscv_data_memory #(
  parameter integer DEPTH = 1024,
  parameter integer WORD_INDEX_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH)
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        wr_en,
  input  logic [31:0] wr_addr,
  input  logic [31:0] wr_data,
  input  logic [31:0] rd_addr,
  output logic [31:0] rd_data
);
  logic [31:0] words [0:DEPTH-1];
  integer mem_i;

  initial begin
    for (mem_i = 0; mem_i < DEPTH; mem_i = mem_i + 1)
      words[mem_i] = 32'h0;
  end

  always @(posedge clk) begin
    if (rst_n && wr_en && (wr_addr[31:2] < DEPTH))
      words[wr_addr[WORD_INDEX_WIDTH+1:2]] <= wr_data;
  end

  always_comb begin
    rd_data = 32'hxxxx_xxxx;
    if (rd_addr[31:2] < DEPTH)
      rd_data = words[rd_addr[WORD_INDEX_WIDTH+1:2]];
  end
endmodule

// -----------------------------------------------------------------------------
// Reusable CPU pipeline control units.
// These modules are instantiated by riscv_pipeline and directly targeted by
// the SymbiYosys formal harness under formal/.
// -----------------------------------------------------------------------------
module riscv_load_use_hazard_unit #(
  parameter [6:0] OPCODE_R      = 7'b0110011,
  parameter [6:0] OPCODE_I      = 7'b0010011,
  parameter [6:0] OPCODE_LOAD   = 7'b0000011,
  parameter [6:0] OPCODE_STORE  = 7'b0100011,
  parameter [6:0] OPCODE_BRANCH = 7'b1100011,
  parameter [6:0] OPCODE_JALR   = 7'b1100111
) (
  input  logic       id_ex_valid,
  input  logic       id_ex_mem_read,
  input  logic [4:0] id_ex_rd,
  input  logic       if_id_valid,
  input  logic [6:0] if_id_opcode,
  input  logic [4:0] if_id_rs1,
  input  logic [4:0] if_id_rs2,
  output logic       stall
);
  always_comb begin
    stall = 1'b0;
    if (id_ex_valid && id_ex_mem_read && (id_ex_rd != 5'd0) && if_id_valid) begin
      unique case (if_id_opcode)
        OPCODE_R, OPCODE_STORE, OPCODE_BRANCH:
          stall = (if_id_rs1 == id_ex_rd) || (if_id_rs2 == id_ex_rd);
        OPCODE_I, OPCODE_LOAD, OPCODE_JALR:
          stall = (if_id_rs1 == id_ex_rd);
        default:
          stall = 1'b0;
      endcase
    end
  end
endmodule

module riscv_forwarding_unit (
  input  logic [4:0]  rs1,
  input  logic [4:0]  rs2,
  input  logic [31:0] rs1_base_value,
  input  logic [31:0] rs2_base_value,
  input  logic        mem_wb_valid,
  input  logic        mem_wb_reg_we,
  input  logic [4:0]  mem_wb_rd,
  input  logic [31:0] mem_wb_wdata,
  input  logic        ex_mem_valid,
  input  logic        ex_mem_reg_we,
  input  logic        ex_mem_mem_read,
  input  logic [4:0]  ex_mem_rd,
  input  logic [31:0] ex_mem_alu_result,
  output logic [31:0] fwd_rs1_value,
  output logic [31:0] fwd_rs2_value
);
  // Apply the older MEM/WB value first; a newer eligible EX/MEM value
  // overrides it. x0 never forwards and loads wait for the MEM result.
  always_comb begin
    fwd_rs1_value = rs1_base_value;
    fwd_rs2_value = rs2_base_value;

    if (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd != 5'd0)) begin
      if (mem_wb_rd == rs1) fwd_rs1_value = mem_wb_wdata;
      if (mem_wb_rd == rs2) fwd_rs2_value = mem_wb_wdata;
    end

    if (ex_mem_valid && ex_mem_reg_we && !ex_mem_mem_read &&
        (ex_mem_rd != 5'd0)) begin
      if (ex_mem_rd == rs1) fwd_rs1_value = ex_mem_alu_result;
      if (ex_mem_rd == rs2) fwd_rs2_value = ex_mem_alu_result;
    end
  end
endmodule

// -----------------------------------------------------------------------------
// 5-stage RV32I pipeline RTL for verification portfolio project
// Stages: IF, ID, EX, MEM, WB
// Notes:
// - Educational RTL, intentionally compact and easy to verify.
// - Instruction memory is loaded by the UVM driver using instr_load_* signals.
// - Data memory is internal and word-addressed through byte addresses.
// - Commit/debug signals are exposed for the UVM monitor and scoreboard.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module riscv_pipeline #(
  parameter int IMEM_WORDS = 1024,
  parameter int DMEM_WORDS = 1024
)(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        quiesce_req,

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
  output logic        pipeline_empty
);

  localparam logic [31:0] NOP = 32'h0000_0013; // ADDI x0,x0,0

  localparam logic [6:0] OPCODE_R      = 7'b0110011;
  localparam logic [6:0] OPCODE_I      = 7'b0010011;
  localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
  localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
  localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
  localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
  localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
  localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
  localparam logic [6:0] OPCODE_JALR   = 7'b1100111;

  typedef enum logic [4:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_AND,
    ALU_OR,
    ALU_XOR,
    ALU_SLL,
    ALU_SRL,
    ALU_SRA,
    ALU_SLT,
    ALU_SLTU,
    ALU_COPY_B
  } alu_op_e;

  logic [31:0] imem [0:IMEM_WORDS-1];
  logic [31:0] rf_rs1_data, rf_rs2_data, rf_x0_value;
  logic [31:0] dmem_rdata;

  // Initialize memories for deterministic simulation.
  // Unused instruction memory locations are NOPs so the core does not fetch X values.
  initial begin
    for (int init_i = 0; init_i < IMEM_WORDS; init_i++) begin
      imem[init_i] = NOP;
    end
  end

  logic [31:0] pc_q, pc_d;

  // IF/ID
  logic        if_id_valid_q, if_id_valid_d;
  logic [31:0] if_id_pc_q,    if_id_pc_d;
  logic [31:0] if_id_instr_q, if_id_instr_d;

  // ID/EX
  logic        id_ex_valid_q, id_ex_valid_d;
  logic [31:0] id_ex_pc_q, id_ex_pc_d;
  logic [31:0] id_ex_instr_q, id_ex_instr_d;
  logic [4:0]  id_ex_rs1_q, id_ex_rs1_d;
  logic [4:0]  id_ex_rs2_q, id_ex_rs2_d;
  logic [4:0]  id_ex_rd_q,  id_ex_rd_d;
  logic [31:0] id_ex_rs1_val_q, id_ex_rs1_val_d;
  logic [31:0] id_ex_rs2_val_q, id_ex_rs2_val_d;
  logic [31:0] id_ex_imm_q, id_ex_imm_d;
  logic [2:0]  id_ex_funct3_q, id_ex_funct3_d;
  logic [6:0]  id_ex_funct7_q, id_ex_funct7_d;
  logic [6:0]  id_ex_opcode_q, id_ex_opcode_d;
  alu_op_e     id_ex_alu_op_q, id_ex_alu_op_d;
  logic        id_ex_alu_src_imm_q, id_ex_alu_src_imm_d;
  logic        id_ex_reg_we_q, id_ex_reg_we_d;
  logic        id_ex_mem_read_q, id_ex_mem_read_d;
  logic        id_ex_mem_write_q, id_ex_mem_write_d;
  logic        id_ex_branch_q, id_ex_branch_d;
  logic        id_ex_jump_q, id_ex_jump_d;
  logic        id_ex_lui_q, id_ex_lui_d;
  logic        id_ex_auipc_q, id_ex_auipc_d;

  // EX/MEM
  logic        ex_mem_valid_q, ex_mem_valid_d;
  logic [31:0] ex_mem_pc_q, ex_mem_pc_d;
  logic [31:0] ex_mem_instr_q, ex_mem_instr_d;
  logic [4:0]  ex_mem_rd_q, ex_mem_rd_d;
  logic [31:0] ex_mem_alu_result_q, ex_mem_alu_result_d;
  logic [31:0] ex_mem_rs2_val_q, ex_mem_rs2_val_d;
  logic        ex_mem_reg_we_q, ex_mem_reg_we_d;
  logic        ex_mem_mem_read_q, ex_mem_mem_read_d;
  logic        ex_mem_mem_write_q, ex_mem_mem_write_d;
  logic        ex_mem_jump_q, ex_mem_jump_d;

  // MEM/WB
  logic        mem_wb_valid_q, mem_wb_valid_d;
  logic [31:0] mem_wb_pc_q, mem_wb_pc_d;
  logic [31:0] mem_wb_instr_q, mem_wb_instr_d;
  logic [4:0]  mem_wb_rd_q, mem_wb_rd_d;
  logic [31:0] mem_wb_wdata_q, mem_wb_wdata_d;
  logic        mem_wb_reg_we_q, mem_wb_reg_we_d;
  logic        mem_wb_mem_we_q, mem_wb_mem_we_d;
  logic [31:0] mem_wb_mem_addr_q, mem_wb_mem_addr_d;
  logic [31:0] mem_wb_mem_wdata_q, mem_wb_mem_wdata_d;

  logic [31:0] instr_f;
  logic [31:0] wb_wdata;
  logic        wb_write_en;

  // Decode wires
  logic [6:0]  dec_opcode;
  logic [4:0]  dec_rs1, dec_rs2, dec_rd;
  logic [2:0]  dec_funct3;
  logic [6:0]  dec_funct7;
  logic [31:0] dec_imm_i, dec_imm_s, dec_imm_b, dec_imm_u, dec_imm_j;

  // EX wires
  logic [31:0] fwd_rs1_val;
  logic [31:0] fwd_rs2_val;
  logic [31:0] dec_rs1_val_byp;
  logic [31:0] dec_rs2_val_byp;
  logic [31:0] id_ex_result_byp;
  logic [31:0] alu_in_a;
  logic [31:0] alu_in_b;
  logic [31:0] alu_result;
  logic        branch_cond_true;
  logic        branch_taken_ex;
  logic [31:0] branch_target_ex;

  assign ready = 1'b1;
  assign pc_dbg = pc_q;
  assign if_id_pc_dbg = if_id_pc_q;
  assign if_id_instr_dbg = if_id_instr_q;
  assign pipeline_empty = !(if_id_valid_q || id_ex_valid_q ||
                             ex_mem_valid_q || mem_wb_valid_q);

  assign dec_opcode = if_id_instr_q[6:0];
  assign dec_rd     = if_id_instr_q[11:7];
  assign dec_funct3 = if_id_instr_q[14:12];
  assign dec_rs1    = if_id_instr_q[19:15];
  assign dec_rs2    = if_id_instr_q[24:20];
  assign dec_funct7 = if_id_instr_q[31:25];

  assign dec_imm_i = {{20{if_id_instr_q[31]}}, if_id_instr_q[31:20]};
  assign dec_imm_s = {{20{if_id_instr_q[31]}}, if_id_instr_q[31:25], if_id_instr_q[11:7]};
  assign dec_imm_b = {{19{if_id_instr_q[31]}}, if_id_instr_q[31], if_id_instr_q[7], if_id_instr_q[30:25], if_id_instr_q[11:8], 1'b0};
  assign dec_imm_u = {if_id_instr_q[31:12], 12'b0};
  assign dec_imm_j = {{11{if_id_instr_q[31]}}, if_id_instr_q[31], if_id_instr_q[19:12], if_id_instr_q[20], if_id_instr_q[30:21], 1'b0};

  assign instr_f = imem[pc_q[31:2]];

  // Reusable load-use interlock and forwarding units.
  riscv_load_use_hazard_unit #(
    .OPCODE_R(OPCODE_R),
    .OPCODE_I(OPCODE_I),
    .OPCODE_LOAD(OPCODE_LOAD),
    .OPCODE_STORE(OPCODE_STORE),
    .OPCODE_BRANCH(OPCODE_BRANCH),
    .OPCODE_JALR(OPCODE_JALR)
  ) u_load_use_hazard (
    .id_ex_valid(id_ex_valid_q),
    .id_ex_mem_read(id_ex_mem_read_q),
    .id_ex_rd(id_ex_rd_q),
    .if_id_valid(if_id_valid_q),
    .if_id_opcode(dec_opcode),
    .if_id_rs1(dec_rs1),
    .if_id_rs2(dec_rs2),
    .stall(stall)
  );

  riscv_forwarding_unit u_forwarding (
    .rs1(id_ex_rs1_q),
    .rs2(id_ex_rs2_q),
    .rs1_base_value(id_ex_rs1_val_q),
    .rs2_base_value(id_ex_rs2_val_q),
    .mem_wb_valid(mem_wb_valid_q),
    .mem_wb_reg_we(mem_wb_reg_we_q),
    .mem_wb_rd(mem_wb_rd_q),
    .mem_wb_wdata(mem_wb_wdata_q),
    .ex_mem_valid(ex_mem_valid_q),
    .ex_mem_reg_we(ex_mem_reg_we_q),
    .ex_mem_mem_read(ex_mem_mem_read_q),
    .ex_mem_rd(ex_mem_rd_q),
    .ex_mem_alu_result(ex_mem_alu_result_q),
    .fwd_rs1_value(fwd_rs1_val),
    .fwd_rs2_value(fwd_rs2_val)
  );

  assign alu_in_a = id_ex_auipc_q ? id_ex_pc_q : fwd_rs1_val;
  assign alu_in_b = (id_ex_alu_src_imm_q || id_ex_lui_q || id_ex_auipc_q) ? id_ex_imm_q : fwd_rs2_val;

  always_comb begin
    unique case (id_ex_alu_op_q)
      ALU_ADD:    alu_result = alu_in_a + alu_in_b;
      ALU_SUB:    alu_result = alu_in_a - alu_in_b;
      ALU_AND:    alu_result = alu_in_a & alu_in_b;
      ALU_OR:     alu_result = alu_in_a | alu_in_b;
      ALU_XOR:    alu_result = alu_in_a ^ alu_in_b;
      ALU_SLL:    alu_result = alu_in_a << alu_in_b[4:0];
      ALU_SRL:    alu_result = alu_in_a >> alu_in_b[4:0];
      ALU_SRA:    alu_result = $signed(alu_in_a) >>> alu_in_b[4:0];
      ALU_SLT:    alu_result = ($signed(alu_in_a) < $signed(alu_in_b)) ? 32'd1 : 32'd0;
      ALU_SLTU:   alu_result = (alu_in_a < alu_in_b) ? 32'd1 : 32'd0;
      ALU_COPY_B: alu_result = alu_in_b;
      default:    alu_result = 32'h0;
    endcase
  end

  always_comb begin
    branch_cond_true = 1'b0;
    unique case (id_ex_funct3_q)
      3'b000: branch_cond_true = (fwd_rs1_val == fwd_rs2_val);                 // BEQ
      3'b001: branch_cond_true = (fwd_rs1_val != fwd_rs2_val);                 // BNE
      3'b100: branch_cond_true = ($signed(fwd_rs1_val) < $signed(fwd_rs2_val)); // BLT
      3'b101: branch_cond_true = ($signed(fwd_rs1_val) >= $signed(fwd_rs2_val));// BGE
      3'b110: branch_cond_true = (fwd_rs1_val < fwd_rs2_val);                  // BLTU
      3'b111: branch_cond_true = (fwd_rs1_val >= fwd_rs2_val);                 // BGEU
      default: branch_cond_true = 1'b0;
    endcase
  end

  always_comb begin
    branch_taken_ex  = 1'b0;
    branch_target_ex = 32'h0;

    if (id_ex_valid_q && id_ex_branch_q && branch_cond_true) begin
      branch_taken_ex  = 1'b1;
      branch_target_ex = id_ex_pc_q + id_ex_imm_q;
    end else if (id_ex_valid_q && id_ex_jump_q) begin
      branch_taken_ex  = 1'b1;
      if (id_ex_opcode_q == OPCODE_JALR) begin
        branch_target_ex = (fwd_rs1_val + id_ex_imm_q) & 32'hFFFF_FFFE;
      end else begin
        branch_target_ex = id_ex_pc_q + id_ex_imm_q;
      end
    end
  end

  assign branch_taken = branch_taken_ex;

  // PC redirect, stall hold, IF/ID flush and quiesce behavior are
  // factored into a reusable unit with a sequential formal harness.
  riscv_fetch_control_unit #(.NOP(NOP)) u_fetch_control (
    .pc_current(pc_q),
    .instr_fetch(instr_f),
    .stall(stall),
    .branch_taken(branch_taken_ex),
    .branch_target(branch_target_ex),
    .quiesce_req(quiesce_req),
    .if_id_valid_current(if_id_valid_q),
    .if_id_pc_current(if_id_pc_q),
    .if_id_instr_current(if_id_instr_q),
    .pc_next(pc_d),
    .if_id_valid_next(if_id_valid_d),
    .if_id_pc_next(if_id_pc_d),
    .if_id_instr_next(if_id_instr_d)
  );

  // Decode-stage operand bypass.
  // Besides normal EX-stage forwarding, preload ID/EX operand values with the
  // newest visible producer. Seed 10 exposed a case where two back-to-back
  // instructions wrote x7 and the consumer had to see the youngest writer.
  // Priority: current ID/EX ALU result > EX/MEM ALU result > MEM/WB > RF.
  assign id_ex_result_byp = id_ex_jump_q ? (id_ex_pc_q + 32'd4) : alu_result;

  always_comb begin
    dec_rs1_val_byp = rf_rs1_data;
    dec_rs2_val_byp = rf_rs2_data;

    if (wb_write_en && (mem_wb_rd_q != 5'd0)) begin
      if (mem_wb_rd_q == dec_rs1) dec_rs1_val_byp = wb_wdata;
      if (mem_wb_rd_q == dec_rs2) dec_rs2_val_byp = wb_wdata;
    end

    if (ex_mem_valid_q && ex_mem_reg_we_q && !ex_mem_mem_read_q && (ex_mem_rd_q != 5'd0)) begin
      if (ex_mem_rd_q == dec_rs1) dec_rs1_val_byp = ex_mem_alu_result_q;
      if (ex_mem_rd_q == dec_rs2) dec_rs2_val_byp = ex_mem_alu_result_q;
    end

    if (id_ex_valid_q && id_ex_reg_we_q && !id_ex_mem_read_q && (id_ex_rd_q != 5'd0)) begin
      if (id_ex_rd_q == dec_rs1) dec_rs1_val_byp = id_ex_result_byp;
      if (id_ex_rd_q == dec_rs2) dec_rs2_val_byp = id_ex_result_byp;
    end
  end

  // ID/EX decode next state
  always_comb begin
    id_ex_valid_d       = if_id_valid_q && !stall && !branch_taken_ex;
    id_ex_pc_d          = if_id_pc_q;
    id_ex_instr_d       = if_id_instr_q;
    id_ex_rs1_d         = dec_rs1;
    id_ex_rs2_d         = dec_rs2;
    id_ex_rd_d          = dec_rd;
    id_ex_rs1_val_d     = dec_rs1_val_byp;
    id_ex_rs2_val_d     = dec_rs2_val_byp;
    id_ex_imm_d         = 32'h0;
    id_ex_funct3_d      = dec_funct3;
    id_ex_funct7_d      = dec_funct7;
    id_ex_opcode_d      = dec_opcode;
    id_ex_alu_op_d      = ALU_ADD;
    id_ex_alu_src_imm_d = 1'b0;
    id_ex_reg_we_d      = 1'b0;
    id_ex_mem_read_d    = 1'b0;
    id_ex_mem_write_d   = 1'b0;
    id_ex_branch_d      = 1'b0;
    id_ex_jump_d        = 1'b0;
    id_ex_lui_d         = 1'b0;
    id_ex_auipc_d       = 1'b0;

    if (stall || branch_taken_ex) begin
      id_ex_valid_d = 1'b0;
      id_ex_instr_d = NOP;
    end else begin
      unique case (dec_opcode)
        OPCODE_R: begin
          id_ex_reg_we_d = 1'b1;
          unique case ({dec_funct7, dec_funct3})
            {7'b0000000,3'b000}: id_ex_alu_op_d = ALU_ADD;
            {7'b0100000,3'b000}: id_ex_alu_op_d = ALU_SUB;
            {7'b0000000,3'b111}: id_ex_alu_op_d = ALU_AND;
            {7'b0000000,3'b110}: id_ex_alu_op_d = ALU_OR;
            {7'b0000000,3'b100}: id_ex_alu_op_d = ALU_XOR;
            {7'b0000000,3'b001}: id_ex_alu_op_d = ALU_SLL;
            {7'b0000000,3'b101}: id_ex_alu_op_d = ALU_SRL;
            {7'b0100000,3'b101}: id_ex_alu_op_d = ALU_SRA;
            {7'b0000000,3'b010}: id_ex_alu_op_d = ALU_SLT;
            {7'b0000000,3'b011}: id_ex_alu_op_d = ALU_SLTU;
            default: begin
              id_ex_reg_we_d = 1'b0;
              id_ex_valid_d  = 1'b0;
            end
          endcase
        end

        OPCODE_I: begin
          id_ex_reg_we_d      = 1'b1;
          id_ex_alu_src_imm_d = 1'b1;
          id_ex_imm_d         = dec_imm_i;
          unique case (dec_funct3)
            3'b000: id_ex_alu_op_d = ALU_ADD;  // ADDI
            3'b111: id_ex_alu_op_d = ALU_AND;  // ANDI
            3'b110: id_ex_alu_op_d = ALU_OR;   // ORI
            3'b100: id_ex_alu_op_d = ALU_XOR;  // XORI
            3'b010: id_ex_alu_op_d = ALU_SLT;  // SLTI
            3'b011: id_ex_alu_op_d = ALU_SLTU; // SLTIU
            3'b001: id_ex_alu_op_d = ALU_SLL;  // SLLI
            3'b101: begin
              if (dec_funct7[5])
                id_ex_alu_op_d = ALU_SRA;
              else
                id_ex_alu_op_d = ALU_SRL;
            end
            default: id_ex_alu_op_d = ALU_ADD;
          endcase
        end

        OPCODE_LOAD: begin
          id_ex_reg_we_d      = 1'b1;
          id_ex_mem_read_d    = 1'b1;
          id_ex_alu_src_imm_d = 1'b1;
          id_ex_imm_d         = dec_imm_i;
          id_ex_alu_op_d      = ALU_ADD;
        end

        OPCODE_STORE: begin
          id_ex_mem_write_d   = 1'b1;
          id_ex_alu_src_imm_d = 1'b1;
          id_ex_imm_d         = dec_imm_s;
          id_ex_alu_op_d      = ALU_ADD;
        end

        OPCODE_BRANCH: begin
          id_ex_branch_d = 1'b1;
          id_ex_imm_d    = dec_imm_b;
        end

        OPCODE_LUI: begin
          id_ex_reg_we_d      = 1'b1;
          id_ex_lui_d         = 1'b1;
          id_ex_alu_src_imm_d = 1'b1;
          id_ex_imm_d         = dec_imm_u;
          id_ex_alu_op_d      = ALU_COPY_B;
        end

        OPCODE_AUIPC: begin
          id_ex_reg_we_d      = 1'b1;
          id_ex_auipc_d       = 1'b1;
          id_ex_alu_src_imm_d = 1'b1;
          id_ex_imm_d         = dec_imm_u;
          id_ex_alu_op_d      = ALU_ADD;
        end

        OPCODE_JAL: begin
          id_ex_reg_we_d = 1'b1;
          id_ex_jump_d   = 1'b1;
          id_ex_imm_d    = dec_imm_j;
        end

        OPCODE_JALR: begin
          id_ex_reg_we_d      = 1'b1;
          id_ex_jump_d        = 1'b1;
          id_ex_alu_src_imm_d = 1'b1;
          id_ex_imm_d         = dec_imm_i;
        end

        default: begin
          id_ex_valid_d = 1'b0;
          id_ex_instr_d = NOP;
        end
      endcase
    end
  end

  // EX/MEM next state
  always_comb begin
    ex_mem_valid_d      = id_ex_valid_q;
    ex_mem_pc_d         = id_ex_pc_q;
    ex_mem_instr_d      = id_ex_instr_q;
    ex_mem_rd_d         = id_ex_rd_q;
    ex_mem_alu_result_d = id_ex_jump_q ? (id_ex_pc_q + 32'd4) : alu_result;
    ex_mem_rs2_val_d    = fwd_rs2_val;
    ex_mem_reg_we_d     = id_ex_reg_we_q && (id_ex_rd_q != 5'd0);
    ex_mem_mem_read_d   = id_ex_mem_read_q;
    ex_mem_mem_write_d  = id_ex_mem_write_q;
    ex_mem_jump_d       = id_ex_jump_q;
  end

  // MEM/WB next state
  always_comb begin
    mem_wb_valid_d     = ex_mem_valid_q;
    mem_wb_pc_d        = ex_mem_pc_q;
    mem_wb_instr_d     = ex_mem_instr_q;
    mem_wb_rd_d        = ex_mem_rd_q;
    mem_wb_reg_we_d    = ex_mem_reg_we_q;
    mem_wb_mem_we_d    = ex_mem_valid_q && ex_mem_mem_write_q;
    mem_wb_mem_addr_d  = ex_mem_alu_result_q;
    mem_wb_mem_wdata_d = ex_mem_rs2_val_q;

    if (ex_mem_mem_read_q) begin
      mem_wb_wdata_d = dmem_rdata;
    end else begin
      mem_wb_wdata_d = ex_mem_alu_result_q;
    end
  end

  assign wb_write_en = mem_wb_valid_q && mem_wb_reg_we_q && (mem_wb_rd_q != 5'd0);
  assign wb_wdata    = mem_wb_wdata_q;

  riscv_register_file u_register_file (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(wb_write_en),
    .wr_addr(mem_wb_rd_q),
    .wr_data(wb_wdata),
    .rs1_addr(dec_rs1),
    .rs2_addr(dec_rs2),
    .rs1_data(rf_rs1_data),
    .rs2_data(rf_rs2_data),
    .x0_value(rf_x0_value)
  );

  riscv_data_memory #(.DEPTH(DMEM_WORDS)) u_data_memory (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(ex_mem_valid_q && ex_mem_mem_write_q),
    .wr_addr(ex_mem_alu_result_q),
    .wr_data(ex_mem_rs2_val_q),
    .rd_addr(ex_mem_alu_result_q),
    .rd_data(dmem_rdata)
  );

  // Sequential state
  // Questa enforces single-driver rules on always_ff variables.
  // This educational EDA Playground version keeps memory initialization in an
  // initial block and program/data writes in this clocked block, so use a
  // standard clocked always block instead of always_ff.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Allow the testbench/UVM driver to preload instruction memory while reset is active.
      if (instr_load_en) begin
        imem[instr_load_addr[31:2]] <= instr_load_data;
      end

      pc_q <= 32'h0;

      if_id_valid_q <= 1'b0;
      if_id_pc_q    <= 32'h0;
      if_id_instr_q <= NOP;

      id_ex_valid_q       <= 1'b0;
      id_ex_pc_q          <= 32'h0;
      id_ex_instr_q       <= NOP;
      id_ex_rs1_q         <= 5'd0;
      id_ex_rs2_q         <= 5'd0;
      id_ex_rd_q          <= 5'd0;
      id_ex_rs1_val_q     <= 32'h0;
      id_ex_rs2_val_q     <= 32'h0;
      id_ex_imm_q         <= 32'h0;
      id_ex_funct3_q      <= 3'd0;
      id_ex_funct7_q      <= 7'd0;
      id_ex_opcode_q      <= 7'd0;
      id_ex_alu_op_q      <= ALU_ADD;
      id_ex_alu_src_imm_q <= 1'b0;
      id_ex_reg_we_q      <= 1'b0;
      id_ex_mem_read_q    <= 1'b0;
      id_ex_mem_write_q   <= 1'b0;
      id_ex_branch_q      <= 1'b0;
      id_ex_jump_q        <= 1'b0;
      id_ex_lui_q         <= 1'b0;
      id_ex_auipc_q       <= 1'b0;

      ex_mem_valid_q      <= 1'b0;
      ex_mem_pc_q         <= 32'h0;
      ex_mem_instr_q      <= NOP;
      ex_mem_rd_q         <= 5'd0;
      ex_mem_alu_result_q <= 32'h0;
      ex_mem_rs2_val_q    <= 32'h0;
      ex_mem_reg_we_q     <= 1'b0;
      ex_mem_mem_read_q   <= 1'b0;
      ex_mem_mem_write_q  <= 1'b0;
      ex_mem_jump_q       <= 1'b0;

      mem_wb_valid_q     <= 1'b0;
      mem_wb_pc_q        <= 32'h0;
      mem_wb_instr_q     <= NOP;
      mem_wb_rd_q        <= 5'd0;
      mem_wb_wdata_q     <= 32'h0;
      mem_wb_reg_we_q    <= 1'b0;
      mem_wb_mem_we_q    <= 1'b0;
      mem_wb_mem_addr_q  <= 32'h0;
      mem_wb_mem_wdata_q <= 32'h0;

    end else begin
      if (instr_load_en) begin
        imem[instr_load_addr[31:2]] <= instr_load_data;
      end

      pc_q <= pc_d;

      if_id_valid_q <= if_id_valid_d;
      if_id_pc_q    <= if_id_pc_d;
      if_id_instr_q <= if_id_instr_d;

      id_ex_valid_q       <= id_ex_valid_d;
      id_ex_pc_q          <= id_ex_pc_d;
      id_ex_instr_q       <= id_ex_instr_d;
      id_ex_rs1_q         <= id_ex_rs1_d;
      id_ex_rs2_q         <= id_ex_rs2_d;
      id_ex_rd_q          <= id_ex_rd_d;
      id_ex_rs1_val_q     <= id_ex_rs1_val_d;
      id_ex_rs2_val_q     <= id_ex_rs2_val_d;
      id_ex_imm_q         <= id_ex_imm_d;
      id_ex_funct3_q      <= id_ex_funct3_d;
      id_ex_funct7_q      <= id_ex_funct7_d;
      id_ex_opcode_q      <= id_ex_opcode_d;
      id_ex_alu_op_q      <= id_ex_alu_op_d;
      id_ex_alu_src_imm_q <= id_ex_alu_src_imm_d;
      id_ex_reg_we_q      <= id_ex_reg_we_d;
      id_ex_mem_read_q    <= id_ex_mem_read_d;
      id_ex_mem_write_q   <= id_ex_mem_write_d;
      id_ex_branch_q      <= id_ex_branch_d;
      id_ex_jump_q        <= id_ex_jump_d;
      id_ex_lui_q         <= id_ex_lui_d;
      id_ex_auipc_q       <= id_ex_auipc_d;

      ex_mem_valid_q      <= ex_mem_valid_d;
      ex_mem_pc_q         <= ex_mem_pc_d;
      ex_mem_instr_q      <= ex_mem_instr_d;
      ex_mem_rd_q         <= ex_mem_rd_d;
      ex_mem_alu_result_q <= ex_mem_alu_result_d;
      ex_mem_rs2_val_q    <= ex_mem_rs2_val_d;
      ex_mem_reg_we_q     <= ex_mem_reg_we_d;
      ex_mem_mem_read_q   <= ex_mem_mem_read_d;
      ex_mem_mem_write_q  <= ex_mem_mem_write_d;
      ex_mem_jump_q       <= ex_mem_jump_d;

      mem_wb_valid_q     <= mem_wb_valid_d;
      mem_wb_pc_q        <= mem_wb_pc_d;
      mem_wb_instr_q     <= mem_wb_instr_d;
      mem_wb_rd_q        <= mem_wb_rd_d;
      mem_wb_wdata_q     <= mem_wb_wdata_d;
      mem_wb_reg_we_q    <= mem_wb_reg_we_d;
      mem_wb_mem_we_q    <= mem_wb_mem_we_d;
      mem_wb_mem_addr_q  <= mem_wb_mem_addr_d;
      mem_wb_mem_wdata_q <= mem_wb_mem_wdata_d;
    end
  end

  // Commit signals are emitted from MEM/WB, the architectural commit point.
  assign commit_valid     = mem_wb_valid_q;
  assign commit_pc        = mem_wb_pc_q;
  assign commit_instr     = mem_wb_instr_q;
  assign commit_rd        = mem_wb_rd_q;
  assign commit_wdata     = mem_wb_wdata_q;
  assign commit_reg_we    = mem_wb_valid_q && mem_wb_reg_we_q && (mem_wb_rd_q != 5'd0);
  assign commit_mem_we    = mem_wb_valid_q && mem_wb_mem_we_q;
  assign commit_mem_addr  = mem_wb_mem_addr_q;
  assign commit_mem_wdata = mem_wb_mem_wdata_q;

endmodule
