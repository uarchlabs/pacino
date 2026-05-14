# Session Handoff 019
Written by Claude.ai at end of session-019 (claude.ai session).
Date: 2026-04-06
This session executed BP-008a-1 and BP-008a-2 producing the
prediction-side logic for tage_cntrl.sv. Several technical
debt items were identified and recorded. No update logic was
produced. Read PROJECT_STATUS.md, then this file, then
CLAUDE.md to restore full context.

---

## What This Session Covered

Session context restored from session_handoff-018.
tage_interfaces.md, tage_table_interfaces.md, and all four
tage_cntrl_*.md arch documents loaded as additional context.

Primary work:
- Reviewed and finalized tage_table_interfaces.md. T0 port
  list added. All known gaps closed. Document promoted to
  Complete.
- Reviewed and finalized tage_interfaces.md. Port list
  converted to vector indexing convention. TI3 retracted
  and corrected. Aging ports added.
- Converted tage_interfaces.md port naming convention from
  scalar per-slot pairs to vector index [0:NUM_PRED_SLOTS-1]
  throughout.
- Retracted pred_pc+32 slot 1 PC derivation. Slot 1 PC
  is supplied by fetch unit via tage_pred_inp_p0[1].pc.
  No offset derivation in tage_cntrl.
- Added Dual Prediction Support section to
  tage_cntrl_decisions.md.
- Added T0 direction sourcing rule to
  tage_cntrl_decisions.md.
- Executed BP-008a-1: tage_cntrl.sv shell. PASS.
- Executed BP-008a-2: tage_cntrl.sv prediction logic. PASS.
- Identified and recorded technical debt items 19-22.
- Defined cleanup sequence BP-007d/e/f before BP-008b.

---

## Decisions Made This Session

### Port naming convention finalized
Slot dimension uses vector index [0:NUM_PRED_SLOTS-1].
No scalar per-slot signal pairs anywhere in tage_cntrl
or tage interfaces. This applies to all future modules
in the TAGE cluster.

### pred_pc+32 retracted
TI3 in tage_interfaces.md was in error. Slot 1 PC is
supplied by an external unit. No offset derivation is
performed in tage_cntrl. tage_pred_inp_p0[0].pc or
tage_pred_inp_p0[1].pc are consumed as-is.

### T0 direction sourcing
where 's' is the prediction slot, 
T0 direction is always taken from t_taken_p1[0][s] port
output of the T0 tage_table instance. tage_prm_ctr[2][s]
is always zero for T0 and must never be used as direction.
tage_prm_pred_tkn is the authoritative direction field.
Documented in tage_cntrl_decisions.md.

### tbl_ri_* ports do not belong on tage_cntrl
tbl_ri_* ports are driven by sram_init.sv instantiated
in tage.sv directly to tage_table instances. tage_cntrl
has no tbl_ri_* ports. tage_table_interfaces.md updated
to reflect this.

### alc_tbl_sel_u0 and alc_index_u0 gap
These ports exist in tage_table_interfaces.md spec but
not in tage_table.sv. Spec is correct. tage_table.sv
must be patched. Tracked as BP-007d.

### T1-T4 hash architecture correction
tage_cntrl incorrectly generates slot-independent T1-T4
hashes from fld_hist_p0 and forwards them to tables.
Each table must derive its own hashes locally using its
own table-specific history lengths. fld_hist_p0 moves
to tage_table as a direct input. Tracked as debts 20
and 21, cleanup in BP-007e and BP-007f.

### UAON is update-time only
UAON counters are read at predict time but never written
at predict time. The predict-time uaon_ff block generated
by BP-008a-2 is incorrect and must be removed. UAON
counter updates are implemented in BP-008b per the
settled truth table in tage_cntrl_useful_update_rules.md.
Tracked as debt #19.

### T0 CTR zero-padding in meta
tage_prm_ctr stores T0 2b CTR as a 3b zero-padded value
when T0 is provider. BP-008b must gate T0 CTR
interpretation on tage_prm_comp == 0. Direction must
be taken from tage_prm_pred_tkn not tage_prm_ctr[2].
Tracked as debt #22.

### Managing claude.code access to prompts for results capture
claude.code has shown problems finding the file to write
it's results. The decision is to use ./prompts to hold all
prompts rather than the unit base sub-directories. 
This is now in CLAUDE.md. The requirement is that the
prompt section will now tell claude.code the task id
as in:
```
## Task ID
Replace this with the task ID
```
This will be filled out during prompt generation.


---

## Technical Debt Added This Session

| 19 | uaon_ff logic in tage_cntrl.sv is incorrect.    | Fix in BP-008b.      |
|    | BP-008a-2 prompt erroneously specified decrement | Remove predict-time  |
|    | unconditionally at predict time. UAON is update  | uaon_ff block.       |
|    | time only. See UAON Modification During Update   | Reimplement per      |
|    | in tage_cntrl_useful_update_rules.md.            | settled truth table. |

| 20 | T1-T4 index and tag hashing incorrect in         | BP-007e.             |
|    | tage_cntrl. tage_cntrl generates slot-independent| Remove index, tag    |
|    | hashes from fld_hist_p0 and forwards to tables.  | outputs and          |
|    | This is wrong. Each table derives its own hashes | fld_hist_p0 input    |
|    | locally. tage_cntrl hash logic must be removed.  | from tage_cntrl.     |
|    |                                                  | Remove associated    |
|    |                                                  | hash logic.          |
|    |                                                  | Update               |
|    |                                                  | tage_interfaces.md   |
|    |                                                  | and tage_table_      |
|    |                                                  | interfaces.md.       |
|    |                                                  | Compile lint clean.  |

