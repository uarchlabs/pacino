# TAGE Decomposition Log
```
 FILE:    TAGE_DECOMP_LOG.md
 SOURCE:  PROJECT_STATUS.md (extracted session-038)
 STATUS:  ARCHIVE
 UPDATED: 2026-04-29
 CONTACT: Jeff Nye
```

Archive of TAGE decomposition history extracted from
PROJECT_STATUS.md during session-038 size reduction.
Not updated after extraction. See git log and session
handoffs for further detail.

---

## Module Notes at Extraction

### tage_table.sv
  BP-007a PASS 10/10.
  BP-007b refactor complete.
  BP-007c see debt #17.
  BP-007d allocation ports complete.
  BP-007f complete.
  Functional issues remain (BP-007c, debt #17).
  HAND-FIX-001 applied see debt #29,
    completed in BP-009a/b.
  BP-012 adds idx_hash_p0 and tag_hash_p0 output ports.

### tage_bim.sv
  BP-009a completed in 009b.
  BP-012 adds idx_hash_p0 output.

### tage_cntrl.sv
  BP-008a-1 complete tage_cntrl shell.
  BP-008a-2 complete prediction logic.
  BP-007e complete: rmv index/tage ports.
  BP-008b complete.
  HAND-FIX-002 applied see debt #30.
  BP-012 fixes t_idx_r1/t_tag_r1 undriven (defect 1)
    and T0 prm_ctr mis-extraction (defect 2).
    Both found BP-011, fixed BP-012.

### tage.sv
  BP-010c/d/e complete.
  BP-010f complete.
  BP-011 and BP-012 complete.
  BP-014a through BP-014h complete.
  BP-026: TC-55 through TC-60 added.
  BP-027: TC-14 through TC-16 in tb_tage_table.sv.
    cov_tage_table 90.1% achieved.
  BP-028: TC-61, TC-62 added. fh_sel T2/T3 covered.
  BP-029: TC-63 through TC-66 added.
    CE-01 through CE-04 closed.
    Sat arithmetic boundary tests.
  BP-030: TC-67, TC-68 added.
    CE-05 (no-alloc sentinel) and
    CE-06 (no-write update path) closed.
  Test count tb_tage: 68, all pass.
  Test count tb_tage_table: 15.

---

## Decomposition Sequence

  BP-006: tage_hash.sv   -- complete, later abandoned.
                            Tables generate hashes locally.
  BP-007: tage_table.sv  -- complete (signal naming cleanup
                            pending, see debt #17)
  BP-007d: tage_table.sv -- complete, add alc_tbl_sel_u0 and
                            alc_index_u0 ports and allocation
                            logic.
  BP-007e: tage_cntrl.sv -- complete remove index/tag hash
                            logic and fld_hist_p0 input.
  BP-007f: tage_table.sv -- complete add fld_hist_p0 input,
                            define and implement local hash
                            functions per table-specific
                            history lengths.
  BP-008a: tage_cntrl.sv -- complete, prediction side.
  BP-008b: tage_cntrl.sv -- complete.
  BP-009: tage.sv        -- lint PASS.
  BP-009a: tage.sv       -- complete.
  BP-010: tage.sv        -- complete, tage testbench.
  BP-014a-h: tage.sv     -- complete, validation.
  BP-015 through BP-022b: complete.
  BP-025: tage.sv        -- CU-11 root cause diagnosed.
  BP-026: tage.sv        -- TC-55 through TC-60 added.
  BP-027: tage_table.sv  -- TC-14 through TC-16 added.
                            cov_tage_table 90.1% PASS.
  BP-028: tage.sv        -- TC-61, TC-62 added. 62 pass.
  BP-029: tage.sv        -- TC-63 through TC-66 added.
                            CE-01 through CE-04 closed.
                            Sat arithmetic boundary tests.
                            68 tests pass.
  BP-030: tage.sv        -- TC-67, TC-68 added.
                            CE-05 (no-alloc sentinel) and
                            CE-06 (no-write update path)
                            closed. 68 tests pass.
                            All TAGE coverage targets closed
                            or deferred.

