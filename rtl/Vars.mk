
VERILATOR ?=$(RVA_ROOT)/tools/bin/verilator
SPIKE     ?=$(RVA_ROOT)/tools/bin/spike
SURFER    ?=$(RVA_ROOT)/tools/bin/surfer

# EMBECOSM_BIN (BP-132, TD#176, TD#147): the bin directory of the
# Embecosm RISC-V toolchain, EMBECOSM_RELEASE, which is too large to be in
# the repository: clang for asm_dec_words (decode) and oracle_ifu_rvc_exp
# (ifu), llvm-objdump for oracle_ifu_rvc_exp, riscv64-unknown-elf-gcc and
# riscv64-unknown-elf-objdump for tools/Makefile.
# tools/check_embecosm.sh --build asks for the path of an existing install
# or installs the release into tools/, and saves the answer in
# tools/local.mk (not tracked). Without that file the default is the
# install in tools/. The environment or the make command line overrides
# both.
EMBECOSM_RELEASE := riscv-embecosm-embedded-ubuntu2204-20250309
-include $(RVA_ROOT)/tools/local.mk
EMBECOSM_BIN ?= $(RVA_ROOT)/tools/$(EMBECOSM_RELEASE)/bin

# $(call need_ext_tool,<target>,<tool>): a recipe line that fails, naming
# EMBECOSM_BIN, when <tool> is not an executable in that directory.
need_ext_tool = test -x $(EMBECOSM_BIN)/$(2) || { echo "$(1): $(2) not \
found in EMBECOSM_BIN=$(EMBECOSM_BIN); run tools/check_embecosm.sh \
--build" >&2; exit 1; }
