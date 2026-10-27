
VERILATOR ?=$(RVA_ROOT)/tools/bin/verilator
SPIKE     ?=$(RVA_ROOT)/tools/bin/spike
SURFER    ?=$(RVA_ROOT)/tools/bin/surfer

# RVA_EXT_TOOLS (BP-132, TD#176, TD#147): the directory of the needed
# tools that are not in the repository. Today that is the embecosm
# RISC-V toolchain, which is too large to be in it: clang for
# asm_dec_words (decode) and oracle_ifu_rvc_exp (ifu), and llvm-objdump
# for oracle_ifu_rvc_exp. Set it in the environment or on the make
# command line to use another directory.
RVA_EXT_TOOLS ?= /usr/local/riscv-embecosm-embedded-ubuntu2204-20250309/bin

# $(call need_ext_tool,<target>,<tool>): a recipe line that fails, naming
# RVA_EXT_TOOLS, when <tool> is not an executable in that directory.
need_ext_tool = test -x $(RVA_EXT_TOOLS)/$(2) || { echo "$(1): $(2) not \
found in RVA_EXT_TOOLS=$(RVA_EXT_TOOLS); set RVA_EXT_TOOLS (rtl/Vars.mk) \
to the directory that holds it" >&2; exit 1; }
