# rtl/lib/Makefile
# Prefer Verilator if available; fall back to VCS.

VERILATOR := $(shell which verilator 2>/dev/null)

RTL_FILES = \
  ./rtl/bw_ram.sv \
  ./rtl/sat_alu.sv \
  ./rtl/dual_lm1.sv \
  ./rtl/sram_init.sv

TB_FILE = tb/tb_components.sv
ALL_SV  = $(RTL_FILES) $(TB_FILE)
SIM_DIR = obj_dir

VER_FLAGS = -Wall -Wno-DECLFILENAME -Wno-IMPORTSTAR -Wno-UNUSED \
  --timing

.PHONY: sim lint clean

ifneq ($(VERILATOR),)

# ------- Verilator path -------
sim: $(SIM_DIR)/Vtb
	$(SIM_DIR)/Vtb

$(SIM_DIR)/Vtb: $(ALL_SV)
	verilator --binary $(VER_FLAGS) \
	  -Mdir $(SIM_DIR) \
	  $(ALL_SV) \
	  --top-module tb

lint:
	verilator --lint-only $(VER_FLAGS) \
	  $(ALL_SV) \
	  --top-module tb

else

# ------- VCS fallback -------
sim: simv
	./simv

simv: $(ALL_SV)
	vcs -sverilog -full64 \
	  $(ALL_SV) \
	  -top tb -o simv

lint:
	@echo "VCS lint: run 'make sim' for compile-time check"

endif

clean:
	rm -rf $(SIM_DIR) simv simv.daidir csrc \
	  *.log *.vpd *.vcd
