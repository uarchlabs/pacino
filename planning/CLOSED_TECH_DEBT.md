<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
---

## Technical Debt

| # | Item                                   | Resolution path                 |
|---|----------------------------------------|---------------------------------|
| 8  | CLI-001: lp_hit missing from          | Closed BP-017a                  |
|    | loop_pred_interfaces.md field list    |                                 |
| 9  | CLI-002: idx/tag vs lp_set/lp_tag     | Closed BP-017a                  |
|    | naming in loop_pred_interfaces.md     |                                 |
| 10 | CLI-004: lp_set vs idx in             | Closed BP-017a                  |
|    | bp_loop_meta_t (bp_structs_pkg.sv)    |                                 |
| 11 | CLI-008: mixed prefix in              | Closed BP-017b                  |
|    | lp_pred_t (bp_structs_pkg.sv)         |                                 |
| 12 | CLI-011: port naming convention       | Closed BP-018                   |
|    | not applied to loop_pred.sv           |                                 |
| 13 | CLI-012: port naming convention       | Closed                          |
|    | not applied to ubtb.sv                | Closed                          |
| 14 | TI7: bp_tage_meta_t migration to      | Closed                          |
|    | tage_pred_meta_t pending. Both        | Closed                          |
|    | retained during transition.           |                                 |
| 15 | CLOSED. EPC field semantics now       | Field implemented; write path   |
|    | implemented and documented.           | modified BP-044c. Live work is  |
|    |                                       | EPC write proof, see #55/#56.   |
| 19 | uaon_ff logic in tage_cntrl.sv is incorrect.     | Closed in BP-008b    |
|    | BP-008a-2 prompt erroneously specified decrement |                      |
|    | unconditionally at predict time. UAON is update  |                      |
|    | time only. See UAON Modification During Update   |                      |
|    | in tage_cntrl_useful_update_rules.md.            |                      |
| 20 | T1-T4 index and tag hashing incorrect in         | Closed BP-007e       |
|    | tage_cntrl. tage_cntrl generates slot-independent|                      |
|    | hashes from fld_hist_p0 and forwards to tables.  |                      |
|    | This is wrong. Each table derives its own hashes |                      |
|    | locally. tage_cntrl hash logic must be removed.  |                      |
| 21 | tage_table does not derive its own index and tag | Closed in BP-007f.   |
|    | hashes. fld_hist_p0 must be added as a direct    |                      |
|    | input to tage_table. Each table must compute its |                      |
|    | own hashes locally using table-specific history  |                      |
|    | lengths. Hash functions must be defined as       |                      |
|    | planning elements before re-running tage_table.  |                      |
| 22 | T0 CTR stored in tage_pred_meta_t as 3b          | Closed in BP-008b.   |
|    | zero-padded value when T0 is provider.           |                      |
|    | tage_prm_ctr field is 3b but T0 CTR is 2b.       |                      |
|    | Update path must not interpret tage_prm_ctr      |                      |
|    | MSB as direction when tage_prm_comp == 0.        |                   .  |
|    | Direction must be taken from tage_prm_pred_tkn   |                      |
|    | not tage_prm_ctr[2].                             |                      |
|    |                                                  |                      |
| 23 | Modify prompt validation script to test for      | Closed               |
|    | new Task-ID field                                |                      |
| 24 | The TAGE_TBL_* vectors are now the authoritative | Closed               |
|    | per-table parameter source. A cleanup pass is    |                      |
|    | needed to remove or alias the redundant scalar   |                      |
|    | parameters (TAGE_T0_WAYS, TAGE_T1_BANKS,         |                      |
|    | TAGE_T1_ENTRIES, etc.) and fix the FIXME-flagged |                      |
|    | consumers (tage_cntrl, tage_hash, bp_structs).   |                      |
| 25 | Context Loaded paths for bp_defines_pkg.sv and | Closed, will-not-fix |
|    | bp_structs_pkg.sv use short paths rtl/ in      |                      |
|    | BP-007d through BP-008b. Correct to            |                      |
|    | frontend/branch_predictor/rtl/ prefix.         |                      |
| 26 | TBL_SEL_WIDTH default in tage_table.sv:            | Closed           |
|    | Uses $clog2(TAGE_NUM_TABLES)+1 instead of          |                  |
|    | TAGE_TBL_SEL_WIDTH. Not fixed in BP-009a-1 because |                  |
|    | testbench implicitly relies on the wrong value.    |                  |
|    | Resolve when testbench is updated for BP-010.      |                  |
| 27 | bw_ram BANKS=2 hardcoded as magic number in     | Closed            |
|    | RAM_ENTRIES and bw_ram instantiation in tage_bim.sv |               |
|    | and tage_table.sv. Should be a local parameter  |                   |
|    | Fix in cleanup pass after BP-010                |                   |
| 28 | planning/arch/ and planning/interfaces/ have    | Closed            |
|    | drifted. tage_interfaces.md is the current      | Manual fix        |
|    | authoritative source for TAGE. Reconcile arch   |                   |
|    | docs with interface docs before bp_cluster impl.|                   |
| 29 | use_we and epc_we in tage_table.sv gated by     | Closed. HAND-FIX-001 applied  |
|    | prm_match only. When using_primary=0, USE and   | directly to tage_table.sv.    |
|    | EPC writes silently dropped for alt provider    | prm_alt_match_s0/s1 added.    |
|    | table. Rules Table 7 rows 5,6 not implemented.  | Found BP-010c, fixed session  |
|    | Both slots affected.                            | 022.                          |
| 30 | tage_use_alt_on_na in tage_cntrl.sv set from        | Closed. HAND-FIX-002 applied   |
|    | uaon_trig alone. Flag should reflect whether UAON   | to tage_cntrl.sv. Now gated    |
|    | mux actually switched prediction source, not merely | on uaon_trig_p1[s] & uaon[s][3]|
|    | whether trigger condition was met. Counter threshold| Found BP-010e, fixed           |
|    | not checked. Both slots affected.                   | session-022.
| 31 | Defect: t_idx_r1/t_tag_r1 undriven. Found BP-011                 | closed BP-012. |
| 32 | Defect: T0 prm_ctr mis-extraction. Found BP-011                  | closed BP-012. |
| 33 | Simultaneous prediction and update protocol undefined.           | closed |
|    | No signals defined for same-cycle pred+upd to overlapping       |   |
|    | entries. Read-during-write contract covers mutual exclusion     |   |
|    | assumption but does not define arbitration, ordering, or stall  |   |
|    | signaling when both are valid in the same cycle.Define protocol |   |
|    | and additional signals before bp_cluster integration. Requires  |   |
|    | interface doc update and new testbench coverage.                |   |
| 34 | T0 CTR update in tage_cntrl.sv keys on pred_crtFix           | closed |
|    | before bp_cluster(correct/wrong) instead of                  | bp-015 |
|    | resolved_taken tointegration. Changedetermine                   |   |
|    | increment or decrement direction.ctr_upd_comb to                |   |
|    | usepred_crt=1 always adds 1, moving a correctly                 |   |
|    | resolved_taken topredicted not-taken branch toward              |   |
|    | the takenselect INC or DEC.side. Standard BIM                   |   |
|    | behavior: resolved_taken=1Add a targeted-> INC,                 |   |
|    | resolved_taken=0 -> DEC. Found BP-014d,regression               |   |
|    | testTC-36. RTL not modified in BP-014d.covering row             |   |
|    | 13a after fix applied.                                          |   |
| 35 | No automated check that all expected test cases    | Superceded by coverage |
|    | are present and executed in tb_tage.sv. Claude     | plan                   |
|    | Code incorrectly reported BP-014f Results          |                        |
|    | Capture as already written because it saw          |                        |
|    | populated section markers. Risk: a session         |                        |
|    | completes with fewer tests than specified and      |                        |
|    | the shortfall goes undetected.                     |                        |
| 36 | sim_tage_table TC6: USE field update not reflected | Closed                 |
|    | in cntrl_bits_p1 after write. hit=1, cntrl=09,     | Verified session-028:  |
|    |                                                    | TC6 passes with cntrl=39      |
|    |                                                    | as expected                   |
|    |                                                    | Defect resolved by HAND-FIX-001 |
|    |                                                    | in session-022. No further    |
|    |                                                    | action required.              |
|    | expected cntrl=39. Pre-existing defect revealed    | tb_tage_table.sv TC6 expected |
|    | when PINMISSING fix in BP-019a allowed             | value. Fix before bp_cluster. |
|    | sim_tage_table to compile and run.                 |                               |
| 44 | Confirm ittage_pred_strong change in  | CLOSED                          |
|    |                                       | Changed session-040: provider   |
|    | ittage_cntrl_decisions.md.            | ctr was !=3 & !=4, now > 0 (NOT |
|    |                                       | NULL). Ensure #43 does not      |
|    |                                       | impact any testcase.            |
| 45 | tage_cntrl / tage_table update-index  | THIS IS INVALID DESCRIPTION IS WRONG |
|    | simplification                        | 2D update/alloc index bus is    |
|    |                                       | wrong: should be per-table      |
|    | (Structural rework, see #xx.)         | ports. T0 CTR always updated    |
|    |                                       | needs an index; prm and alt CTR |
|    |                                       | both updatable; useful uses     |
|    | Real fix moved to #66                 | prm_idx or alt_idx. Specify     |
|    |                                       | upd_index_u0[s], alc_index_u0[s]|
|    |                                       | bim_index_u0[s]=PC[MAX_IDX-1:1].|
|    |                                       | Test if alc_index needed. Add   |
|    |                                       | tage_cntrl_interfaces.md.       |

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
| 50 | sram_init FAST_INIT  | CLOSED. w. BP-040.                            |
|    | behavior             | ittage.sv nonconformance fixed.               |
|    |                      | All modules audited.                          |
| 51 | CTR/USE/TGT update   | CLOSED BP-044b/c. |
|    | rule audit           | Bug 4 (BP-039) found using_primary condition  |
|    |                      | inverted in ittage_cntrl.sv ctr_upd block.    |
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
| 53 | tage_ctr_test rows   | CLOSED with BP-041.md                        |
|    | 14-17 failing        | pcomp CTR write not landing in T4 RAM for    |
|    |                      | rows 14-17. Root cause was test state        |
|    |                      | contamination from rows 13 into rows 14-17.  |
| 54 | tage ctr tests       | CLOSED.                                          |
|    |                      | Planning document tage_cntrl_ctr_update_rules.md |
|    |                      | was updated and confirmed with BP-041 manual |
|    |                      | tests. The new table is more explicit on X   |
|    |                      | handling and backed by new assertions.       |
|    |                      | Existing IA tests need audit and retrofit.   |
|    |                      | BP-043 will address this.                    |
| 55 | tage EPC write proof.                  | CLOSED BP-056 |
|    |                                        | epc_we gate changed BP-044c     |
|    | Changed RTL, never proven by readback. | (USE rider). Seed entry, drive  |
|    |                                        | EPC-writing update, read EPC    |
|    |                                        | back via prediction, confirm    |
|    |                                        | landing. Use bw_write backdoor. |
| 56 | ittage EPC write proof.                | CLOSED with BP-050b |
|    |                                        | Same as #55 for ittage.         |
|    | Changed RTL, never proven by readback. | epc_we_s0/s1 fixed BP-044c      |
|    |                                        | alongside use_we. No positive   |
|    |                                        | test. Readback-verify per       |
|    |                                        | provider, UP=1 and UP=0.        |
| 57 | ittage TGT target replacement.         | CLOSED. BP-049a
|    |                                        | TGT write path not audited.     |
|    | Untested. Successor to #51.            | #51 suspect for same provider-  |
|    |                                        | gating defect as CTR/USE.       |
|    |                                        | Target written on mispredict    |
|    |                                        | when CTR null only. Trace path, |
|    |                                        | readback-verify reachable rows. |
|    |                                        | ittage only (no TAGE tgt).      |
| 58 | tage UAON trigger rules.               | CLOSED with BP-057              |
|    |                                        | tage_cntrl_uaon_update_rules.md |
|    | Tested only as setup, never as DUT.    | is Draft. Promote to authority, |
|    |                                        | directed test per row, prove    |
|    |                                        | use_alt_on_na fires/clears.     |
|    |                                        | BUG-003 found and fixed.        |
| 59 | ittage UAON trigger rules.             | CLOSED BP-051 |
|    |                                        | ittage_cntrl_uaon_update_rules. |
|    | Tested only as setup, never as DUT.    | md is Draft. Same as #58. USE   |
|    |                                        | tests relied on UAON firing as  |
|    |                                        | precondition; never verified.   |
| 60 | tage aging / epoch path. Entire path   | CLOSED with BP-058              |
|    |                                        | Supersedes #41. All tests run   |
|    | dark.                                  | tage_enable_aging=0. Drive      |
|    |                                        | aging high, exercise EPC-vs-    |
|    |                                        | epoch compare and USE decrement |
|    |                                        | over interval. Confirm interval |
|    |                                        | reachable at current params     |
|    |                                        | first (cf #39).                 |
| 61 | ittage aging / epoch path. Entire      | CLOSED. BP-052                  |
|    |                                        | Same as #60 for ittage.         |
|    | path dark.                             | Consumes the EPC field whose    |
|    |                                        | write changed BP-044c (see #56).|
| 62 | tage allocation policy + write gating. | CLOSED BP-059                   |
|    |                                        | Allocation treated as residue   |
|    | Never the feature under test.          | to invalidate, never verified.  |
|    | Successor to #51.                      | Test which table allocates,     |
|    |                                        | alloc write-enable gating,      |
|    |                                        | alloc index. Do #66 first.      |
|    |                                        | RAM-level write isolation       |
|    |                                        | verified (TC-95).               |
| 63 | ittage allocation policy + gating.     | CLOSED with BP-053              |
|    |                                        | Same as #62. Alloc on           |
|    | Never the feature under test.          | mispredict, CTR-null condition, |
|    | Successor to #51.                      | alloc_we gating. Readback-      |
|    |                                        | verify allocated entry state.   |
| 64 | tage prediction-side correctness.      | CLOSED BP-060                   |
|    |                                        | Prediction path exercised only  |
|    | Not directed-tested.                   | as setup for update tests.      |
|    |                                        | Directed-test provider          |
|    |                                        | selection, using_primary,       |
|    |                                        | pred_strong, target mux given   |
|    |                                        | seeded entries.                 |
| 65 | ittage prediction-side correctness.    | CLOSED BP-054/054a              |
|    |                                        | Same as #64 for ittage.         |
|    | Not directed-tested.                   | Resolves #42 test aspect:       |
|    |                                        | verify provider/using_primary/  |
|    |                                        | target operate at s2 not s3.    |
| 66 | TAGE structural rework                 | CLOSED BP-045                   |
|    | Sequence before TAGE alloc #62.        | collapsed to shared per-slot buses; |
|    |                                        | t_alt_upd_index_u0 added for the |
|    |                                        | dual-CTR case; BP-045, session-047 |
|    | | Currently TAGE has 2d buses for alc and upd index, there is one bus for each |
|    | | table, this is incorrect, the connection should be shared buses across |
|    | | these signals, the only multi-dimension is the width of the bus and the prediction slot, |
|    | | so this:
|    | |   output logic [TAGE_MAX_CTR_WIDTH-1:0] t_prm_ctr_wd_u0[0:TAGE_NUM_TABLES-1][0:NUM_PRED_SLOTS-1]|
|    | | should be this
|    | |   output logic [TAGE_MAX_CTR_WIDTH-1:0] t_prm_ctr_wd_u0[0:NUM_PRED_SLOTS-1] |
|    | | same thing for each of these: |
|    | |   `t_prm_ctr_wd_u0` |
|    | |   `t_alt_ctr_wd_u0` |
|    | |   `t_use_wd_u0` |
|    | |   `t_epc_wd_u0` |
|    | |   `t_alc_wd_u0` |
|    | |   `t_prm_tbl_sel_u0` |
|    | |   `t_alt_tbl_sel_u0` |
|    | |   `t_alc_tbl_sel_u0` |
|    | |   `t_upd_index_u0` |
|    | |   `t_alc_index_u0` |
|    | | |
| 71 | tage round-trip                        | CLOSED BP-061                   |
|    |                                        | Mixed ctr/use/alloc/epc in one  |
|    | Combined test, run only after          | flow. Run ONLY after            |
|    | individual tests pass                  | #55,58,60,62,64 each proven     |
|    |                                        | alone -- mixing before          |
|    |                                        | isolation reproduces the multi- |
|    |                                        | cause ambiguity that stalled    |
|    |                                        | BP-044.                         |
| 72 | ittage round-trip (capstone).          | CLOSED BP-055                   |
|    |                                        | Mixed ctr/use/alloc/epc/tgt in  |
|    | Combined test, run only after          | one flow. Run ONLY after        |
|    | individual tests pass                  | #56,57,59,61,63,65 each proven  |
|    |                                        | alone. Same isolation-first     |
|    |                                        | rule as #71.                    |
|    |                                        | Allocation RAM-level write      |
|    |                                        | isolation verified, selected    |
|    |                                        | table written, other tables     |
|    |                                        | shown unchanged                 |
| 76 | ittage should have independent index   | CLOSED with BP-048 |
|    | buses for primary and alternative      | |
|    | table updates.                         | |
|    | | Since there are different history lengths, and the indexes are |
|    | | hashed based on history length we do in fact need an index bus |
|    | | for primary and alternative. |
|    | | the names should be t_prm_upd_index_u0 and t_alt_upd_index |
|    | | Secondly the names of the ports of ittage_cntrl that touch the tables |
|    | | should use the same convention as tage_cntrl, and begin with t_      |



---

