<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# SC Testbench Planning Decisions
```
 FILE:    sc_tb_decisions.md
 SOURCE:  session-058
 STATUS:  DRAFT
 UPDATED: 2026-07-01
 CONTACT: Jeff Nye
```

Scope: unit testbench for sc_table (ST0-ST3). The DUT is sc_table
instantiated directly, not through sc.sv. sc_brimli has a separate
testbench.

---

## DUT and Instantiation

- DUT: sc_table, instantiated once in tb_sc_table.sv as u_dut.
- The tb selects the table under test by setting the sc_table
  parameters (THIS_TABLE, THIS_INDEX_BITS, THIS_CTR_WIDTH,
  THIS_ENTRIES, THIS_FH) at instantiation from the SC_TBL_* arrays
  in bp_defines_pkg.sv.
- ST0-ST3 share one RTL module. A parameterized tb instance covers
  any of the four. Default instance: ST1 (hashed index, non-zero
  fold). ST0 (unhashed, fold tied zero) covered by a separate
  instance or a parameter override.
- tbl_ri_* are DUT input ports. The unit tb drives them directly.
  There is no sram_init instance and no sc_ready at this level;
  those live in sc.sv.

---

## Fast RAM Init

### Mechanism
- Plusarg name: SC_FAST_INIT (SC-scoped). Read in sc_table.sv via
  $value$plusargs.
- bw_ram.sv is not modified.

### Behavior
- SC_FAST_INIT=0 (default): the tb drives the tbl_ri_* override
  path to initialize the RAMs, walking address 0 to RAM_ENTRIES-1
  across both banks with tbl_ri_active=1, tbl_ri_wr=1,
  tbl_ri_wd=SC_SRAM_INIT_VALUE. sc_table has no internal sram_init;
  the sequencing is the tb's responsibility at this unit level.
- SC_FAST_INIT=1: the sc_table initial block writes the bw_ram mem
  arrays directly via hierarchical reference at time zero
  (sc_decisions.md section 13). The tb skips the tbl_ri init
  sequence.

### Initial block pattern (sc_table)
The mem array in bw_ram is 2D: mem[BANKS][ENTRIES]. The sc_table
initial block loops both dimensions and casts to ALLOC_DATA_WIDTH
(the SC counter width). This is in the RTL (sc_table.sv), not the
tb; the tb only chooses whether to pass +SC_FAST_INIT.

### SC_SRAM_INIT_VALUE
- localparam int in bp_defines_pkg.sv, value 0.
- Used by the sc_table fast-init block (SC_FAST_INIT=1) and by the
  tb-driven tbl_ri sequence (SC_FAST_INIT=0).

---

## Hierarchical References

- The tb reads RAM contents directly via hierarchical reference
  after initialization.
- sc_table instance paths (DUT instantiated directly as u_dut):
    u_dut.u_ram_s0.mem[b][i]
    u_dut.u_ram_s1.mem[b][i]
- bw_ram mem is 2D: mem[BANKS][ENTRIES]. All accesses use mem[b][i].
- NUM_BANKS=2. For ST0-ST3: RAM_ENTRIES = THIS_ENTRIES / 2 = 256.
  bank_addr = index[THIS_INDEX_BITS-1] = index[8];
  row = index[THIS_INDEX_BITS-2:0] = index[7:0].
- No generate-block prefix at this level (sc_table is the top DUT,
  not wrapped by sc.sv). Constant-index restriction does not force
  unrolling here; the two RAM instances are named, not generated.

---

## Test Structure Convention

- Per-test enable integer declared at top of tb module:
    int verbose = 1;
    int _testname = 1;
- Invocation pattern:
    if (_testname != 0) testname(ARGS, verbose);
- Use if (int_var != 0), not if (int_var), to avoid Verilator
  WIDTHTRUNC warnings.
- Self-checking. No manual waveform inspection. A basic sanity
  check runs under 10 seconds (CLAUDE.md).

---

## Test Coverage (sc_table operations)

The tb exercises the table operations. It does not test the
THIS_TABLE-range assert (unreachable for a valid instantiation).

### Init check
- After init (either mode), read all entries in both banks via
  hierarchical reference. Verify each equals SC_SRAM_INIT_VALUE.

### Prediction read (index hash)
- Rule source: sc_table_hash_rules.md (sc_idx_hash).
- Drive inp_pc_p2[s] and idx_fh_p2. Compute the expected index
  independently in the tb:
    exp_idx = THIS_INDEX_BITS'((pc >> INST_OFFSET) ^ fh_idx_ext)
  where fh_idx_ext = 0 for ST0, idx_fh_p2 for ST1-ST3.
- Verify idx_hash_p2[s] == exp_idx.
- Seed a known counter at exp_idx, deassert the write, read at p2
  the following cycle, verify ctr_p3[s] at p3 matches the seeded
  value. Prediction and update are phase-exclusive; seed and read
  occupy separate cycles.

### Update write
- Rule source: sc_decisions.md section 10 (counter write is a
  whole-word write of the supplied ctr_wd_u0 at upd_index_u0).
- Drive sc_upd_val_u0[s], ctr_wr_u0[s], upd_index_u0[s], ctr_wd_u0[s].
- Verify the addressed entry (both banks reachable) holds ctr_wd_u0
  via hierarchical reference. Verify no other entry changes.
- Verify no write when sc_upd_val_u0[s]=0 or ctr_wr_u0[s]=0.

### Slot independence
- Drive slot 0 and slot 1 with different indices and data in the
  same cycle. Verify each RAM (u_ram_s0, u_ram_s1) receives only
  its slot's transaction. No cross-slot interference.

### tbl_ri override
- Assert tbl_ri_active with a concurrent update request. Verify the
  tbl_ri address/data/enable win and the update is suppressed
  (sc_table.sv addr/din/wen muxes gate on tbl_ri_active).

### Bank decomposition
- Drive indices with index[THIS_INDEX_BITS-1]=0 and =1. Verify the
  entry lands in bank 0 and bank 1 respectively (mem[0][row],
  mem[1][row]).

---

## Makefile Conventions

- sim_sc_table: default, no +SC_FAST_INIT. The tb drives the
  tbl_ri init sequence.
- sim_sc_table_fast: passes +SC_FAST_INIT=1. sc_table initial block
  initializes; tb skips the tbl_ri sequence.
- Both targets must exit zero on PASS.
- Every Makefile target runs (CLAUDE.md ALL TARGETS MUST RUN).
  Report pass/fail per target from the current session.

---

## Deferred

- sc_brimli (ST4) testbench: separate task.
- Flush (_px) behavior: TD #96, not defined.
- sc.sv-level sram_init sequencing and sc_ready: tested at the
  sc.sv task, not here.

