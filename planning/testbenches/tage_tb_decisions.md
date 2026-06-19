<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# TAGE Testbench Planning Decisions
```
 FILE:    tage_tb_decisions.md
 SOURCE:  various
 STATUS:  NEEDS RE-VERIFICATION
 UPDATED: 2026-04-07
 CONTACT: Jeff Nye
```

---

## Fast RAM Init

### Mechanism
- Plusarg name: TAGE_FAST_INIT (tage-scoped, not generic)
- Read at runtime via $value$plusargs in tage_bim.sv,
  tage_table.sv, and tage.sv.
- bw_ram.sv is NOT modified. No initial block in bw_ram.

### Behavior
- TAGE_FAST_INIT=0 (default): sram_init sequences through
  all entries. tage_rdy asserts after no more than
  (1 << MAX_IDX_WIDTH) + 4 cycles from reset deassertion.
- TAGE_FAST_INIT=1: tage_bim and tage_table initial
  blocks write bw_ram mem arrays directly via
  hierarchical reference at time zero. tage.sv reads
  the plusarg and immediately asserts tage_rdy=1 and
  straps all tbl_ri_* signals to zero. sram_init is
  fully bypassed -- it elaborates but is disconnected.
  tage_rdy asserts on the first cycle after reset
  deasserts.

### tage.sv fast init behavior
When TAGE_FAST_INIT=1, tage.sv drives:
  tbl_ri_active = 1'b0  (sram_init output ignored)
  tbl_ri_wr     = 1'b0
  tbl_ri_wa     = '0
  tbl_ri_wd     = '0
  tage_rdy      = 1'b1  (immediate, not from sram_init)

When TAGE_FAST_INIT=0, tage.sv drives:
  tbl_ri_active = from sram_init
  tbl_ri_wr     = from sram_init
  tbl_ri_wa     = from sram_init
  tbl_ri_wd     = from sram_init
  tage_rdy      = tbl_ri_rdy (from sram_init)

tage.sv reads +TAGE_FAST_INIT into a logic register
fast_init_r via an initial block. All tbl_ri_* and
tage_rdy assignments are muxed on fast_init_r.

### Initial block pattern (tage_bim and tage_table)
The mem array in bw_ram is 2D: mem[BANKS][ENTRIES].
Initial blocks must use nested loops over both
dimensions.

  initial begin
    int fast_init;
    fast_init = 0;
    void'($value$plusargs("TAGE_FAST_INIT=%d", fast_init));
    if (fast_init != 0) begin
      for (int b = 0; b < 2; b++) begin
        for (int i = 0; i < RAM_ENTRIES; i++) begin
          u_ram_s0.mem[b][i] =
            THIS_CTR_WIDTH'(TAGE_SRAM_INIT_VALUE);
          u_ram_s1.mem[b][i] =
            THIS_CTR_WIDTH'(TAGE_SRAM_INIT_VALUE);
        end
      end
    end
  end

tage_table uses ALLOC_DATA_WIDTH instead of
THIS_CTR_WIDTH for the cast width.

### Isolation
- ubtb, loop_pred, and all other bw_ram users are
  unaffected. Only tage_bim, tage_table, and tage.sv
  read TAGE_FAST_INIT.
- When these modules share a future unified simulation
  with other predictors, isolation is preserved by the
  plusarg name scoping.

### TAGE_SRAM_INIT_VALUE
- Present in bp_defines_pkg.sv as localparam int = 0.
- Used by sram_init (via tage.sv .INIT_VAL port when
  TAGE_FAST_INIT=0) and the tage_bim/tage_table
  initial blocks (when TAGE_FAST_INIT=1).
- tage_bim casts to THIS_CTR_WIDTH.
- tage_table casts to ALLOC_DATA_WIDTH.

---

## tage_rdy Port

- tage.sv output port: tage_rdy (output logic)
- When TAGE_FAST_INIT=0: assign tage_rdy = tbl_ri_rdy
- When TAGE_FAST_INIT=1: tage_rdy = 1'b1 immediately
  after reset deasserts. Not derived from sram_init.
- No prediction or update may be asserted until
  tage_rdy is asserted. This is a testbench obligation
  documented in tage_interfaces.md.

---

## Hierarchical References

- Testbench uses hierarchical references to verify
  RAM contents directly after tage_rdy asserts.
- tage_bim and tage_table use hierarchical references
  in their initial blocks to write bw_ram mem arrays.
- bw_ram mem array is 2D: mem[BANKS][ENTRIES].
  All accesses must use mem[b][i] not mem[i].
- Confirmed hierarchical paths (verified BP-010a):
    T0: u_dut.u_tage_bim.u_ram_s0.mem[b][i]
        u_dut.u_tage_bim.u_ram_s1.mem[b][i]
    T1: u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s0.mem[b][i]
        u_dut.gen_tage_tbl[1].u_tage_tbl.u_ram_s1.mem[b][i]
    T2: u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s0.mem[b][i]
        u_dut.gen_tage_tbl[2].u_tage_tbl.u_ram_s1.mem[b][i]
    T3: u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s0.mem[b][i]
        u_dut.gen_tage_tbl[3].u_tage_tbl.u_ram_s1.mem[b][i]
    T4: u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s0.mem[b][i]
        u_dut.gen_tage_tbl[4].u_tage_tbl.u_ram_s1.mem[b][i]
- Verilator requires constant indices for generate
  block hierarchical references. Loop index t cannot
  be used directly. Unroll T1-T4 checks explicitly.
- Both usages are accepted. bw_ram.sv is untouched.

---

## Test Structure Convention

- Per-test enable integer declared at top of tb module:
    int verbose = 1;
    int _testname = 1;
- Invocation pattern:
    if (_testname) testname(ARGS, verbose);
- verbose parameter defined now. Semantics TBD.
- Use if (int_var != 0) not if (int_var) to avoid
  Verilator WIDTHTRUNC warnings.

---

## tage_rdy_tst() Task

- Spins until tage_rdy asserts.
- Watchdog threshold: (1 << MAX_IDX_WIDTH) + 16 cycles.
  Fails test and calls $finish if exceeded.
- After tage_rdy asserts: checks all RAM entries in
  all bw_ram instances via confirmed hierarchical paths.
  Verifies contents match TAGE_SRAM_INIT_VALUE.
  Uses unrolled T1-T4 checks (no loop index in path).
- When TAGE_FAST_INIT=0: verifies cycle count from
  reset deassertion to tage_rdy is less than
  (1 << MAX_IDX_WIDTH) + 4. Reports failure if exceeded.
- When TAGE_FAST_INIT=1: tage_rdy asserts on first
  cycle after reset. Cycle count check skipped.
- One task covers both paths. Task reads the plusarg
  internally to determine which checks apply.

---

## Makefile Conventions

- sim_tage: default, no +TAGE_FAST_INIT. Full sram_init
  sequence runs.
- sim_tage_fast: passes +TAGE_FAST_INIT=1. sram_init
  bypassed. tage_rdy immediate.
- Both targets must exit zero on PASS.

---

## Prompt Phasing

- BP-010a: DONE. RTL changes and tage_rdy_tst skeleton.
  Fast init path functionally incorrect -- sram_init
  not bypassed. Fixed in BP-010b.
- BP-010b: Fix tage.sv fast init bypass. Fix tage_bim
  and tage_table initial blocks for 2D mem access.
  Fix tage_rdy_tst cycle count window. Sim must pass
  under both sim_tage and sim_tage_fast.
- BP-010c and beyond: prediction and update tests.

