IVERILOG ?= iverilog
VVP ?= vvp
BUILD_DIR ?= build

.PHONY: test clean

test: $(BUILD_DIR)/riscv_pipeline_lp_tb
	$(VVP) $<

$(BUILD_DIR)/riscv_pipeline_lp_tb: ../eda_playground/design.sv riscv_pipeline_lp.sv tb/riscv_pipeline_lp_tb.sv
	mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -s riscv_pipeline_lp_tb -o $@ $^

clean:
	rm -rf $(BUILD_DIR)
