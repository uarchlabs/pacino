# PERF-005 Phase 4: the pacino TAGE twin, an entry of the CBP framework
# copy under perf/build/twin_cbp (perf/Makefile twin). TWIN_INC is given
# on that make line: perf/src/twin and perf/src/harness (tage_hash.h).
ENTRY=pacino_twin
ENTRY_SRCS := \
  entries/$(ENTRY)/cond_branch_predictor_interface.cc

ENTRY_INCS := $(TWIN_INC)