| 21 | tage_table does not derive its own index and tag  | BP-007f.             |
|    | hashes. fld_hist_p0 must be added as a direct    | Add fld_hist_p0      |
|    | input to tage_table. Each table must compute its | input to tage_table. |
|    | own hashes locally using table-specific history  | Define hash          |
|    | lengths. Hash functions must be defined as       | functions as         |
|    | planning elements before re-running tage_table.  | planning elements    |
|    |                                                  | first. Implement     |
|    |                                                  | local hash logic.    |
|    |                                                  | Re-run tage_table    |
|    |                                                  | prompt. Compile      |
|    |                                                  | lint clean.          |

| 22 | T0 CTR stored in tage_pred_meta_t as 3b          | Fix in BP-008b.      |
|    | zero-padded value when T0 is provider.           | BP-008b must gate    |
|    | tage_prm_ctr field is 3b but T0 CTR is 2b.      | T0 CTR              |
|    | Update path must not interpret tage_prm_ctr      | interpretation on    |
|    | MSB as direction when tage_prm_comp == 0.        | tage_prm_comp == 0.  |
|    | Direction must be taken from tage_prm_pred_tkn   | Use tage_prm_pred_   |
|    | not tage_prm_ctr[2].                             | tkn for direction,   |
|    |                                                  | not tage_prm_ctr[2]. |

---

## Technical Debt Modified This Session

None modified. Debts 19-22 are new.

---

## Files Created This Session

  BP-008a-1.md    -- experiment file, PASS
  BP-008a-2.md    -- experiment file, PASS

## Files Modified This Session

  tage_interfaces.md
    -- Port list converted to vector indexing.
    -- Aging ports added.
    -- TI3 retracted and corrected.
    -- TI2 closed.
    -- Status promoted to Complete.

  tage_table_interfaces.md
    -- T0 port list added.
    -- T0 entry format documented.
    -- tbl_ri_* sourcing clarified (sram_init in tage.sv).
    -- TAGE_T0_CTR_BITS added to top level parameters.
    -- MAX_IDX_WIDTH naming made consistent throughout.
    -- pc[11:1] corrected from pc[12:1].
    -- All known gaps closed.
    -- Status promoted to Complete.

  tage_cntrl_decisions.md
    -- Dual Prediction Support section added.
    -- T0 direction sourcing rule added.

  tage_cntrl.sv
    -- Shell produced by BP-008a-1.
    -- Prediction logic added by BP-008a-2.
    -- Update-side outputs remain at zero.
    -- Known defects: uaon_ff (debt #19),
       hash logic (debt #20).

  bp_defines_pkg.sv
    -- Duplicate TAGE_T0_CTR_BITS removed (pre-existing bug).

---

## Next Session

### Cleanup sequence before BP-008b

The following must run in order before BP-008b:

#### BP-007d: patch tage_table.sv alc ports
Add alc_tbl_sel_u0 and alc_index_u0 ports to tage_table.sv.
Wire allocation logic. Compile and lint clean.
Load as context:
  tage_table_interfaces.md
  tage_table.sv
  bp_defines_pkg.sv
  bp_structs_pkg.sv

#### BP-007e: remove hash logic from tage_cntrl
Remove fld_hist_p0 input, index/tag output ports, and all
associated hash logic from tage_cntrl.sv. Update
tage_interfaces.md and tage_table_interfaces.md.
Compile and lint clean.
Load as context:
  tage_interfaces.md
  tage_table_interfaces.md
  tage_cntrl.sv
  bp_defines_pkg.sv
  bp_structs_pkg.sv

#### BP-007f: add local hash logic to tage_table
Define hash functions as planning elements first. Add
fld_hist_p0 input to tage_table. Implement local index
and tag hash logic using table-specific history lengths.
Re-run tage_table prompt. Compile and lint clean.
Load as context:
  tage_table_interfaces.md
  tage_table.sv
  tage_hash.sv
  bp_defines_pkg.sv
  bp_structs_pkg.sv

#### BP-008b: tage_cntrl.sv update logic
Add update logic to tage_cntrl.sv. Remove incorrect
predict-time uaon_ff block (debt #19). Implement UAON
update per settled truth table. Gate T0 CTR on
tage_prm_comp == 0 (debt #22). Compile and lint clean.
Load as context:
  tage_interfaces.md
  tage_table_interfaces.md
  tage_cntrl_decisions.md
  tage_cntrl_ctr_update_rules.md
  tage_cntrl_useful_update_rules.md
  tage_cntrl_alloc_rules.md
  tage_cntrl.sv
  bp_defines_pkg.sv
  bp_structs_pkg.sv

---

## PROJECT_STATUS.md Updates Needed

1. Module table: update tage_cntrl.sv row status to
   In Progress. Note BP-008a-1/a-2 complete,
   BP-008b pending.
2. Add debts 19, 20, 21, 22 to Technical Debt table.
3. Add BP-007d, BP-007e, BP-007f to TAGE decomposition
   section under Architectural Decisions.
4. Update BP-008 decomposition to reflect
   BP-008a-1/a-2/b split.
5. Add note to debt #18: update side still open,
   pending T0 implementation in tage_table.

