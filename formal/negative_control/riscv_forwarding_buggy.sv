// INTENTIONALLY BUGGY negative-control design.
// The older MEM/WB value is applied after the younger EX/MEM value and
// incorrectly overrides it when both stages write the same source register.

module riscv_forwarding_unit_buggy (
  input  logic [4:0]  rs1,
  input  logic [31:0] rs1_base_value,
  input  logic        mem_wb_valid,
  input  logic        mem_wb_reg_we,
  input  logic [4:0]  mem_wb_rd,
  input  logic [31:0] mem_wb_wdata,
  input  logic        ex_mem_valid,
  input  logic        ex_mem_reg_we,
  input  logic        ex_mem_mem_read,
  input  logic [4:0]  ex_mem_rd,
  input  logic [31:0] ex_mem_alu_result,
  output logic [31:0] fwd_rs1_value
);
  always_comb begin
    fwd_rs1_value = rs1_base_value;

    // Newer EX/MEM value is selected first.
    if (ex_mem_valid && ex_mem_reg_we && !ex_mem_mem_read &&
        (ex_mem_rd != 5'd0) && (ex_mem_rd == rs1))
      fwd_rs1_value = ex_mem_alu_result;

    // BUG: older MEM/WB assignment overrides the newer EX/MEM value.
    if (mem_wb_valid && mem_wb_reg_we &&
        (mem_wb_rd != 5'd0) && (mem_wb_rd == rs1))
      fwd_rs1_value = mem_wb_wdata;
  end
endmodule
