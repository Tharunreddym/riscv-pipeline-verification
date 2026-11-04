// Formal harnesses for the exact units instantiated by the CPU RTL.
// Symbolic inputs are unconstrained: proofs cover all input bit combinations.

module riscv_load_use_formal;
  (* gclk *) reg formal_timestep;

  (* anyconst *) reg       id_ex_valid;
  (* anyconst *) reg       id_ex_mem_read;
  (* anyconst *) reg [4:0] id_ex_rd;
  (* anyconst *) reg       if_id_valid;
  (* anyconst *) reg [6:0] if_id_opcode;
  (* anyconst *) reg [4:0] if_id_rs1;
  (* anyconst *) reg [4:0] if_id_rs2;

  wire stall;
  riscv_load_use_hazard_unit dut (
    .id_ex_valid(id_ex_valid),
    .id_ex_mem_read(id_ex_mem_read),
    .id_ex_rd(id_ex_rd),
    .if_id_valid(if_id_valid),
    .if_id_opcode(if_id_opcode),
    .if_id_rs1(if_id_rs1),
    .if_id_rs2(if_id_rs2),
    .stall(stall)
  );

  wire two_source_opcode = (if_id_opcode == 7'b0110011) ||
                           (if_id_opcode == 7'b0100011) ||
                           (if_id_opcode == 7'b1100011);
  wire one_source_opcode = (if_id_opcode == 7'b0010011) ||
                           (if_id_opcode == 7'b0000011) ||
                           (if_id_opcode == 7'b1100111);
  wire expected_stall = id_ex_valid && id_ex_mem_read && (id_ex_rd != 5'd0) &&
                        if_id_valid &&
                        ((two_source_opcode &&
                          ((if_id_rs1 == id_ex_rd) || (if_id_rs2 == id_ex_rd))) ||
                         (one_source_opcode && (if_id_rs1 == id_ex_rd)));

  always @(posedge formal_timestep) begin
    assert(stall == expected_stall);
    assert(!stall || (id_ex_valid && id_ex_mem_read &&
                      (id_ex_rd != 5'd0) && if_id_valid));
    assert(!stall || two_source_opcode || one_source_opcode);

    cover(stall && two_source_opcode && (if_id_rs2 == id_ex_rd) &&
          (if_id_rs1 != id_ex_rd));
    cover(stall && one_source_opcode && (if_id_rs1 == id_ex_rd));
    cover(!stall && id_ex_valid && id_ex_mem_read && if_id_valid &&
          (id_ex_rd != 5'd0) && (if_id_rs1 != id_ex_rd) &&
          (if_id_rs2 != id_ex_rd));
    cover(!stall && (id_ex_rd == 5'd0) && if_id_valid);
  end
endmodule

module riscv_forwarding_formal;
  (* gclk *) reg formal_timestep;

  (* anyconst *) reg [4:0]  rs1;
  (* anyconst *) reg [4:0]  rs2;
  (* anyconst *) reg [31:0] rs1_base_value;
  (* anyconst *) reg [31:0] rs2_base_value;
  (* anyconst *) reg        mem_wb_valid;
  (* anyconst *) reg        mem_wb_reg_we;
  (* anyconst *) reg [4:0]  mem_wb_rd;
  (* anyconst *) reg [31:0] mem_wb_wdata;
  (* anyconst *) reg        ex_mem_valid;
  (* anyconst *) reg        ex_mem_reg_we;
  (* anyconst *) reg        ex_mem_mem_read;
  (* anyconst *) reg [4:0]  ex_mem_rd;
  (* anyconst *) reg [31:0] ex_mem_alu_result;

  wire [31:0] fwd_rs1_value;
  wire [31:0] fwd_rs2_value;
  wire mem_wb_rs1_match = mem_wb_valid && mem_wb_reg_we &&
                          (mem_wb_rd != 5'd0) && (mem_wb_rd == rs1);
  wire mem_wb_rs2_match = mem_wb_valid && mem_wb_reg_we &&
                          (mem_wb_rd != 5'd0) && (mem_wb_rd == rs2);
  wire ex_mem_eligible = ex_mem_valid && ex_mem_reg_we &&
                         !ex_mem_mem_read && (ex_mem_rd != 5'd0);
  wire ex_mem_rs1_match = ex_mem_eligible && (ex_mem_rd == rs1);
  wire ex_mem_rs2_match = ex_mem_eligible && (ex_mem_rd == rs2);

  wire [31:0] expected_rs1 = ex_mem_rs1_match ? ex_mem_alu_result :
                             mem_wb_rs1_match ? mem_wb_wdata : rs1_base_value;
  wire [31:0] expected_rs2 = ex_mem_rs2_match ? ex_mem_alu_result :
                             mem_wb_rs2_match ? mem_wb_wdata : rs2_base_value;

  riscv_forwarding_unit dut (
    .rs1(rs1),
    .rs2(rs2),
    .rs1_base_value(rs1_base_value),
    .rs2_base_value(rs2_base_value),
    .mem_wb_valid(mem_wb_valid),
    .mem_wb_reg_we(mem_wb_reg_we),
    .mem_wb_rd(mem_wb_rd),
    .mem_wb_wdata(mem_wb_wdata),
    .ex_mem_valid(ex_mem_valid),
    .ex_mem_reg_we(ex_mem_reg_we),
    .ex_mem_mem_read(ex_mem_mem_read),
    .ex_mem_rd(ex_mem_rd),
    .ex_mem_alu_result(ex_mem_alu_result),
    .fwd_rs1_value(fwd_rs1_value),
    .fwd_rs2_value(fwd_rs2_value)
  );

  always @(posedge formal_timestep) begin
    assert(fwd_rs1_value == expected_rs1);
    assert(fwd_rs2_value == expected_rs2);
    assert(!(ex_mem_rs1_match && mem_wb_rs1_match) ||
           (fwd_rs1_value == ex_mem_alu_result));
    assert(!(ex_mem_rs2_match && mem_wb_rs2_match) ||
           (fwd_rs2_value == ex_mem_alu_result));
    assert(!(ex_mem_valid && ex_mem_reg_we && ex_mem_mem_read &&
             (ex_mem_rd != 5'd0) && (ex_mem_rd == rs1) && !mem_wb_rs1_match) ||
           (fwd_rs1_value == rs1_base_value));
    assert(!(ex_mem_valid && ex_mem_reg_we && ex_mem_mem_read &&
             (ex_mem_rd != 5'd0) && (ex_mem_rd == rs2) && !mem_wb_rs2_match) ||
           (fwd_rs2_value == rs2_base_value));

    cover(ex_mem_rs1_match && mem_wb_rs1_match);
    cover(ex_mem_rs2_match && mem_wb_rs2_match);
    cover(mem_wb_rs1_match && !ex_mem_rs1_match);
    cover(ex_mem_rs1_match && !mem_wb_rs1_match);
    cover(rs1 == 5'd0 && mem_wb_valid && mem_wb_reg_we &&
          (mem_wb_rd == 5'd0) && (fwd_rs1_value == rs1_base_value));
  end
endmodule
