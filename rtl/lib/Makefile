# rtl/lib/Makefile
VERILATOR := $(shell which verilator 2>/dev/null)
ifeq ($(VERILATOR),)
  $(error [error] verilator not found. Install verilator before running make)
endif

ifeq ($(VERBOSE),1)
  Q :=
else
  Q :=
  MAKEFLAGS := -s --no-print-directory
endif

RTL_FILES = \
  ./rtl/bw_ram.sv \
  ./rtl/sat_alu.sv \
  ./rtl/dual_lm1.sv \
  ./rtl/sram_init.sv
TB_FILE  = tb/tb_components.sv
ALL_SV   = $(RTL_FILES) $(TB_FILE)
SIM_DIR  = obj_dir
VER_FLAGS = -Wall -Wno-DECLFILENAME -Wno-IMPORTSTAR -Wno-UNUSED \
  --timing

.PHONY: all sim lint clean

all: lint sim

sim: $(SIM_DIR)/Vtb
	@echo "[simulating] $(SIM_DIR)/Vtb"
	$(Q)$(SIM_DIR)/Vtb

$(SIM_DIR)/Vtb: $(ALL_SV)
	@for f in $(ALL_SV); do echo "[compiling]  $$f"; done
	$(Q)verilator --binary $(VER_FLAGS) \
	  -Mdir $(SIM_DIR) \
	  $(ALL_SV) \
	  --top-module tb

lint:
	@for f in $(ALL_SV); do echo "[linting]    $$f"; done
	$(Q)verilator --lint-only $(VER_FLAGS) \
	  $(ALL_SV) \
	  --top-module tb

clean:
	$(Q)rm -rf $(SIM_DIR) simv simv.daidir csrc \
	  *.log *.vpd *.vcd
