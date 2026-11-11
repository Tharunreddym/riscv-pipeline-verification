// -----------------------------------------------------------------------------
// EDA Playground single-file testbench for RISC-V pipeline verification
// Paste this entire file into testbench.sv.
// -----------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// RISC-V pipeline verification interface
// -----------------------------------------------------------------------------

interface riscv_if(input logic clk);
  logic rst_n;

  logic        instr_load_en;
  logic [31:0] instr_load_addr;
  logic [31:0] instr_load_data;

  logic        ready;
  logic [31:0] pc_dbg;
  logic        stall;
  logic        branch_taken;

  logic        commit_valid;
  logic [31:0] commit_pc;
  logic [31:0] commit_instr;
  logic [4:0]  commit_rd;
  logic [31:0] commit_wdata;
  logic        commit_reg_we;
  logic        commit_mem_we;
  logic [31:0] commit_mem_addr;
  logic [31:0] commit_mem_wdata;

  logic [31:0] if_id_pc_dbg;
  logic [31:0] if_id_instr_dbg;

  clocking drv_cb @(posedge clk);
    output instr_load_en, instr_load_addr, instr_load_data;
    input  ready, stall;
  endclocking

  clocking mon_cb @(posedge clk);
    input rst_n;
    input ready, stall, branch_taken, pc_dbg;
    input commit_valid, commit_pc, commit_instr, commit_rd, commit_wdata;
    input commit_reg_we, commit_mem_we, commit_mem_addr, commit_mem_wdata;
    input if_id_pc_dbg, if_id_instr_dbg;
  endclocking

  modport drv_mp(clocking drv_cb, input rst_n);
  modport mon_mp(clocking mon_cb);
endinterface

// -----------------------------------------------------------------------------
// SystemVerilog Assertions for RISC-V pipeline
// -----------------------------------------------------------------------------

