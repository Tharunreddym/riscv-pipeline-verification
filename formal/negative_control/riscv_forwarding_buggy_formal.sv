// Negative control: this expected-correct property must FAIL on the deliberately
// reversed-priority DUT and produce a counterexample trace.

module riscv_forwarding_buggy_formal;
  (* gclk *) reg formal_timestep;

  (* anyconst *) reg [4:0] rs1;
  (* anyconst *) reg [31:0] rs1_base_value;
  (* anyconst *) reg mem_wb_valid;
  (* anyconst *) reg mem_wb_reg_we;
  (* anyconst *) reg [4:0] mem_wb_rd;
  (* anyconst *) reg [31:0] mem_wb_wdata;
  (* anyconst *) reg ex_mem_valid;
  (* anyconst *) reg ex_mem_reg_we;
  (* anyconst *) reg ex_mem_mem_read;
  (* anyconst *) reg [4:0] ex_mem_rd;
  (* anyconst *) reg [31:0] ex_mem_alu_result;

  wire [31:0] fwd_rs1_value;
  wire mem_wb_match = mem_wb_valid && mem_wb_reg_we &&
                      (mem_wb_rd != 5'd0) && (mem_wb_rd == rs1);
  wire ex_mem_match = ex_mem_valid && ex_mem_reg_we && !ex_mem_mem_read &&
                      (ex_mem_rd != 5'd0) && (ex_mem_rd == rs1);
  wire [31:0] expected_rs1 = ex_mem_match ? ex_mem_alu_result :
                             mem_wb_match ? mem_wb_wdata : rs1_base_value;

  riscv_forwarding_unit_buggy dut (.*);

  always @(posedge formal_timestep) begin
    assert(fwd_rs1_value == expected_rs1);
    cover(ex_mem_match && mem_wb_match &&
          (ex_mem_alu_result != mem_wb_wdata));
  end
endmodule
