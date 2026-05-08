# riscv-codesign/tools/Makefile
.PHONY: default clean

RV_TOOLS=/usr/local/riscv-embecosm-embedded-ubuntu2204-20250309
RCC=$(RV_TOOLS)/bin/riscv64-unknown-elf-gcc
ROBJD=$(RV_TOOLS)/bin/riscv64-unknown-elf-objdump

#OTHER=zicbop_zcb_zvkb
MARCH=-march=rv64imafdc_v_h_sscofpmf_sstc_svinval_svnapot_svpbmt_zawrs_zba_zbb_zbc_zbs_zfa_zfh_zfhmin_zicbom_zicboz_zicntr_zifencei_zicond_zihintntl_zihintpause_zihpm_zkt_zk_zkn_zknd_zkne_zknh_zbkb_zbkc_zbkx_zicbop_zcb_zvkb

MABI=-mabi=lp64d

RCC_OPTS=-DTEST_ALL -O0 -static

ROBJD_OPTS=-d -M no-aliases --show-raw-insn -x

default: 
	$(MAKE) clean
	$(MAKE) rva23_ext_test
	$(MAKE) rva23_insn_ref.o

rva23_ext_test: rva23_ext_test.c
	$(RCC) $(MARCH) $(MABI) $(RCC_OPTS) -o $@ $<
	$(ROBJD) $(ROBJD_OPTS) -x $@  > rva23_ext_test.disasm

rva23_insn_ref.o: rva23_insn_ref.c
	$(RCC) -c $(MARCH) $(MABI) $(RCC_OPTS) -o $@ $<
	$(ROBJD) $(ROBJD_OPTS) -x $@  > rva23_insn_ref.disasm

clean:
	-rm -f rva23_ext_test rva23_ext_test.disasm
	-rm -f rva23_insn_ref.o rva23_insn_ref.disasm
	-rm -f spike_oracle.csv

# ------------------------------------------------------------------
# spike-dasm oracle regression targets
# ------------------------------------------------------------------
SPIKE_DASM=spike/install/bin/spike-dasm

.PHONY: spike_oracle spike_check spike_all

spike_oracle:
	python3 gen_spike_oracle.py

spike_check: spike_oracle.csv
	python3 check_spike_decode.py

spike_all:
	$(MAKE) spike_oracle
	$(MAKE) spike_check