module riscv_assertions(
  input logic        clk,
  input logic        rst_n,
  input logic        stall,
  input logic        branch_taken,
  input logic [31:0] pc_dbg,
  input logic [31:0] if_id_pc_dbg,
  input logic [31:0] if_id_instr_dbg,
  input logic        commit_valid,
  input logic        commit_reg_we,
  input logic [4:0]  commit_rd,
  input logic [31:0] commit_wdata
);

  property no_write_x0;
    @(posedge clk) disable iff (!rst_n)
      commit_valid && commit_reg_we |-> (commit_rd != 5'd0);
  endproperty

  property stall_holds_pc;
    @(posedge clk) disable iff (!rst_n)
      stall |=> $stable(pc_dbg);
  endproperty

  property stall_holds_if_id;
    @(posedge clk) disable iff (!rst_n)
      stall |=> ($stable(if_id_pc_dbg) && $stable(if_id_instr_dbg));
  endproperty

  property pc_increments_without_branch_or_stall;
    @(posedge clk) disable iff (!rst_n)
      ($past(rst_n) && !stall && !branch_taken) |=> (pc_dbg == $past(pc_dbg) + 32'd4);
  endproperty

  property writeback_not_unknown;
    @(posedge clk) disable iff (!rst_n)
      commit_valid && commit_reg_we |-> !$isunknown(commit_wdata);
  endproperty

  a_no_write_x0: assert property(no_write_x0)
    else $error("SVA no_write_x0 failed");

  a_stall_holds_pc: assert property(stall_holds_pc)
    else $error("SVA stall_holds_pc failed");

  a_stall_holds_if_id: assert property(stall_holds_if_id)
    else $error("SVA stall_holds_if_id failed");

  a_pc_increments_without_branch_or_stall: assert property(pc_increments_without_branch_or_stall)
    else $error("SVA pc_increments_without_branch_or_stall failed");

  a_writeback_not_unknown: assert property(writeback_not_unknown)
    else $error("SVA writeback_not_unknown failed");

endmodule

package riscv_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {
    R_TYPE,
    I_TYPE,
    LOAD_TYPE,
    STORE_TYPE,
    BRANCH_TYPE,
    U_TYPE,
    J_TYPE
  } instr_type_e;

// -----------------------------------------------------------------------------
// Sequence item and commit transaction definitions
// -----------------------------------------------------------------------------
class riscv_seq_item extends uvm_sequence_item;
  `uvm_object_utils(riscv_seq_item)

  rand instr_type_e instr_type;
  rand bit [4:0] rs1;
  rand bit [4:0] rs2;
  rand bit [4:0] rd;
  rand bit [2:0] funct3;
  rand bit [6:0] funct7;
  rand bit [11:0] imm12;
  rand bit [19:0] imm20;
  rand bit [31:0] instr;

  constraint valid_regs_c {
    rs1 inside {[0:31]};
    rs2 inside {[0:31]};
    rd  inside {[1:31]};
  }

  constraint type_dist_c {
    instr_type dist {
      R_TYPE      := 25,
      I_TYPE      := 25,
      LOAD_TYPE   := 10,
      STORE_TYPE  := 10,
      BRANCH_TYPE := 15,
      U_TYPE      := 8,
      J_TYPE      := 7
    };
  }

  function new(string name = "riscv_seq_item");
    super.new(name);
  endfunction

  function void post_randomize();
    unique case (instr_type)
      R_TYPE: begin
        bit [3:0] sel = $urandom_range(0, 9);
        unique case (sel)
          0: begin funct7 = 7'b0000000; funct3 = 3'b000; end // ADD
          1: begin funct7 = 7'b0100000; funct3 = 3'b000; end // SUB
          2: begin funct7 = 7'b0000000; funct3 = 3'b111; end // AND
          3: begin funct7 = 7'b0000000; funct3 = 3'b110; end // OR
          4: begin funct7 = 7'b0000000; funct3 = 3'b100; end // XOR
          5: begin funct7 = 7'b0000000; funct3 = 3'b001; end // SLL
          6: begin funct7 = 7'b0000000; funct3 = 3'b101; end // SRL
          7: begin funct7 = 7'b0100000; funct3 = 3'b101; end // SRA
          8: begin funct7 = 7'b0000000; funct3 = 3'b010; end // SLT
          default: begin funct7 = 7'b0000000; funct3 = 3'b011; end // SLTU
        endcase
        instr = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
      end

      I_TYPE: begin
        bit [2:0] sel = $urandom_range(0, 5);
        unique case (sel)
          0: funct3 = 3'b000; // ADDI
          1: funct3 = 3'b111; // ANDI
          2: funct3 = 3'b110; // ORI
          3: funct3 = 3'b100; // XORI
          4: funct3 = 3'b010; // SLTI
          default: funct3 = 3'b011; // SLTIU
        endcase
        instr = {imm12, rs1, funct3, rd, 7'b0010011};
      end

      LOAD_TYPE: begin
        funct3 = 3'b010; // LW
        imm12[1:0] = 2'b00;
        instr = {imm12, rs1, funct3, rd, 7'b0000011};
      end

      STORE_TYPE: begin
        funct3 = 3'b010; // SW
        imm12[1:0] = 2'b00;
        instr = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], 7'b0100011};
      end

      BRANCH_TYPE: begin
        bit [12:0] bimm;
        funct3 = ($urandom_range(0, 1) == 0) ? 3'b000 : 3'b001; // BEQ/BNE
        bimm = {imm12[11], imm12[10:0], 1'b0};
        bimm[0] = 1'b0;
        instr = {bimm[12], bimm[10:5], rs2, rs1, funct3, bimm[4:1], bimm[11], 7'b1100011};
      end

      U_TYPE: begin
        if ($urandom_range(0, 1))
          instr = {imm20, rd, 7'b0110111}; // LUI
        else
          instr = {imm20, rd, 7'b0010111}; // AUIPC
      end

      J_TYPE: begin
        bit [20:0] jimm;
        jimm = {imm20, 1'b0};
        instr = {jimm[20], jimm[10:1], jimm[11], jimm[19:12], rd, 7'b1101111};
      end
    endcase
  endfunction

  function string convert2string();
    return $sformatf("type=%s instr=0x%08h rd=x%0d rs1=x%0d rs2=x%0d", instr_type.name(), instr, rd, rs1, rs2);
  endfunction
endclass

class riscv_commit_item extends uvm_sequence_item;
  `uvm_object_utils(riscv_commit_item)

  bit        valid;
  bit [31:0] pc;
  bit [31:0] instr;
  bit [4:0]  rd;
  bit [31:0] wdata;
  bit        reg_we;
  bit        mem_we;
  bit [31:0] mem_addr;
  bit [31:0] mem_wdata;

  function new(string name = "riscv_commit_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("pc=0x%08h instr=0x%08h reg_we=%0b rd=x%0d wdata=0x%08h mem_we=%0b mem_addr=0x%08h mem_wdata=0x%08h",
                     pc, instr, reg_we, rd, wdata, mem_we, mem_addr, mem_wdata);
  endfunction
endclass

// -----------------------------------------------------------------------------
// UVM driver: loads instruction stream into DUT instruction memory
// -----------------------------------------------------------------------------
class riscv_driver extends uvm_driver #(riscv_seq_item);
  `uvm_component_utils(riscv_driver)

  virtual riscv_if vif;
  int unsigned instr_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", "virtual interface must be set for riscv_driver")
    end
  endfunction

  task reset_dut();
    vif.instr_load_en   <= 1'b0;
    vif.instr_load_addr <= '0;
    vif.instr_load_data <= 32'h0000_0013;
    repeat (2) @(posedge vif.clk);
  endtask

  task load_instr(input int unsigned index, input bit [31:0] instr);
    @(posedge vif.clk);
    vif.instr_load_en   <= 1'b1;
    vif.instr_load_addr <= index * 4;
    vif.instr_load_data <= instr;
    @(posedge vif.clk);
    vif.instr_load_en   <= 1'b0;
    vif.instr_load_addr <= '0;
    vif.instr_load_data <= 32'h0000_0013;
  endtask

  task run_phase(uvm_phase phase);
    riscv_seq_item item;    instr_count = 0;
    reset_dut();

    forever begin
      seq_item_port.get_next_item(item);
      `uvm_info("DRV", $sformatf("Loading instruction[%0d]: %s", instr_count, item.convert2string()), UVM_MEDIUM)
      load_instr(instr_count, item.instr);
      instr_count++;
      seq_item_port.item_done();
    end
  endtask
endclass

// -----------------------------------------------------------------------------
// UVM monitor: captures committed instructions from MEM/WB
// -----------------------------------------------------------------------------
class riscv_monitor extends uvm_component;
  `uvm_component_utils(riscv_monitor)

  virtual riscv_if vif;
  uvm_analysis_port #(riscv_commit_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", "virtual interface must be set for riscv_monitor")
    end
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n && vif.commit_valid) begin
        riscv_commit_item tr = riscv_commit_item::type_id::create("tr");
        tr.valid     = vif.commit_valid;
        tr.pc        = vif.commit_pc;
        tr.instr     = vif.commit_instr;
        tr.rd        = vif.commit_rd;
        tr.wdata     = vif.commit_wdata;
        tr.reg_we    = vif.commit_reg_we;
        tr.mem_we    = vif.commit_mem_we;
        tr.mem_addr  = vif.commit_mem_addr;
        tr.mem_wdata = vif.commit_mem_wdata;
        `uvm_info("MON", tr.convert2string(), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask
endclass

// -----------------------------------------------------------------------------
// UVM scoreboard: SystemVerilog-only golden model for EDA Playground bring-up
// This avoids C++ DPI link setup for the first simulation pass.
// -----------------------------------------------------------------------------
class riscv_scoreboard extends uvm_component;
  `uvm_component_utils(riscv_scoreboard)

  uvm_analysis_imp #(riscv_commit_item, riscv_scoreboard) analysis_export;

  bit [31:0] regs [0:31];
  bit [31:0] mem  [0:1023];
  bit [31:0] model_pc;
  int unsigned checked_count;
  int unsigned mismatch_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysis_export = new("analysis_export", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reset_model();
  endfunction

  function void reset_model();
    foreach (regs[i]) regs[i] = 32'h0;
    foreach (mem[i])  mem[i]  = 32'h0;
    model_pc = 32'h0;
    checked_count = 0;
    mismatch_count = 0;
  endfunction

  function automatic bit [31:0] sext(input bit [31:0] value, input int bits);
    bit [31:0] mask;
    begin
      mask = 32'hFFFF_FFFF << bits;
      if (value[bits-1]) sext = value | mask;
      else               sext = value & ~mask;
    end
  endfunction

  function automatic bit [31:0] imm_i(input bit [31:0] instr);
    return {{20{instr[31]}}, instr[31:20]};
  endfunction

  function automatic bit [31:0] imm_s(input bit [31:0] instr);
    return {{20{instr[31]}}, instr[31:25], instr[11:7]};
  endfunction

  function automatic bit [31:0] imm_b(input bit [31:0] instr);
    return {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  endfunction

  function automatic bit [31:0] imm_u(input bit [31:0] instr);
    return {instr[31:12], 12'b0};
  endfunction

  function automatic bit [31:0] imm_j(input bit [31:0] instr);
    return {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
  endfunction

  function automatic void model_step(
    input  bit [31:0] instr,
    input  bit [31:0] pc,
    output bit        exp_reg_we,
    output bit [4:0]  exp_rd,
    output bit [31:0] exp_wdata,
    output bit        exp_mem_we,
    output bit [31:0] exp_mem_addr,
    output bit [31:0] exp_mem_wdata,
    output bit [31:0] exp_next_pc
  );
    bit [6:0] opcode;
    bit [2:0] funct3;
    bit [6:0] funct7;
    bit [4:0] rs1, rs2, rd;
    bit [31:0] a, b, shamt;
    bit branch_taken;

    opcode = instr[6:0];
    rd     = instr[11:7];
    funct3 = instr[14:12];
    rs1    = instr[19:15];
    rs2    = instr[24:20];
    funct7 = instr[31:25];
    a      = (rs1 == 0) ? 32'h0 : regs[rs1];
    b      = (rs2 == 0) ? 32'h0 : regs[rs2];
    shamt  = instr[24:20];

    exp_reg_we    = 1'b0;
    exp_rd        = rd;
    exp_wdata     = 32'h0;
    exp_mem_we    = 1'b0;
    exp_mem_addr  = 32'h0;
    exp_mem_wdata = 32'h0;
    exp_next_pc   = pc + 32'd4;

    unique case (opcode)
      7'b0110011: begin // R-type
        exp_reg_we = (rd != 0);
        unique case ({funct7, funct3})
          {7'b0000000,3'b000}: exp_wdata = a + b;
          {7'b0100000,3'b000}: exp_wdata = a - b;
          {7'b0000000,3'b111}: exp_wdata = a & b;
          {7'b0000000,3'b110}: exp_wdata = a | b;
          {7'b0000000,3'b100}: exp_wdata = a ^ b;
          {7'b0000000,3'b001}: exp_wdata = a << b[4:0];
          {7'b0000000,3'b101}: exp_wdata = a >> b[4:0];
          {7'b0100000,3'b101}: exp_wdata = $signed(a) >>> b[4:0];
          {7'b0000000,3'b010}: exp_wdata = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
          {7'b0000000,3'b011}: exp_wdata = (a < b) ? 32'd1 : 32'd0;
          default: exp_reg_we = 1'b0;
        endcase
      end

      7'b0010011: begin // I-type ALU
        exp_reg_we = (rd != 0);
        unique case (funct3)
          3'b000: exp_wdata = a + imm_i(instr);                  // ADDI
          3'b111: exp_wdata = a & imm_i(instr);                  // ANDI
          3'b110: exp_wdata = a | imm_i(instr);                  // ORI
          3'b100: exp_wdata = a ^ imm_i(instr);                  // XORI
          3'b010: exp_wdata = ($signed(a) < $signed(imm_i(instr))) ? 32'd1 : 32'd0;
          3'b011: exp_wdata = (a < imm_i(instr)) ? 32'd1 : 32'd0;
          3'b001: exp_wdata = a << shamt[4:0];
          3'b101: exp_wdata = instr[30] ? ($signed(a) >>> shamt[4:0]) : (a >> shamt[4:0]);
          default: exp_reg_we = 1'b0;
        endcase
      end

      7'b0000011: begin // LOAD: LW only
        exp_mem_addr = a + imm_i(instr);
        exp_reg_we   = (rd != 0);
        exp_wdata    = mem[exp_mem_addr[31:2]];
      end

      7'b0100011: begin // STORE: SW only
        exp_mem_we    = 1'b1;
        exp_mem_addr  = a + imm_s(instr);
        exp_mem_wdata = b;
      end

      7'b1100011: begin // BRANCH
        branch_taken = 1'b0;
        unique case (funct3)
          3'b000: branch_taken = (a == b);
          3'b001: branch_taken = (a != b);
          3'b100: branch_taken = ($signed(a) < $signed(b));
          3'b101: branch_taken = ($signed(a) >= $signed(b));
          3'b110: branch_taken = (a < b);
          3'b111: branch_taken = (a >= b);
          default: branch_taken = 1'b0;
        endcase
        exp_next_pc = branch_taken ? (pc + imm_b(instr)) : (pc + 32'd4);
      end

      7'b0110111: begin // LUI
        exp_reg_we = (rd != 0);
        exp_wdata  = imm_u(instr);
      end

      7'b0010111: begin // AUIPC
        exp_reg_we = (rd != 0);
        exp_wdata  = pc + imm_u(instr);
      end

      7'b1101111: begin // JAL
        exp_reg_we  = (rd != 0);
        exp_wdata   = pc + 32'd4;
        exp_next_pc = pc + imm_j(instr);
      end

      7'b1100111: begin // JALR
        exp_reg_we  = (rd != 0);
        exp_wdata   = pc + 32'd4;
        exp_next_pc = (a + imm_i(instr)) & 32'hFFFF_FFFE;
      end

      default: begin
        exp_next_pc = pc + 32'd4;
      end
    endcase
  endfunction

  function void write(riscv_commit_item tr);
    bit exp_reg_we;
    bit [4:0] exp_rd;
    bit [31:0] exp_wdata;
    bit exp_mem_we;
    bit [31:0] exp_mem_addr;
    bit [31:0] exp_mem_wdata;
    bit [31:0] exp_next_pc;

    if (tr.instr == 32'h0000_0013) begin
      return; // ignore NOP commits after the directed program ends
    end

    if (tr.pc !== model_pc) begin
      mismatch_count++;
      `uvm_error("SB", $sformatf("PC mismatch: RTL pc=0x%08h EXP pc=0x%08h instr=0x%08h", tr.pc, model_pc, tr.instr))
    end

    model_step(tr.instr, tr.pc, exp_reg_we, exp_rd, exp_wdata, exp_mem_we, exp_mem_addr, exp_mem_wdata, exp_next_pc);
    checked_count++;

    if (tr.reg_we !== exp_reg_we) begin
      mismatch_count++;
      `uvm_error("SB", $sformatf("reg_we mismatch pc=0x%08h instr=0x%08h RTL=%0b EXP=%0b", tr.pc, tr.instr, tr.reg_we, exp_reg_we))
    end

    if (exp_reg_we) begin
      if (tr.rd !== exp_rd) begin
        mismatch_count++;
        `uvm_error("SB", $sformatf("rd mismatch pc=0x%08h instr=0x%08h RTL=x%0d EXP=x%0d", tr.pc, tr.instr, tr.rd, exp_rd))
      end
      if (tr.wdata !== exp_wdata) begin
        mismatch_count++;
        `uvm_error("SB", $sformatf("wdata mismatch pc=0x%08h instr=0x%08h RTL=0x%08h EXP=0x%08h", tr.pc, tr.instr, tr.wdata, exp_wdata))
      end
    end

    if (tr.mem_we !== exp_mem_we) begin
      mismatch_count++;
      `uvm_error("SB", $sformatf("mem_we mismatch pc=0x%08h instr=0x%08h RTL=%0b EXP=%0b", tr.pc, tr.instr, tr.mem_we, exp_mem_we))
    end

    if (exp_mem_we) begin
      if (tr.mem_addr !== exp_mem_addr) begin
        mismatch_count++;
        `uvm_error("SB", $sformatf("store address mismatch pc=0x%08h RTL=0x%08h EXP=0x%08h", tr.pc, tr.mem_addr, exp_mem_addr))
      end
      if (tr.mem_wdata !== exp_mem_wdata) begin
        mismatch_count++;
        `uvm_error("SB", $sformatf("store data mismatch pc=0x%08h RTL=0x%08h EXP=0x%08h", tr.pc, tr.mem_wdata, exp_mem_wdata))
      end
    end

    if (exp_mem_we) begin
      mem[exp_mem_addr[31:2]] = exp_mem_wdata;
    end
    if (exp_reg_we && exp_rd != 0) begin
      regs[exp_rd] = exp_wdata;
    end
    regs[0] = 32'h0;    model_pc = exp_next_pc;
  endfunction

  function void report_phase(uvm_phase phase);
    if (mismatch_count == 0) begin
      `uvm_info("SB", $sformatf("Scoreboard PASS: checked %0d committed instructions", checked_count), UVM_LOW)
    end else begin
      `uvm_error("SB", $sformatf("Scoreboard FAIL: %0d mismatches across %0d committed instructions", mismatch_count, checked_count))
    end
  endfunction
endclass

// -----------------------------------------------------------------------------
// Functional coverage for committed RV32I instructions
// -----------------------------------------------------------------------------
class riscv_coverage extends uvm_subscriber #(riscv_commit_item);
  `uvm_component_utils(riscv_coverage)

  bit [6:0] opcode;
  bit [2:0] funct3;
  bit [6:0] funct7;
  bit [4:0] rd;
  bit [4:0] rs1;
  bit [4:0] rs2;
  bit       reg_we;
  bit       mem_we;

  covergroup instr_cg;
    option.per_instance = 1;

    opcode_cp: coverpoint opcode {
      bins r_type   = {7'b0110011};
      bins i_type   = {7'b0010011};
      bins load     = {7'b0000011};
      bins store    = {7'b0100011};
      bins branch   = {7'b1100011};
      bins lui      = {7'b0110111};
      bins auipc    = {7'b0010111};
      bins jal      = {7'b1101111};
      bins jalr     = {7'b1100111};
    }

    funct3_cp: coverpoint funct3;
    funct7_cp: coverpoint funct7;
    rd_cp:     coverpoint rd  { bins regs[] = {[0:31]}; }
    rs1_cp:    coverpoint rs1 { bins regs[] = {[0:31]}; }
    rs2_cp:    coverpoint rs2 { bins regs[] = {[0:31]}; }
    reg_we_cp: coverpoint reg_we;
    mem_we_cp: coverpoint mem_we;

    opcode_x_funct3: cross opcode_cp, funct3_cp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    instr_cg = new();
  endfunction

  function void write(riscv_commit_item t);
    opcode = t.instr[6:0];
    rd     = t.instr[11:7];
    funct3 = t.instr[14:12];
    rs1    = t.instr[19:15];
    rs2    = t.instr[24:20];
    funct7 = t.instr[31:25];
    reg_we = t.reg_we;
    mem_we = t.mem_we;
    instr_cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("Instruction functional coverage = %0.2f%%", instr_cg.get_coverage()), UVM_LOW)
  endfunction
endclass

// -----------------------------------------------------------------------------
// UVM agent
// -----------------------------------------------------------------------------
class riscv_agent extends uvm_agent;
  `uvm_component_utils(riscv_agent)

  uvm_sequencer #(riscv_seq_item) sequencer;
  riscv_driver    driver;
  riscv_monitor   monitor;
  riscv_coverage  coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = uvm_sequencer#(riscv_seq_item)::type_id::create("sequencer", this);
    driver    = riscv_driver::type_id::create("driver", this);
    monitor   = riscv_monitor::type_id::create("monitor", this);
    coverage  = riscv_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
    monitor.ap.connect(coverage.analysis_export);
  endfunction
endclass

// -----------------------------------------------------------------------------
// UVM environment
// -----------------------------------------------------------------------------
class riscv_env extends uvm_env;
  `uvm_component_utils(riscv_env)

  riscv_agent      agent;
  riscv_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = riscv_agent::type_id::create("agent", this);
    scoreboard = riscv_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.ap.connect(scoreboard.analysis_export);
  endfunction
endclass

// -----------------------------------------------------------------------------
// RISC-V instruction sequences
// -----------------------------------------------------------------------------
class riscv_base_sequence extends uvm_sequence #(riscv_seq_item);
  `uvm_object_utils(riscv_base_sequence)

  int unsigned count = 1000;

  function new(string name = "riscv_base_sequence");
    super.new(name);
  endfunction

  task send_instr(bit [31:0] instr);
    riscv_seq_item item = riscv_seq_item::type_id::create("item");
    start_item(item);
    item.instr = instr;
    finish_item(item);
  endtask

  function bit [31:0] enc_r(bit [6:0] funct7, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] funct3, bit [4:0] rd);
    return {funct7, rs2, rs1, funct3, rd, 7'b0110011};
  endfunction

  function bit [31:0] enc_i(bit signed [11:0] imm, bit [4:0] rs1, bit [2:0] funct3, bit [4:0] rd, bit [6:0] opcode = 7'b0010011);
    return {imm[11:0], rs1, funct3, rd, opcode};
  endfunction

  function bit [31:0] enc_s(bit signed [11:0] imm, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] funct3);
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
  endfunction

  function bit [31:0] enc_b(bit signed [12:0] imm, bit [4:0] rs2, bit [4:0] rs1, bit [2:0] funct3);
    return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 7'b1100011};
  endfunction
endclass

class alu_sequence extends riscv_base_sequence;
  `uvm_object_utils(alu_sequence)
  function new(string name = "alu_sequence"); super.new(name); endfunction

  task body();
    send_instr(enc_i(12'd5,  5'd0, 3'b000, 5'd1)); // addi x1,x0,5
    send_instr(enc_i(12'd10, 5'd0, 3'b000, 5'd2)); // addi x2,x0,10
    send_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3)); // add x3,x1,x2
    send_instr(enc_r(7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4)); // sub x4,x3,x1
    send_instr(enc_r(7'b0000000, 5'd4, 5'd3, 3'b111, 5'd5)); // and
    send_instr(enc_r(7'b0000000, 5'd4, 5'd3, 3'b110, 5'd6)); // or
    send_instr(enc_r(7'b0000000, 5'd4, 5'd3, 3'b100, 5'd7)); // xor
  endtask
endclass

class load_store_sequence extends riscv_base_sequence;
  `uvm_object_utils(load_store_sequence)
  function new(string name = "load_store_sequence"); super.new(name); endfunction

  task body();
    send_instr(enc_i(12'd64, 5'd0, 3'b000, 5'd1)); // base address
    send_instr(enc_i(12'd99, 5'd0, 3'b000, 5'd2)); // data
    send_instr(enc_s(12'd0, 5'd2, 5'd1, 3'b010));  // sw x2,0(x1)
    send_instr(enc_i(12'd0, 5'd1, 3'b010, 5'd3, 7'b0000011)); // lw x3,0(x1)
    send_instr(enc_r(7'b0000000, 5'd2, 5'd3, 3'b000, 5'd4)); // add x4,x3,x2
  endtask
endclass

class branch_sequence extends riscv_base_sequence;
  `uvm_object_utils(branch_sequence)
  function new(string name = "branch_sequence"); super.new(name); endfunction

  task body();
    send_instr(enc_i(12'd5, 5'd0, 3'b000, 5'd1));
    send_instr(enc_i(12'd5, 5'd0, 3'b000, 5'd2));
    send_instr(enc_b(13'd8, 5'd2, 5'd1, 3'b000)); // beq x1,x2,+8
    send_instr(enc_i(12'd1, 5'd0, 3'b000, 5'd3)); // should be flushed if branch taken
    send_instr(enc_i(12'd2, 5'd0, 3'b000, 5'd4));
    send_instr(enc_b(13'd8, 5'd4, 5'd3, 3'b001)); // bne x3,x4,+8
    send_instr(enc_i(12'd3, 5'd0, 3'b000, 5'd5));
    send_instr(enc_i(12'd4, 5'd0, 3'b000, 5'd6));
  endtask
endclass

class hazard_sequence extends riscv_base_sequence;
  `uvm_object_utils(hazard_sequence)
  function new(string name = "hazard_sequence"); super.new(name); endfunction

  task body();
    send_instr(enc_i(12'd3, 5'd0, 3'b000, 5'd1));
    send_instr(enc_i(12'd4, 5'd0, 3'b000, 5'd2));
    send_instr(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3)); // add x3,x1,x2
    send_instr(enc_r(7'b0100000, 5'd1, 5'd3, 3'b000, 5'd4)); // sub x4,x3,x1 forwarding
    send_instr(enc_r(7'b0000000, 5'd4, 5'd3, 3'b111, 5'd5)); // and x5,x3,x4 forwarding
    send_instr(enc_i(12'd128, 5'd0, 3'b000, 5'd10));
    send_instr(enc_s(12'd0, 5'd5, 5'd10, 3'b010));
    send_instr(enc_i(12'd0, 5'd10, 3'b010, 5'd11, 7'b0000011)); // lw x11,0(x10)
    send_instr(enc_r(7'b0000000, 5'd1, 5'd11, 3'b000, 5'd12)); // load-use stall expected
  endtask
endclass

class random_instruction_sequence extends riscv_base_sequence;
  `uvm_object_utils(random_instruction_sequence)
  function new(string name = "random_instruction_sequence"); super.new(name); endfunction

  task body();
    // EDA-friendly constrained random stream.
    // Keep random memory operations inside the small internal memory and avoid
    // random control-flow redirection so this test checks many committed ALU,
    // load, and store operations deterministically on EDA Playground.
    repeat (count) begin
      riscv_seq_item item = riscv_seq_item::type_id::create("item");
      start_item(item);
      if (!item.randomize() with {
        instr_type inside {R_TYPE, I_TYPE, LOAD_TYPE, STORE_TYPE};
        rd  inside {[1:31]};
        rs1 inside {[0:31]};
        rs2 inside {[0:31]};

        // Loads/stores use x0 as base plus a small aligned positive offset.
        // This prevents out-of-range data-memory reads from producing X values.
        (instr_type inside {LOAD_TYPE, STORE_TYPE}) ->
          (rs1 == 5'd0 && imm12 inside {[0:124]} && imm12[1:0] == 2'b00);

        // Keep ALU immediates small and positive for stable, readable results.
        (instr_type == I_TYPE) -> (imm12 inside {[0:255]});
      }) begin
        `uvm_error("SEQ", "Randomization failed")
      end
      finish_item(item);
    end
  endtask
endclass

endpackage

package riscv_tests_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import riscv_pkg::*;

// -----------------------------------------------------------------------------
// Base UVM test
// -----------------------------------------------------------------------------
class base_test extends uvm_test;
  `uvm_component_utils(base_test)

  riscv_env env;
  virtual riscv_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = riscv_env::type_id::create("env", this);
    if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", "virtual interface not found for test")
    end
  endfunction

  task run_phase(uvm_phase phase);
    alu_sequence seq;
    phase.raise_objection(this);
    seq = alu_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    wait (vif.rst_n === 1'b1);
    repeat (120) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------// Hazard-focused test
// -----------------------------------------------------------------------------
class hazard_test extends base_test;
  `uvm_component_utils(hazard_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    hazard_sequence seq;
    phase.raise_objection(this);
    seq = hazard_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    wait (vif.rst_n === 1'b1);
    repeat (160) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// Branch and flush-focused test
// -----------------------------------------------------------------------------
class branch_test extends base_test;
  `uvm_component_utils(branch_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    branch_sequence seq;
    phase.raise_objection(this);
    seq = branch_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    wait (vif.rst_n === 1'b1);
    repeat (160) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

// -----------------------------------------------------------------------------
// Constrained-random instruction test
// -----------------------------------------------------------------------------
class random_instruction_test extends base_test;
  `uvm_component_utils(random_instruction_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    random_instruction_sequence seq;
    phase.raise_objection(this);
    seq = random_instruction_sequence::type_id::create("seq");
    int unsigned drain_cycles;
    int unsigned drain_limit;
    void'(uvm_config_db#(int unsigned)::get(this, "", "random_count", seq.count));
    void'($value$plusargs("random_count=%d", seq.count));
    if (seq.count == 0) `uvm_fatal("RANDOM_COUNT", "random_count must be greater than zero")
    seq.start(env.agent.sequencer);
    wait (vif.rst_n === 1'b1);
    drain_cycles = 0;
    drain_limit  = (seq.count * 2) + 1000;
    while ((env.scoreboard.checked_count < seq.count) && (drain_cycles < drain_limit)) begin
      @(posedge vif.clk);
      drain_cycles++;
    end
    if (env.scoreboard.checked_count < seq.count)
      `uvm_fatal("INCOMPLETE_REGRESSION", $sformatf("Expected %0d committed instructions, checked %0d", seq.count, env.scoreboard.checked_count))
    `uvm_info("TEST", $sformatf("Completed %0d committed instructions in %0d drain cycles", env.scoreboard.checked_count, drain_cycles), UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

endpackage

// -----------------------------------------------------------------------------
// Top-level UVM testbench
// -----------------------------------------------------------------------------
module tb_top;
  import uvm_pkg::*;
  import riscv_pkg::*;
  import riscv_tests_pkg::*;

  logic clk;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  riscv_if rif(clk);

  riscv_pipeline dut (
    .clk              (clk),
    .rst_n            (rif.rst_n),
    .quiesce_req      (1'b0),
    .pipeline_empty   (),
    .instr_load_en    (rif.instr_load_en),
    .instr_load_addr  (rif.instr_load_addr),
    .instr_load_data  (rif.instr_load_data),
    .ready            (rif.ready),
    .pc_dbg           (rif.pc_dbg),
    .stall            (rif.stall),
    .branch_taken     (rif.branch_taken),
    .commit_valid     (rif.commit_valid),
    .commit_pc        (rif.commit_pc),
    .commit_instr     (rif.commit_instr),
    .commit_rd        (rif.commit_rd),
    .commit_wdata     (rif.commit_wdata),
    .commit_reg_we    (rif.commit_reg_we),
    .commit_mem_we    (rif.commit_mem_we),
    .commit_mem_addr  (rif.commit_mem_addr),
    .commit_mem_wdata (rif.commit_mem_wdata),
    .if_id_pc_dbg     (rif.if_id_pc_dbg),
    .if_id_instr_dbg  (rif.if_id_instr_dbg)
  );

  riscv_assertions u_assertions (
    .clk             (clk),
    .rst_n           (rif.rst_n),
    .stall           (rif.stall),
    .branch_taken    (rif.branch_taken),
    .pc_dbg          (rif.pc_dbg),
    .if_id_pc_dbg    (rif.if_id_pc_dbg),
    .if_id_instr_dbg (rif.if_id_instr_dbg),
    .commit_valid    (rif.commit_valid),
    .commit_reg_we   (rif.commit_reg_we),
    .commit_rd       (rif.commit_rd),
    .commit_wdata    (rif.commit_wdata)
  );

  initial begin
    rif.rst_n           = 1'b0;
    rif.instr_load_en   = 1'b0;
    rif.instr_load_addr = '0;
    rif.instr_load_data = 32'h0000_0013;

    // Hold reset until the random program has been completely preloaded.
    // Each instruction load takes two clock edges; include margin before release.
    int unsigned preload_count;
    string selected_test;
    if (!$value$plusargs("UVM_TESTNAME=%s", selected_test)) selected_test = "";
    if (selected_test == "random_instruction_test") begin
      if (!$value$plusargs("random_count=%d", preload_count)) preload_count = 1000;
      repeat ((2 * preload_count) + 200) @(posedge clk);
    end else begin
      repeat (120) @(posedge clk);
    end
    rif.rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual riscv_if)::set(null, "*", "vif", rif);
    run_test();
  end

  initial begin
    #200000;
    `uvm_fatal("TIMEOUT", "Simulation timeout")
  end
endmodule