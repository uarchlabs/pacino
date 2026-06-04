# Project Status -- RISC-V RVA23 Processor Co-Design
```
 FILE:    PROJECT_STATUS.md
 SOURCE:  various
 STATUS:  WORKING
 UPDATED: 2026-06-04 (session_handoff-045)
 CONTACT: Jeff Nye
```

Updated every session. Paste into Claude.ai at session start,
along with the latest session_handoff-NNN.md and CLAUDE.md.

Paste PROJECT_CORE.md only when methodology is under discussion.

---

## Module Status

| Module                  | Status      | Tests             | Notes                            |
|-------------------------|-------------|-------------------|----------------------------------|
| predecode.sv            | Complete    | tb_predecode      | clk/rstn unused (debt #4)        |
| instr_decoder.sv        | Complete    | tb_instr_decoder  | 1043 passing                     |
| rvc_expander.sv         | Complete    | tb_rvc_expander   |                                  |
| decode_pkg.sv           | Complete    | --                | All decode structs               |
| bp_defines_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE parameters       |
|                         |             |                   | complete. IT_TBL_TGT_WIDTH added.|
| bp_structs_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE structs complete.|
|                         |             |                   | IT5 fold fields pending (II1).   |
| bp_pkg.sv               | Deprecated  | --                | Deleted.                         |
| bp_history.sv           | Complete    | tb_bp_history     | 12 passing                       |
| ubtb.sv                 | Complete    | tb_ubtb           | TC1-TC10 passing.                |
|                         |             |                   | Port naming retrofit pending     |
|                         |             |                   | (CLI-012)                        |
| loop_pred.sv            | Complete    | tb_loop_pred      | BP-004c-f complete.              |
|                         |             |                   | Port naming retrofit pending     |
|                         |             |                   | (CLI-011)                        |
| tage_interfaces.md      | Complete    | --                | session-036: 6 corrections       |
|                         |             |                   | applied.                         |
| tage_table_interfaces.md| Draft       | --                | Created session-016.             |
|                         |             |                   | Updates pending.                 |
| tage_cntrl_use          | Complete    | --                | session-037: complete.           |
| _update_rules.md        |             |                   | session-045: DIFF corrected.     |
|                         |             |                   | TTM row added. Notes corrected.  |
|                         |             |                   | Aging disabled section added.    |
| tage_cntrl_uaon         | Draft       | --                | session-036: verified.           |
| _update_rules.md        |             |                   | Debt #45 closed BP-032.          |
| tage_cntrl              | Complete    | --                | session-044: X entries expanded. |
| _ctr_update_rules.md    |             |                   | Unreachable rows removed.        |
|                         |             |                   | ADR-001 added.                   |
|                         |             |                   | Verified session-045 via         |
|                         |             |                   | tage_use_test all 6 rows pass.   |
| bw_ram / sat_alu        | Complete    | tb_components     | COMP-001 PASS                    |
| dual_lm1                | Complete    | tb_components     | COMP-002 now uses generate       |
| sram_init               | Complete    | tb_components     | COMP-003                         |
| tage_hash.sv            | Complete    | tb_tage_hash      | BP-006 abandoned.                |
| tage_table.sv           | Complete    | tb_tage_table     | BP-007 through BP-012 complete.  |
|                         |             |                   | Signal naming debt #17 pending.  |
|                         |             |                   | HAND-FIX-001 applied.            |
| tage_bim.sv             | Complete    | --                | BP-009b complete.                |
|                         |             |                   | idx_hash_p0 output added.        |
| tage_cntrl.sv           | In progress | --                | BP-008a/b complete.              |
|                         |             |                   | BP-012 complete.                 |
|                         |             |                   | Was complete but BP-034/5 exposed|
|                         |             |                   | issues, see tech debt #45.       |
|                         |             |                   | HAND-FIX-002 applied (debt #30). |
|                         |             |                   | HAND-FIX-003 applied (BP-041).   |
|                         |             |                   | T0 CTR u_both_t0 path corrected. |
| tage.sv                 | Complete    | tb_tage           | BP-010 through BP-030 complete.  |
|                         |             |                   | 68 tests pass. All coverage      |
|                         |             |                   | targets closed or deferred.      |
|                         |             |                   | tage_assert.sv bound via bind.   |
| tage_assert.sv          | Complete    | sim_tage          | ADR-001 and row 18 assertions.   |
|                         |             | sim_tage_fast     | assert_inhibit port added        |
|                         |             | sim_tage_tasks    | (BP-042a). CE-06 gated.          |
|                         |             | sim_tage_manual   | Bound in tb_tage.sv,             |
|                         |             |                   | tb_tage_manual.sv,               |
|                         |             |                   | tage_assert_bind.sv removed from |
|                         |             |                   | sim_tage_manual (BP-042b).       |
| ittage_assert.sv        | Complete    | sim_ittage        | New session-045 (BP-042/042a/b). |
|                         |             |                   | Three assertions: hit+comp,      |
|                         |             |                   | using_primary+prm_comp,          |
|                         |             |                   | using_primary+alt_comp.          |
|                         |             |                   | ittage_hit guard on assertion 2  |
|                         |             |                   | added BP-042b.                   |
|                         |             |                   | Located in tb/ directory.        |
| tb_tage_manual.sv       | Complete    | sim_tage_manual   | tage_ctr_test rows 1-17 pass.    |
|                         |             |                   | Row 18 covered by assertion.     |
|                         |             |                   | tage_use_test rows 1-6 pass.     |
|                         |             |                   | session-045.                     |
| ittage_interfaces.md              | Draft       | --    | session-036: corrections applied.|
|                                   |             |       | session-037: II6 resolved.       |
|                                   |             |       | session-038: redundancy collapse |
|                                   |             |       | applied.                         |
| ittage_table_interfaces.md        | Draft       | --    | Created session-036.             |
|                                   |             |       | session-038: redundancy collapse |
|                                   |             |       | applied.                         |
| ittage_cntrl_alloc_rules.md       | Complete    | --    | Created session-033.             |
|                                   |             |       | session-036: verified.           |
| ittage_cntrl_ctr_update_rules.md  | Complete    | --    | session-045: TBD draft replaced  |
|                                   |             |       | with fully specified 33-row      |
|                                   |             |       | table. Assert rows A1/A2/A3      |
|                                   |             |       | added citing ittage_assert.sv.   |
|                                   |             |       | MIS, pACT, aACT all populated.   |
| ittage_cntrl_decisions.md         | Complete    | --    | session-036: corrections applied.|
|                                   |             |       | session-037: open items closed.  |
|                                   |             |       | session-038: redundancy collapse |
|                                   |             |       | applied.                         |
| ittage_cntrl_uaon_update_rules.md | Draft       | --    | Created session-033.             |
|                                   |             |       | session-036: user editing        |
|                                   |             |       | manually.                        |
| ittage_cntrl_use_update_rules.md  | Draft       | --    | session-045: DIFF corrected      |
|                                   |             |       | (prm_tgt != alt_tgt).            |
|                                   |             |       | HIT=0 row added.                 |
|                                   |             |       | Notes corrected and aligned.     |
|                                   |             |       | Aging disabled section added.    |
| ittage_table_hash_rules.md        | Complete    | --    | Created session-033.             |
|                                   |             |       | session-036: verified.           |
| ittage_table.sv                   | Complete    | tb_ittage_table | BP-033/033-FIX-1 complete. |
| ittage_cntrl.sv                   | Complete    | tb_ittage_cntrl | Prediction path complete BP-034|
|                                   |             |       | Update path complete BP-035      |
|                                   |             |       | Testbench complete BP-036        |
|                                   |             |       | 76 tests passing                 |
|                                   |             |       | BP-040 Bug B/C/D unverified.     |
| ittage.sv                         | In progress | tb_ittage | BP-034/035/35a/35b           |
|                                   |             |       | shell without arb cntrl complete |
|                                   |             |       | sim_ittage 32 pass / 3 fail      |
|                                   |             |       | (pre-existing, BP-042b).         |
| FTB, SC, RAS     | Not started | --             | Later BP sessions                |
| bp_cluster (top) | Not started | --             | After predictors complete        |
| fetch            | Not started | --             | After BP cluster                 |

---

## Technical Debt

| # | Item                                   | Resolution path                 |
|---|----------------------------------------|---------------------------------|
| 1  | NUM_PRED_SLOTS=2 default. Generate    | Cleanup session after TAGE      |
|    | removal and NUM_PRED_SLOTS=1 tests    | complete                        |
|    | pending.                              |                                 |
| 2  | Instruction fusion                    | Deferred to rename/dispatch     |
| 3  | UOP expansion for RVV segments        | Policy TBD at vector execution  |
| 4  | predecode.sv clk/rstn unused          | Resolve at pipeline stage assign|
| 5  | ENUM hole at 7'd2 (VALU_FP)           | Minor, acceptable for now       |
| 6  | vtype_hazard intra-bundle policy      | TBD at rename/dispatch          |
| 7  | curs/curs_v rollback undefined.       | Resolve at bp_cluster impl or   |
|    | Seznec uses SLIM structure. Inline    | migrate to SLIM-style external  |
|    | fields have no defined                | structure.                      |
|    | checkpoint/rollback path.             |                                 |
|    | retained during transition.           |                                 |
| 15 | EPC field semantics not yet           | Define before BP-008            |
|    | documented.                           |                                 |
| 16 | ALLOC_DATA_WIDTH padding when         | Resolve at T0 implementation    |
|    | THIS_ < MAX_ -- unused bits between   |                                 |
|    | EPC and TAG fields.                   |                                 |
| 17 | BP-007b signal naming nonconforming.  | BP-007c scope expanded to       |
|    | _s0/_s1 suffixes used instead of      | include alc_index_u0 width fix  |
|    | array indexing per                    |(MAX_IDX_WIDTH->THIS_INDEX_BITS) |
|    | tage_table_interfaces.md.             | T0 tag hash compute-and-discard |
|    | Prompt author error.                  | cleanup.                        |
| 18 | Definition of T0 fields/behavior      | Prediction side closed          |
|    |                                       | Update side pending T0          |
|    |                                       | implementation                  |
| 37 | trx_type forwarded combinationally    | Investigate in BP-023c          |
|    | from arb_grant_upd instead of from    | before closing. When concurrent |
|    | registered arb_trx_r.trx_type.        | pred+upd tests are added,       |
|    | When concurrent pred+upd tests are    | verify grant signal stability   |
|    | added (TB-ARB-03, TB-ARB-04), verify  | through tage_cntrl pipeline.    |
|    | grant signal stability through        | If unstable, promote            |
|    | tage_cntrl pipeline is maintained.    | arb_trx_r.trx_type and adjust   |
|    |                                       | write-enable timing.            |
| 38 | Verilator upgraded to 5.048.          | Covergroup/coverpoint issue     |
|    | inout optimizer bug resolved.         | #7099 status in 5.048 release   |
|    | Covergroup/coverpoint support         | notes still needs re-check      |
|    | (issue #7099) status in 5.048         | before fully closing TD #38.    |
|    | not yet verified.                     |                                 |
| 39 | TB-ARB-08 Rule 2 starvation override  | Verify at design finalization   |
|    | is untestable with current params.    | that PRED_CREDITS <             |
|    | TAGE_PRED_CREDITS=4 <                 | STARVE_THRESH is intentional.   |
|    | TAGE_STARVE_THRESH=8 means            | If Rule 2 must be testable,     |
|    | starve_ctr never reaches threshold.   | adjust params before bp_cluster |
|    | Rule 4 is the effective ceiling.      | integration.                    |
| 40 | TB-ARB-05 spec discrepancy.           | Update bp_arb_spec.md           |
|    | bp_arb_spec.md section 10.1           | section 10.1 to match           |
|    | describes "backpressure for 2 cycles" | TAGE_UQ_DEPTH=8 before          |
|    | which does not match TAGE_UQ_DEPTH=8. | bp_cluster integration.         |
|    | No RTL risk.                          | No RTL change required.         |
| 41 | CU-08/CU-09 aging paths deferred.     | Revisit at bp_cluster aging     |
|    | tage_enable_aging never driven high   | integration when                |
|    | in TC-44/TC-45. Accepted gap per      | tage_enable_aging control is    |
|    | session-031 decision.                 | defined at cluster interface.   |
| 42 | Pipeline diagram shows ITTAGE         | Revisit after SC definition.    |
|    | operating at s3, should be s2.        | Update diagram and discussions. |
|    | ITTAGE operates alongside FTB and     |                                 |
|    | TAGE at s2.                           |                                 |
| 43 | Reduce the CTR width in    | This impacts a number of files/designs/tbs      |
|    | ITTAGE from 3b to 2b.      | as well as RTL, known so far bp_defines_pkg.sv  |
|    |                            | ittage_table_interfaces.md as well RTL and      |
|    |                            | testbenches.                                    |
| 44 | Confirm change to  | in ittage_cntrl_decisions.md                        |
|    | ittage_pred_strong | from ittage_pred_strong -- provider ctr was !=3 & !=4|
|    |                    | to   ittage_pred_strong -- provider ctr > 0 (NOT NULL)|
|    |                    | Document change has been made (in session 040)       |
|    |                    | Make sure #43 does not impact any testcases          |
| 45 | Revisit tage_cntrl | During update there are multiple tables that can be  |
|    | and tage_table     | written and need the proper ports in the table and   |
|    | Simplifications    | in the control.                                      |
|    | available.         |                                                      |
|    |                    | - T0 always has CTR value updated, needs an index.   |
|    |                    | - both primary and alt can have CTR updated          |
|    |                    |   one of primary or alt may have useful updated      |
|    |                    |     useful update can use the prm_idx or alt_idx     |
|    |                    |                                                      |
|    |                    | It is possible to also allocate an entry             |
|    |                    |                                                      |
|    |                    | Currently tage_cntrl supplies a 2D bus for update    |
|    |                    | and allocation index. one D is prediction slot the   |
|    |                    | other D is one for each table. This is wrong.        |
|    |                    |                                                      |
|    |                    | It should be one upd index port for the bim where    |
|    |                    | the index is directly taken from                     |
|    |                    | tage_pred_meta.tage_bim_idx.                         |
|    |                    |                                                      |
|    |                    | Note tage_bim_idx is new, added for this fix.        |
|    |                    | tage_bim_idx is from the branch pc bits in the       |
|    |                    | original prediction request                          |
|    |                    | tage_bim_idx = PC[TAGE_MAX_IDX_WIDTH-1:1]            |
|    |                    |                                                      |
|    |                    | Changes: tage_table_interfaces.md                    |
|    |                    |            specify upd_index_u0[s]                   |
|    |                    |            specify alc_index_u0[s]                   |
|    |                    |            specify bim_index_u0[s]                   |
|    |                    |          test if alc_index_u0 is necessary likely not|
|    |                    |          add a tage_cntrl_interfaces.md doc          |
| 46 | ittage_cntrl.sv    | CLOSED. BP-038a did not close this in the tb.    |
|    | missing trx_type   | Add trx_type input port (logic type) to          |
|    | port               | ittage_cntrl.sv. Connect to trx_type_comb in     |
|    |                    | ittage.sv. BP-040 closed this item.              |
| 47 | ittage_interfaces  | CLOSED.                                          |
|    | .md missing arb    | Add pq_not_full and upd_rdy to port list.        |
|    | ports              | These ports are present in ittage.sv (added      |
|    |                    | BP-038) but not in the spec. Update before       |
|    |                    | bp_cluster integration.                          |
|    |                    | These are also missing in tage_interfaces.md     |
| 48 | ittage.sv RB       | CLOSED.                                          |
|    | bypass behavior    | consumer_ready=1'b1 means RB memory is never     |
|    |                    | written and results always bypass. Correct for   |
|    |                    | ITTAGE with no SC consumer. Verify bypass        |
|    |                    | behavior matches bp_cluster backpressure         |
|    |                    | expectations at cluster integration.             |
| 49 | Arb queue status   | Tage and Ittage have arbitration queue status    |
|    | pin renaming       | flags, pq_not_full, upd_rdy. These ports should  |
|    |                    | be renamed for standardization:                  |
|    |                    | Tage: pq_not_full ->  tage_pq_not_full           |
|    |                    | Tage: upd_rdy     ->  tage_uq_not_full           |
|    |                    | ITTage: pq_not_full -> ittage_pq_not_full        |
|    |                    | ITTage: upd_rdy    -> ittage_uq_not_full         |
|    |                    | Scope: RTL, testbenches, bp_arb_spec.md,         |
|    |                    | tage_interfaces.md, ittage_interfaces.md         |
| 50 | sram_init FAST_INIT  | CLOSED. w. BP-040.                            |
|    | behavior             | ittage.sv nonconformance fixed.               |
|    |                      | All modules audited.                          |
| 51 | CTR/USE/TGT update   | Bug 4 (BP-039) found using_primary condition  |
|    | rule audit           | inverted in ittage_cntrl.sv ctr_upd block.    |
|    |                      | Systematic risk: other update logic blocks    |
|    |                      | (USE, TGT, allocation) may have similar       |
|    |                      | errors not yet exercised by existing tests.   |
|    |                      | Resolution: new round-trip test set in        |
|    |                      | tb_ittage.sv exercising each CTR/USE/TGT      |
|    |                      | update rule row explicitly. One test per      |
|    |                      | rule row in ittage_cntrl_ctr_update_rules.md  |
|    |                      | and ittage_cntrl_use_update_rules.md.         |
|    |                      | Tests must be independent of each other       |
|    |                      | and of TC-P01 through TC-UAON-01.             |
|    |                      | Constraints section of prompts will preclude  |
|    |                      | IA from modifying RTL without citing the      |
|    |                      | violation in the planning documents.          |
| 52 | move Arb logic into  | The top level modules should be structural   |
|    | submodule out of top | only. Create a new module for tage and       |
|    | in tage and ittage   | ittage, move the arb logic into this new     |
|    |                      | module.                                      |
| 53 | tage_ctr_test rows   | CLOSED with BP-041.md                        |
|    | 14-17 failing        | pcomp CTR write not landing in T4 RAM for    |
|    |                      | rows 14-17. Root cause was test state        |
|    |                      | contamination from rows 13 into rows 14-17.  |
| 54 | tage ctr tests       | Planning document tage_cntrl_ctr_update_rules.md |
|    |                      | was updated and confirmed with BP-041 manual |
|    |                      | tests. The new table is more explicit on X   |
|    |                      | handling and backed by new assertions.       |
|    |                      | Existing IA tests need audit and retrofit.   |
|    |                      | BP-043 will address this.                    |

---

## Open Items

| Priority | Item                                    | Status              |
|----------|-----------------------------------------|---------------------|
| 1        | TOOLS-002 spike ISA string              | Deferred            |
| 2        | DECODE-012 pre-decode restructure       | Defer to fetch unit |
| 3        | Whisper ISS lock-step validation        | Post-pipeline       |
| 4        | Cleanup CLI-001,002,004,008,011,012,TI7 | Complete            |
| 5        | TAGE full validation plan               | Complete            |
| 6        | BP code coverage plan: CE-01            | Complete            |
|          | through CE-06 all closed                |                     |
| 7        | Verilator upgrade to post-covergroup    | Upgraded to 5.048.  |
|          | release                                 | Covergroup #7099    |
|          |                                         | re-check pending.   |
| 8        | Investigate mutation testing            | Planned             |
| 9        | Research verible-verilog-format for SV  | Planned             |
|          | formatting.                             |                     |
| 10       | README update: document tools/bin       | Pending             |
|          | layout and build instructions for       |                     |
|          | Verilator and Spike.                    |                     |

---

## BP Cluster Open TBDs

| ID  | Item                                  | Status                 |
|-----|---------------------------------------|------------------------|
| G5  | RAS commit stack entry count          | TBD at implementation  |
| G6  | RAS recursion counter width           | TBD at implementation  |
| G7  | SC threshold value                    | TBD, fixed at impl     |
| G8  | Dual pred bundle split point          | TBD at fetch interface |
| G9  | Update channel arbitration            | TBD                    |
| G10 | TAGE/ITTAGE meta overload scheme      | TBD at implementation  |
| G14 | Confidence counter purpose            | Reserved, 4b           |
| G15 | Fold recompute timing concern         | Deferred               |
| G16 | ignored labeling gap                  |                        |
| G17 | Slot 1 PC derivation (pred_pc+32)     | TBD at fetch interface |
| G18 | carry field consumer in cluster       | TBD at bp_cluster impl |
| G19 | NO_BRANCH target on hit:              | TBD                    |
|     | fall-through PC or zero?              |                        |
|     | See also UI4 in ubtb_interfaces       |                        |
| G20 | bp_history dual slot update path      | Resolve before         |
|     | not defined for NUM_PRED_SLOTS=2      | bp_cluster impl        |
|     | See HI1 in bp_history_interfaces      |                        |
| G21 | rollback_en + pred_valid same-cycle   | Resolve before         |
|     | priority undefined                    | bp_cluster impl        |
| G22 | One-cycle folded output invalid       | Tied to G15            |
|     | window after rollback                 |                        |
| G23 | Checkpoint slot reclaim protocol      | TBD at FTQ impl        |

---

## Package Split Convention (settled session-008)

bp_pkg.sv has been split into:
  bp_defines_pkg.sv  -- bp_defines_pkg  -- parameters only
  bp_structs_pkg.sv  -- bp_structs_pkg  -- structs, enums, typedefs

Import order is mandatory in every file:
  import bp_defines_pkg::*;
  import bp_structs_pkg::*;

---

## BP Cluster Key Parameters
See bp_defines_pkg.sv. Do not duplicate here.
num_branches valid range: 0-2. Value 3 is undefined.

---

## Prompt Generation Guide

See PROJECT_CORE.md §Prompt generation rules.
For known failure modes see ANTIPATTERNS.md.

---

## Architectural Decisions

### Decoder track

Full detail: planning/arch/decode.md (file currently absent).

Key decisions for quick reference:
- Illegal instruction: ILLEGAL flag in decode packet,
  ROB entry allocated, commit flushes to mtvec
- vtype: decoder stateless, rename resolves dependency
- Dual decode packet: decode_pkt_t[7:0] scalar,
  vec_decode_pkt_t[7:0] vector, predecode_pkt_t[7:0]
- OPMVX: pkt.vs1=0, GPR in scalar pkt.rs1
- Extension enable: ext_enable_t static from misa/CSR
- Vector memory disambiguation: opcodes 0x07/0x27

### BP cluster track

Full detail: planning/arch/bp_cluster.md (LOCKED)

Key decisions for quick reference:
- Seven predictors: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS
- Pipeline: s0 index, s1 uBTB+Loop, s2 FTB+TAGE+ITTAGE+RAS,
  s3 SC
- Override chain: SC > TAGE > FTB > uBTB
- ITTAGE overrides FTB target at s2 for indirect branches.
  RAS overrides FTB target at s2 for returns. Both are
  mutually exclusive by branch type resolved upstream.
- Loop overrides uBTB at s1 when trusted
- Update policy: post-execute, not retire
- RAS: Dual-stack, 48 entries
- BPU is decoupled frontend, self-generates next PC
- FTQ depth 64, split fast/slow SRAMs
- History: GHR 256b, PHR 32b, folds recomputed on rollback
- TAGE entry: T0 2b CTR only, T1-T4 valid+tag+CTR+useful
- ITTAGE entry: IT1-IT5 valid+tag+EPC+USE+CTR(3b)+TGT(38b).
  No IT0 base table. CTR is confidence not direction.
  Target written on misprediction when CTR is null only.
- SC index split: sc_upd_idx[MAIN_TBLS], sc_imli_idx
- SC has no tag bits. All 5 tables are pure counter arrays.
  BrIMLI table (ST4) is SC only -- not ITTAGE.
- NUM_PRED_SLOTS=2 is the default for all current design
  work. Both slot 0 and slot 1 logic always present
  unconditionally. Reduction to 1 is deferred (debt #1).
- Port naming convention: <signal>_<pipestage>
  p0/p1/p2 for prediction path, u0/u1 for update path,
  px for flush signals (not yet defined).
- TI6 RESOLVED: Banks are per-slot RAMs, not address-banked.
  Each table contains two independent RAMs. RAM0 serves
  slot 0, RAM1 serves slot 1. Selection is structural.
  Unrelated to bw_ram BANKS parameter or sram_init scheme.
- CNTRL_BITS_WIDTH = MAX_EPC_WIDTH+MAX_USE_WIDTH
                   + MAX_CTR_WIDTH+MAX_VAL_WIDTH
  ALLOC_DATA_WIDTH = CNTRL_BITS_WIDTH+THIS_TAG_BITS
  EPC is a control field. Included in CNTRL_BITS_WIDTH.
  For ITTAGE: IT_CNTRL_BITS_WIDTH also includes
  IT_MAX_TGT_WIDTH.
- tage_hash.sv abandoned in favor of tables generating
  hashes locally. Same approach adopted for ITTAGE.
- Added tage_table_hash_rules.md as planning document.
- Added ittage_table_hash_rules.md as planning document.

### Shared planning documents
    - planning/arch/bp_arb_spec.md                    In progress
        - Dynamic prediction/training arbitration balancing
    - planning/arch/bp_cluster.md                     In progress
        - Branch prediction cluster summary data
    - planning/arch/sram_init.md                      Complete
        - Post reset RAM initialization operation
    - planning/testbenches/manual_tb_decisions.md     Complete
        - General rules for manual testbench creation

### TAGE decomposition
- RTL is available
    - Unit testbenches written
    - Manual testbench written
    - Line coverage > 90%
    - Directed validation in progress
    - Formal validation not started
- BP-006 through BP-032: complete.
- BP-041 manual checks for tage CTR and USE complete
    - tage_cntrl_ctr_update_rules.md -- updated and verified
    - tage_cntrl_use_update_rules.md -- corrected and verified
      session-045. All 6 USE rows pass.
- Tage planning documents
    - planning/arch/tage_cntrl_alloc_rules.md         Draft
        - Table entry allocation rules
    - planning/arch/tage_cntrl_ctr_update_rules.md    Complete
        - CTR field update rules
    - planning/arch/tage_cntrl_decisions.md           Complete
        - TAGE control behavior, conventions and rules
    - planning/arch/tage_cntrl_uaon_update_rules.md   Draft
        - UAON (Use ALT on newly allocated)  trigger rules
    - planning/arch/tage_cntrl_use_update_rules.md    Complete
        - USE(ful) field update rules. Corrected session-045.
    - planning/arch/tage_table_hash_rules.md          Complete
        - Address and tag generation hashing
    - planning/interfaces/tage_interfaces.md          Complete
        - TAGE module interface contracts
    - planning/interfaces/tage_table_interfaces.md    Complete
        - TAGE table module interface contracts

### ITTAGE decomposition
- RTL is available
    - Unit testbenches written
    - Line coverage < 90% in progress
    - Directed validation not started
    - Formal validation not started
- BP-034 - BP-042 complete (BP-033 abandoned)
- ITTage planning documents
    - planning/arch/ittage_cntrl_alloc_rules.md         Draft
        - Table entry allocation rules
    - planning/arch/ittage_cntrl_ctr_update_rules.md    Complete
        - CTR field update rules. 33-row table. session-045.
    - planning/arch/ittage_cntrl_decisions.md           Complete
        - ITTAGE control behavior, conventions and rules
    - planning/arch/ittage_cntrl_uaon_update_rules.md   Draft
        - UAON (Use ALT on newly allocated)  trigger rules
    - planning/arch/ittage_cntrl_use_update_rules.md    Draft
        - USE(ful) field update rules. Corrected session-045.
    - planning/arch/ittage_table_hash_rules.md          Complete
        - Address and tag generation hashing
    - planning/interfaces/ittage_interfaces.md          Complete
        - ITTAGE module interface contracts
    - planning/interfaces/ittage_table_interfaces.md    Complete
        - ITTAGE table module interface contracts

### Shared components track
- components/rtl  components/tb

---

# HAND-FIX Records

- HAND-FIX-001 applied to tage_table.sv:
    - Signals use_we_s0/s1 and epc_we_s0/s1 now gate on
      prm_alt_match (prm_match | alt_match) instead of
      prm_match alone. prm_alt_match_s0 and
      prm_alt_match_s1 signals added.
    - Debt #29 added and immediately closed.
    - Applied after BP-010c.
    - Recorded in session-handoff-023.

- HAND-FIX-002 applied to tage_cntrl.sv:
    - Signal tage_use_alt_on_na now set only when
      uaon_trig AND counter MSB both set:
      meta_p1[s].tage_use_alt_on_na =
        uaon_trig_p1[s] & uaon[s][3];
    - Debt #30 added and immediately closed.
    - Applied after BP-010c.
    - Recorded in session-handoff-023.

- HAND-FIX-003 applied to tage_cntrl.sv:
    - T0 CTR update condition corrected in
      ctr_upd_comb u_both_t0 path.
      u_resolved replaced with !u_mispredict.
      BIM prediction correctness
      (pred_tkn == resolved_taken) is the correct
      INC/DEC gate, not branch outcome alone.
    - Citeable: tage_cntrl_ctr_update_rules.md
      rows 13a-d.
    - Applied as part of BP-041.
    - Recorded in session-handoff-045.

  NOTE: HAND-FIX-003 was later reverted in BP-043a. The fix
  was a false fail caused by an error in the planning document
  for T0 CTR update

---

# BUG Records

- BUG-001: HAND-FIX-003. T0 CTR INC/DEC condition
  wrong in tage_cntrl.sv. Found by tage_ctr_test
  row 13a. Fixed BP-041. See session-handoff-045.

