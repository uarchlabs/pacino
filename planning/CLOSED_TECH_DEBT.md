<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
---

## Technical Debt

| # | Item                                   | Resolution path                 |
|---|----------------------------------------|---------------------------------|
| 1  | NUM_PRED_SLOTS=1 reduction.           | CLOSED by BP-128 (session-078). |
|    | Generate removal and NUM_PRED_SLOTS=1 | NUM_PRED_SLOTS is 1 or 2 from   |
|    | tests pending.                        | BP_NUM_PRED_SLOTS in            |
|    |                                       | bp_defines_pkg.sv; every bpu,   |
|    |                                       | ftq and fe_top target passes at |
|    |                                       | both, 106 _1slot targets in the |
|    |                                       | regression. History widths      |
|    |                                       | BP-129, BP-130. Was: Cleanup    |
|    |                                       | session after TAGE complete.    |
|    |                                       | Dual-slot *testing* tracked     |
|    |                                       | separately in #74.              |
|    | SESSION-064: NEW BLOCKER.             | tb_bp_cluster indexes generate  |
|    |                                       | blocks by literal and $fatal(1)s|
|    |                                       | at elaboration if the package   |
|    |                                       | value is not 2. Reduction now   |
|    |                                       | requires reworking that tb.     |
|    |                                       | loop_pred and tb_loop_pred DO   |
|    |                                       | elaborate at 1 (BP-091).        |
| 4  | predecode.sv clk/rstn unused          | CLOSED session-078 (Jeff), moot:|
|    |                                       | predecode.sv deleted by BP-118  |
|    |                                       | (TD#143). Was: Resolve at       |
|    |                                       | pipeline stage assign.          |
| 5  | v_op_class_t (decode_pkg.sv), 8 bits  | CLOSED session-078 (Jeff),      |
|    | since BP-124. Values 1 (was VALU_INT, | accepted. Reserved in the type; |
|    | DECODE-007) and 2 (was VALU_FP,       | renumbering moves every VOP     |
|    | DECODE-006) unassigned, marked        | value for no gain. Was: ENUM    |
|    | reserved in the enum.                 | hole at 7'd2 (VALU_FP).         |
| 7  | curs/curs_v rollback undefined.       | CLOSED by BP-122 (session-076): |
|    | Seznec uses SLIM structure. Inline    | checkpoint per FTQ entry,       |
|    | fields have no defined                | restore option A. TD#169.       |
|    | checkpoint/rollback path.             | RULED session-075 (Jeff): built |
|    |                                       | with the loop predictor's       |
|    |                                       | read-before-write update,       |
|    |                                       | TD#169, BP-122.                 |
|    |                                       | Was:                            |
|    |                                       | Resolve at bp_cluster impl or   |
|    |                                       | migrate to SLIM-style external  |
|    |                                       | structure. See rollback test    |
|    |                                       | items #69/#70.                  |
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
| 16 | ALLOC_DATA_WIDTH padding when         | CLOSED session-078 (Jeff). No   |
|    | THIS_ < MAX_ -- unused bits between   | instance exists: T0 is          |
|    | EPC and TAG fields.                   | tage_bim.sv, not a tage_table   |
|    |                                       | instance, and T1-T4 have every  |
|    |                                       | THIS_ width equal to its MAX.   |
|    |                                       | Was: Resolve at T0              |
|    |                                       | implementation.                 |
| 17 | BP-007b signal naming nonconforming.  | CLOSED session-078 (Jeff). The  |
|    | _s0/_s1 suffixes used instead of      | naming rule covers ports only   |
|    | array indexing per                    | (tage_table_interfaces.md, Port |
|    | tage_table_interfaces.md.             | Naming Convention); every       |
|    | Prompt author error.                  | tage_table port is array-       |
|    |                                       | indexed. alc_index_u0 is        |
|    |                                       | THIS_INDEX_BITS wide. T0 is     |
|    |                                       | tage_bim.sv, so the T0 tag hash |
|    |                                       | is moot. Was: BP-007c scope.    |
| 18 | Definition of T0 fields/behavior      | CLOSED by BP-133 (session-079,  |
|    |                                       | Jeff). T0 trains when           |
|    |                                       | use_alt_on_na chooses it as the |
|    |                                       | provider over a tagged primary: |
|    |                                       | it steps toward the resolved    |
|    |                                       | direction through a second      |
|    |                                       | write path on tage_bim's alt    |
|    |                                       | update bus                      |
|    |                                       | (tage_cntrl_ctr_update_rules.md |
|    |                                       | rows 19.1-19.8). The primary    |
|    |                                       | keeps the rows 9/10 rule. Was:  |
|    |                                       | Prediction side closed. Update  |
|    |                                       | side pending T0 implementation. |
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
| 37 | trx_type forwarded combinationally    | CLOSED by BP-126 (session-077), |
|    | from arb_grant_upd instead of from    | negative result: trx_type is    |
|    | registered arb_trx_r.trx_type.        | used only at entry (pred_val_p1 |
|    | Verify grant signal stability through | takes pred_val_p0 and not       |
|    | tage_cntrl pipeline under concurrent  | trx_type; the write strobes act |
|    | pred+upd.                             | at u0 in the grant cycle).      |
|    |                                       | tb_tage trx_stab monitor and    |
|    |                                       | trx_stab_tst, 0 violations.     |
|    |                                       | Was: Investigate before         |
|    |                                       | closing. When concurrent        |
|    |                                       | pred+upd tests are added (arb   |
|    |                                       | item #73), verify grant         |
|    |                                       | stability through the pipeline. |
|    |                                       | If unstable, promote            |
|    |                                       | arb_trx_r.trx_type and adjust   |
|    |                                       | write-enable timing. Tasked in  |
|    |                                       | BP-126 (session-077).           |
| 38 | Verilator 5.048 covergroup #7099      | CLOSED by BP-126 (session-077): |
|    | status not yet verified.              | Verilator 5.048 does not        |
|    |                                       | support covergroups; each is    |
|    |                                       | ignored with COVERIGN and       |
|    |                                       | records no coverage. Issue 7099 |
|    |                                       | closed 2026-06-06 through       |
|    |                                       | #7117, after 5.048              |
|    |                                       | (2026-04-26). Revisit on an     |
|    |                                       | upgrade past #7117. Was:        |
|    |                                       | Re-check #7099 status in 5.048  |
|    |                                       | release notes before closing.   |
|    |                                       | Tasked in BP-126 (session-077). |
| 39 | Rule 2 starvation override            | CLOSED, MOOT session-076.       |
|    | reachability.                         | BP-121 replaced the credit      |
|    | SC_PRED_CREDITS=4 <                   | rules (bp_arb_spec.md 4.5); the |
|    | SC_STARVE_THRESH=8.                   | parameter relationship no       |
|    |                                       | longer exists.                  |
|    |                                       | Was:                            |
|    |                                       | ANSWERED BP-094, needs a        |
|    |                                       | DECISION. Measured: SC_PRED_    |
|    |                                       | CREDITS=4 and rule 4 resets the |
|    |                                       | starve counter after 4 grants,  |
|    |                                       | so starve_ctr tops out at 4 and |
|    |                                       | NEVER reaches 8. The override is|
|    |                                       | unreachable in traffic. Group H |
|    |                                       | test H6 seeds the counter and   |
|    |                                       | proves the implemented arm obeys|
|    |                                       | 4.5 rule 2; it does not prove   |
|    |                                       | reachability, and says so.      |
|    |                                       | Either raise PRED_CREDITS above |
|    |                                       | STARVE_THRESH, lower the        |
|    |                                       | threshold, or record the arm as |
|    |                                       | dead code kept for parameter    |
|    |                                       | flexibility. Parameter choice,  |
|    |                                       | not a testbench problem.        |
| 40 | TB-ARB-05 spec discrepancy.           | CLOSED session-078 (Jeff). The  |
|    | Old "backpressure 2 cycles" note did  | note is gone. Was:              |
|    | not match TAGE_UQ_DEPTH=8.            | bp_arb_spec.md testbench section|
|    | No RTL risk.                          | (was 10.1) removed session-057; |
|    |                                       | tb requirements now live in the |
|    |                                       | implementing task file.         |
| 42 | Pipeline diagram shows ITTAGE at s3,  | CLOSED session-070. The SC      |
|    | should be s2 (alongside FTB, TAGE).   | gate is met and bp_cluster.md   |
|    |                                       | is corrected at all three sites: |
|    |                                       | the ITTAGE Stage bullet, the    |
|    |                                       | Pipeline Staging block and      |
|    |                                       | Redirect Architecture, which    |
|    |                                       | carried a raw-at-p2 /           |
|    |                                       | final-at-p3 split with no       |
|    |                                       | signals behind it. p2 confirmed |
|    |                                       | by fe_decisions.md 1,           |
|    |                                       | ittage_interfaces.md and the    |
|    |                                       | RTL: ittage.sv and              |
|    |                                       | ittage_cntrl.sv declare only    |
|    |                                       | _p2 and contain no _p3 signal.  |
|    |                                       | #65 is CLOSED, BP-054           |
| 43 | Reduce ITTAGE CTR width 3b -> 2b.     | CLOSED session-078 (Jeff). The  |
|    |                                       | counter stays 3 bits; no change.|
|    |                                       | Was: impacts bp_defines_pkg.sv, |
|    |                                       | ittage_table_interfaces.md, RTL |
|    |                                       | and testbenches.                |
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
| 49 | Arb queue status pin renaming.         | CLOSED by BP-132 (session-078): |
|    |                                        | pins renamed tage_pq_not_full / |
|    |                                        | tage_uq_not_full and the ittage_|
|    |                                        | pair in tage and ittage and     |
|    |                                        | every reference; the bp_cluster |
|    |                                        | boundary keeps tage_upd_rdy /   |
|    |                                        | ittage_upd_rdy (ruled, Jeff).   |
|    |                                        | Was:                            |
|    |                                        | pq_not_full/upd_rdy ->          |
|    |                                        | tage_pq_not_full/tage_uq_not_   |
|    |                                        | full and ittage_ equivalents.   |
|    |                                        | Scope: RTL, tb, bp_arb_spec.md, |
|    |                                        | tage_interfaces.md,             |
|    |                                        | ittage_interfaces.md.           |
|    |                                        | Session-063: bp_cluster ALREADY |
|    |                                        | prefixes these at its boundary, |
|    |                                        | so the rename inside tage.sv and|
|    |                                        | ittage.sv is cosmetic alignment,|
|    |                                        | not a blocker.                  |
| 52 | Move arb logic into submodule out of   | CLOSED by BP-132 (session-078): |
|    | top in tage and ittage.                | arbitration in tage_arb.sv and  |
|    | (Refactor; pairs with #73 test.)       | ittage_arb.sv; the tops keep the|
|    |                                        | fast-init muxes and the per-    |
|    |                                        | table index select. Group H 2011|
|    |                                        | / 1431 unchanged.               |
|    |                                        | Was:                            |
|    |                                        | Top modules should be           |
|    |                                        | structural only. New arb module |
|    |                                        | for tage and ittage. Co-        |
|    |                                        | sequence with arb test #73.     |
| 67 | tage sram_init non-fast path.          | CLOSED by BP-126 (session-077): |
|    | Untested here; confirm not elsewhere.  | sim_tage already ran the        |
|    | SESSION-064: now extends to the        | sram_init walk; tage_rdy_tst    |
|    | CLUSTER -- sim_bp_cluster and          | checks every T0 to T4 entry     |
|    | cov_bp_cluster pass all three          | after it. New                   |
|    | fast-init plusargs.                    | sim_bp_cluster_init runs all    |
|    |                                        | three walks, the same 2011      |
|    |                                        | checks as sim_bp_cluster. Was:  |
|    |                                        | All tests used +FAST_INIT,      |
|    |                                        | bypassing real sram_init        |
|    |                                        | cycling. Confirm the COMP tests |
|    |                                        | cover the non-fast path; do not |
|    |                                        | assume. A plusarg running a     |
|    |                                        | SHORT init walk rather than     |
|    |                                        | none would also make the SC     |
|    |                                        | arbiter rule-1 guard reachable  |
|    |                                        | from the ports (see BP-094      |
|    |                                        | H2b). Tasked in BP-126          |
|    |                                        | (session-077).                  |
| 68 | ittage sram_init non-fast path.        | CLOSED by BP-126 (session-077): |
|    |                                        | sim_ittage now runs the walk    |
|    |                                        | and new sim_ittage_fast the     |
|    |                                        | fast init (P-2, confirmed);     |
|    |                                        | tb_ittage checks every IT1-IT5  |
|    |                                        | entry after init. Was: Same as  |
|    |                                        | #67. Tasked in BP-126           |
|    |                                        | (session-077).                  |
| 69 | tage rollback / history recompute.     | CLOSED by BP-126 (session-077): |
|    | Dark; tracks arch TBDs.                | the tb_bp_cluster FOLD monitor, |
|    |                                        | a history model of its own,     |
|    |                                        | checks every TAGE T1-T4 index   |
|    |                                        | and tag on every prediction and |
|    |                                        | on the first after each         |
|    |                                        | rollback and corrected          |
|    |                                        | rollback. Was: G20/G21/G22      |
|    |                                        | RESOLVED session-054. Fold      |
|    |                                        | recompute proven in-sim BP-072. |
|    |                                        | Rollback STIMULUS now exists    |
|    |                                        | AND is exercised: tb_bp_cluster |
|    |                                        | E1/E2 drive checkpoint and      |
|    |                                        | rollback through the cluster.   |
|    |                                        | The tage-side recompute is      |
|    |                                        | still not checked end to end.   |
|    |                                        | See TD #7. Tasked in BP-126     |
|    |                                        | (session-077).                  |
| 70 | ittage rollback / history recompute.   | CLOSED by BP-126 (session-077): |
|    |                                        | the FOLD monitor, as #69, for   |
|    |                                        | ITTAGE IT1-IT5. Was: Same as    |
|    |                                        | #69 for ittage. Tasked in       |
|    |                                        | BP-126 (session-077).           |
| 73 | Arbitration layer behavioral test.     | CLOSED BP-094 group H. All      |
|    | Pairs with refactor #52.               | seven bp_arb_spec 4.5 grant     |
|    |                                        | rules plus tage consumer_ready  |
|    |                                        | tested, hierarchically. Folds in|
|    |                                        | #37, #39, #40. Residual: #39 is |
|    |                                        | a parameter decision, and       |
|    |                                        | concurrent pred+upd for TAGE and|
|    |                                        | ITTAGE (not SC) is untouched.   |
| 74 | Dual-slot (NUM_PRED_SLOTS=2) test.     | CLOSED by BP-136 (session-080,  |
|    |                                        | Jeff). Every slot-1 path BP-135 |
|    |                                        | listed is checked against a     |
|    |                                        | rule-derived value: TAGE in     |
|    |                                        | tb_tage_manual (CTR, USE/EPC,   |
|    |                                        | UAON tests per slot), ITTAGE in |
|    |                                        | tb_ittage TC-SLOT-UPD and       |
|    |                                        | TC-SLOT-DUAL. m_t0_s1 and       |
|    |                                        | m_ittage_s1 now fail. Not       |
|    |                                        | covered: ITTAGE uaon[1], slot-1 |
|    |                                        | prediction-side effects. Was:   |
|    |                                        | bp_history part CLOSED          |
|    | bp_history dual-slot fold equivalence  | (BP-072), externally anchored   |
|    | proven; broader cluster dual-slot      | BP-073. SESSION-064: both slots |
|    | still partly deferred.                 | are now exercised together in   |
|    |                                        | tb_bp_cluster groups B, E, F and|
|    |                                        | G. The slot-1 UPDATE path across|
|    |                                        | TAGE/ITTAGE is covered by group |
|    |                                        | G only for the loop it drives.  |
|    |                                        | Reduction work in #1.           |
|    |                                        | Session-079 (Jeff): folded into |
|    |                                        | BP-135. KEPT after it (Jeff),   |
|    |                                        | narrowed. Unchecked on slot 1:  |
|    |                                        | TAGE T0 writes (rows 13a-13d,   |
|    |                                        | 19.x); alt USE/EPC (Table 7     |
|    |                                        | rows 5-6); the pred_diff steps  |
|    |                                        | (rows 3, 4, 9, 10); uaon[1];    |
|    |                                        | bim_upd_idx_u0[1]; every ITTAGE |
|    |                                        | slot-1 update through           |
|    |                                        | ittage_cntrl. Removing T0 or    |
|    |                                        | ITTAGE slot-1 writes passes     |
|    |                                        | regress.sh. BP-136.             |
| 75 | ittage has no fast versions of the     | CLOSED by BP-126 (session-077): |
|    | ittage sim targets.                    | sim_ittage_fast,                |
|    |                                        | +ITTAGE_FAST_INIT=1, 223/0.     |
|    |                                        | Was: The equivalent TAGE target |
|    |                                        | is sim_tage_fast. Create        |
|    |                                        | sim_ittage_fast. Tasked in      |
|    |                                        | BP-126 (session-077).           |
| 77 | scrub prompts and redact any absolute  | CLOSED by BP-132 (session-078): |
|    | path not using the RVA_ROOT env var    | no prompt changed; every        |
|    |                                        | absolute repo path in prompts/  |
|    |                                        | is a record of a past session   |
|    |                                        | (ruled, Jeff).                  |
|    |                                        | Was:                            |
|    |                                        | Not a design TD; tools and infra|
|    |                                        | task, possibly manual.          |
| 78 | RAS p3 undo-pop does not reverse a   | CLOSED by BP-133 (session-079,  |
|    | recursion pop.                       | Jeff). The undo-pop, and the    |
|    |                                      | undo of a whole RETURN_CALL,    |
|    |                                      | restore the recursion counts    |
|    |                                      | the p2 operation changed        |
|    |                                      | (ras_decisions.md 1). Reachable |
|    |                                      | since BP-121, when SC reverses  |
|    |                                      | a direction at p3. tb_ras TC-21 |
|    |                                      | (BP-064's pin, changed), TC-38; |
|    |                                      | tb_fe_top rec_undo (BP-134).    |
|    |                                      | Was: LEAVE AS-IS. BP-064 pins   |
|    |                                      | the current non-reversing       |
|    |                                      | behavior. Revisit at bp_cluster |
|    |                                      | integration if a p2/p3 repair   |
|    |                                      | over a recursion pop is ever    |
|    |                                      | required. Related: #79.         |
| 79 | RAS commit-stack recursion depth not | CLOSED by BP-133 (session-079,  |
|    | preserved.                           | Jeff), not a defect. The commit |
|    |                                      | stack has no recursion          |
|    |                                      | compression: every committed    |
|    |                                      | call is its own entry, so depth |
|    |                                      | is kept as repeated entries     |
|    |                                      | (tb_ras TC-39). commit_rctr     |
|    |                                      | removed by BP-134. Was: DEFER.  |
|    |                                      | The field is write-only and     |
|    |                                      | never read by any output path,  |
|    |                                      | so a wrong value degrades the   |
|    |                                      | fallback prediction only. Real  |
|    |                                      | fix needs a recursion-count     |
|    |                                      | source on the commit interface. |
|    |                                      | Decide at FTQ integration.      |
| 81 | tb_ftb coverage skews to br0.        | CLOSED by BP-126 (session-077): |
|    |                                      | 35 br1 checks (B1-*), sim_ftb   |
|    |                                      | 162 -> 197. Was: Optional       |
|    |                                      | symmetric br1 augment. Not a    |
|    |                                      | blocker; sim_ftb 99/0. Tasked   |
|    |                                      | in BP-126 (session-077).        |
| 82 | bp_history if/else-if slot cleanup.  | CLOSED by BP-129 (session-078,  |
|    |                                      | Jeff): one loop over branches,  |
|    |                                      | each case assigns the folds     |
|    |                                      | once.                           |
|    |                                      | Was:                            |
|    |                                      | decisions.md 3.5. Fold into the |
|    |                                      | next bp_history RTL touch. No   |
|    |                                      | behavior change.                |
| 83 | bp_history decisions.md s6.6 origin  | CLOSED session-078 (Jeff): the  |
|    | citation placeholders.               | external citation and its       |
|    |                                      | placeholders removed; the       |
|    |                                      | geometry is the standard        |
|    |                                      | O-GEHL / TAGE folding. Was:     |
|    |                                      | fill the commit sha / date.     |
| 84 | Producer/consumer end-to-end fold    | CLOSED by BP-126 (session-077): |
|    | check.                               | the FOLD monitor traces the     |
|    |                                      | folds through the TAGE, ITTAGE  |
|    |                                      | and SC ST1-ST3 index and tag    |
|    |                                      | hashes. Which PC bits the SC    |
|    |                                      | index takes is open (PD-17).    |
|    |                                      | Was: BP-073 proved the fold     |
|    |                                      | VALUE against the canonical     |
|    |                                      | definition; it did NOT run that |
|    |                                      | fold through the TAGE/ITTAGE    |
|    |                                      | table index hash. Cluster       |
|    |                                      | stimulus now exists and         |
|    |                                      | tb_bp_cluster group G drives a  |
|    |                                      | closed loop, but the FOLD is    |
|    |                                      | still not traced through the    |
|    |                                      | hash. SC ST1-ST3 additional.    |
|    |                                      | Tasked in BP-126 (session-077). |
| 87 | tage strong/medium/weak decode       | CLOSED BP-081 (session-060).    |
| 88 | tage_extd_ctr generation             | CLOSED BP-081 (session-060).    |
| 89 | ftb       | CLOSED by BP-133 (session-079, Jeff), without FTB        |
|    |           | storage. ftq_upd_conv has formed sc_upd_inp.branch_range |
|    |           | at the update since BP-119: bits 15:6 of the branch PC,  |
|    |           | the FTQ entry's block start plus the slot position, at   |
|    |           | either slot count. Was: Change the FTB definition to     |
|    |           | store 20 additional bits. These are PC bits [15:6] of    |
|    |           | branch location. These will be supplied to               |
|    |           | sc_upd_inp.branch_range.                                 |
| 90 | ftb       | CLOSED by BP-133 (session-079, Jeff), without FTB        |
|    |           | storage. ftq_upd_conv has formed                         |
|    |           | sc_upd_inp.backwards_branch at the update since BP-119:  |
|    |           | the resolved taken target below the branch PC, per slot; |
|    |           | sc_cntrl reads it only on a taken resolution. Was:       |
|    |           | Change the FTB to store 2 additional bits. The signs of  |
|    |           | the branch targets for conditional branch 0/1 should be  |
|    |           | stored as backwards_branch0/1. These will be supplied to |
|    |           | sc_upd_inp.backwards_branch. Two bits, one per           |
|    |           | prediction slot.                                         |
| 91 | bpc       | CLOSED session-063.                                      |
| 92 | bpc/sc    | CLOSED session-063 for the PC and phr; the three SC      |
|    |           | index folds were staged BP-090 and bp_arb_spec.md 6.1    |
|    |           | now names them (session-064). FULLY CLOSED.              |
| 94 | bp_arb_spec | CLOSED BP-081. Session-064: 6.1 now names the SC       |
|    |           | index folds; 3.4 and 5.x annotated so the                |
|    |           | <pred>_redir_* names are not read as ports.              |
|    |           | The closure text read "Sections 9/10 remain stubs."      |
|    |           | They do not: both read "Section removed", and 10 adds    |
|    |           | that testbench requirements derive from 4.5. Nothing     |
|    |           | is outstanding there and this TD tracks nothing.         |
|    |           | Corrected session-070; the Module Status row carried     |
|    |           | the same claim.                                          |
| 95 | tage      | CLOSED BP-081 (session-060).                             |
| 96 | bpc       | CLOSED BP-105. THERE IS NO FLUSH EVENT. A flush is a     |
|    |           | redirect: fe_decisions.md FE-14. A predictor is cleared  |
|    |           | by withholding its stage valid, which bp_cluster already |
|    |           | does. Corroborated by XiangShan, which has no flush port |
|    |           | on any predictor. The _px and ras_flush_* ports are      |
|    |           | REDUNDANT and retained; read ras_decisions.md 4.4.2      |
|    |           | before re-raising this.                                  |
| 97 | bp_arb    | CLOSED session-078 (Jeff). Not built and not needed:     |
|    |           | fetch presents each request straight to each predictor's |
|    |           | own queue (bp_arb_spec.md 8.1), and the cluster gates it |
|    |           | on the TAGE and ITTAGE queues (bp_cluster.sv p0). A      |
|    |           | queue in front of those queues adds nothing. Was: to     |
|    |           | determine whether a shared upstream PQ broadcasting to   |
|    |           | all predictor PQs is implemented. Deferred.              |
| 99 | bpu       | CLOSED TOOLS-006 (session-073). tools/regress.sh runs   |
|    |           | every target of every rtl/ Makefile (78), fails on an    |
|    |           | unclassified target, and is gated at push by            |
|    |           | tools/hooks/pre-push. The four testbenches that could    |
|    |           | not fail through exit status were found by injection     |
|    |           | and fixed; see session-073. Was: create a PR/CI/CD       |
|    |           | process. Motivating evidence                            |
|    |           | (session-060): `make all` silently omits targets.        |
|    |           | `all` names 38 of 47, enumerated from the Makefile       |
|    |           | BP-097. The 37 recorded through session-064 was wrong.   |
|    |           | Omitted: sim_ittage, sim_tage_manual, the seven cov      |
|    |           | targets. CI must run all 47, not `make all`.             |
|    |           | SESSION-064 SECOND MOTIVE: seven testbenches reported    |
|    |           | green regardless of what they found. CI must verify      |
|    |           | that each suite CAN fail, not merely that it passes.     |
|    |           | Scope note: the validator checks that a manifest path    |
|    |           | exists TODAY. 60 of 184 prompt files fail that on        |
|    |           | historical manifests. CI must validate only the file     |
|    |           | being run, not the prompts tree.                         |
| 100 | tage     | CLOSED by BP-126 (session-077): per-file table, cov_tage |
|     |          | RTL 588/614, every uncovered RTL line explained. The low |
|     |          | headline was the counting: an .info line counts only     |
|     |          | when every point on it is hit in every instance. Was:    |
|     |          | tage line coverage below the previously-stated >90%.     |
|     |          | MEASURED BP-097: cov_tage 73.8% (6418/8700),             |
|     |          | cov_tage_table 79.5% (399/502), cov_bpu 79.1%            |
|     |          | (9032/11419). The cov_tage denominator moved 8468 ->     |
|     |          | 8700 when BP-096 added tage_assert.sv to that compile,   |
|     |          | so 73.7 -> 73.8 is a new baseline, not a coverage        |
|     |          | change. The prior 6242/8468 predates that. The TD#109    |
|     |          | caveat is retired: the assertions ARE bound in cov_tage  |
|     |          | and tage_assert.sv is 10/10 there. STILL UNRESOLVED:     |
|     |          | genuine under-coverage or accounting artifact. Data, not |
|     |          | a resolution: 8043 of cov_tage's 8700 lines are          |
|     |          | tb_tage.sv, so the headline is dominated by testbench    |
|     |          | lines; DUT-only is near 90%. In cov_tage_table,          |
|     |          | tage_table.sv alone is 155/172 = 90.1%, so the 90.1% in  |
|     |          | TAGE_DECOMP_LOG.md and tage_coverage_plan.md is the      |
|     |          | DUT-only figure, not a stale one. Any conclusion must    |
|     |          | state its denominator. CAUTION: BP-097's per-file table  |
|     |          | does not sum to 8700 and its RTL-only subtotal excludes  |
|     |          | a file it lists. Re-derive per-file numbers before using |
|     |          | them. Tasked in BP-126 (session-077).                    |
| 101 | ras.sv   | CLOSED by BP-126 (session-077): removed from ras.sv,     |
|     |          | tb_ras.sv and bp_cluster; no planning document gives it  |
|     |          | a use. Was: Declares input ras_pc_p2, unread in the      |
|     |          | module. bp_cluster drives it from the staged p2 PC.      |
|     |          | Confirm needed or remove from ras.sv and tb_ras.sv.      |
|     |          | Tasked in BP-126 (session-077).                          |
| 102 | bp_history.sv | CLOSED by BP-126 (session-077): bp_history          |
|     |          | generates the IT5 folds in the rollback recompute and    |
|     |          | both steps; tb_bp_history and the FOLD monitor check     |
|     |          | them. No tb_fe_top figure changed. Was: Does not         |
|     |          | generate IT5 folds. ittage.sv wires                      |
|     |          | it_t5_idx_fh/tag_fh1/tag_fh2 to bp_history outputs that  |
|     |          | are never driven -- permanently 0. IT5 has real history  |
|     |          | (IT_TBL_HIST[5]=32, FH=9, FH1=9, FH2=8). Consequence:    |
|     |          | IT5 indexes on PC alone, so the longest-history ITTAGE   |
|     |          | table contributes no history and duplicates a            |
|     |          | short-history table. Prediction accuracy loss, not a     |
|     |          | correctness break. Add IT5 fold generation (same pattern |
|     |          | as IT1-IT4). Recorded in bp_history_interfaces.md as HI6 |
|     |          | and ftq_bpu_interfaces.md section 10 item 14. Tasked in  |
|     |          | BP-126 (session-077).                                    |
| 103 | tage     | CLOSED by BP-126 (session-077): T0 resets to 2'b10 on    |
|     |          | the walk and fast-init paths, TAGE_T0_SRAM_INIT_VALUE =  |
|     |          | 2 (new); the tagged tables keep TAGE_SRAM_INIT_VALUE =   |
|     |          | 0. Was: tage initializes T0 to 00 (strongly not taken).  |
|     |          | Intended is weakly taken, b10. Impacts                   |
|     |          | TAGE_SRAM_INIT_VALUE use with sram_init. When this       |
|     |          | closes, update tage_cntrl_decisions.md's T0 init line    |
|     |          | again (see the conflict note at the top of this file).   |
|     |          | Tasked in BP-126 (session-077).                          |
| 104 | ftb      | CLOSED by BP-126 (session-077): ftb_cntrl.sv states      |
|     |          | entry 114 and RAM entry 113 bits per way; ftb.sv         |
|     |          | describes ftb_fastpath_en as a documented input, source  |
|     |          | G25, TD#178. Was: Two stale RTL header comments          |
|     |          | (INFRA-008). Comment-only: - ftb_cntrl.sv: "107          |
|     |          | bits/way". The entry is 112 (ftb_decisions.md, sole      |
|     |          | home); this read 105, the pre-BP-099 width, and 109 was  |
|     |          | superseded s-071. - ftb.sv: ftb_fastpath_en "beyond the  |
|     |          | interface draft", it is a documented top input. Fold     |
|     |          | into the first FTB-touching RTL task. Tasked in BP-126   |
|     |          | (session-077).                                           |
| 105 | loop_pred| CLOSED BP-091 (session-064). Dual-slot retrofit,         |
|     |          | per-slot banks, pred_p0 -> pred_p1 rename, bp_cluster    |
|     |          | rewired. The cluster boundary ports lp_upd_valid_p0 and  |
|     |          | lp_upd_p0 gained the slot dimension in the same task.    |
| 106 | bp_structs_pkg | CLOSED BP-092 (session-064). bp_loop_meta_t        |
|     |          | deleted; lp_pred_t survives; lp_to_meta() deleted rather |
|     |          | than rewritten -- it did nothing but reorder and rename. |
| 107 | bp_cluster | CLOSED BP-092 (session-064). Both stale comments      |
|     |          | corrected. BP-092a found and corrected two more of the   |
|     |          | same class (stale interfaces section numbers) plus a     |
|     |          | fourth BP-092 missed because it read "(interfaces 8)".   |
| 108 | bp_cluster | CLOSED BP-092 (session-064). bpu_pred_pft_p1 added   |
|     |          | to the p1 output group: the block fall-through, one      |
|     |          | value per prediction, qualified by bpu_pred_val_p1,      |
|     |          | driven from the existing p1 not-taken term. Also closes  |
|     |          | the observability hole handoff-064 Part 3 item 4.        |
| 109 | tb_tage  | CLOSED BP-096. The bind read "bind u_dut tage_assert",   |
|     |          | an INSTANCE name. v5.048 accepts it, instantiates        |
|     |          | nothing and warns about nothing under -Wall, so          |
|     |          | tage_assert was NOT evaluated in sim_tage,               |
|     |          | sim_tage_fast, lint_tage or cov_tage. Repaired to        |
|     |          | "bind tage tage_assert".                                 |
|     |          | CORRECTED BP-097. The claim that tage_assert_inhibit     |
|     |          | "is not declared anywhere in tb_tage.sv" is FALSE. It is |
|     |          | declared at :259, initialised at :260, driven at         |
|     |          | :7669/:7671, and was present before BP-096 (verified     |
|     |          | against ea6e917). The compile failure was SCOPE          |
|     |          | RESOLUTION: a bind naming a MODULE resolves its port     |
|     |          | expressions in the bound-into module's scope, where      |
|     |          | that tb signal does not exist. Fix was the hierarchical  |
|     |          | reference tb.tage_assert_inhibit, not a declaration.     |
|     |          | Same defect in tb_tage_manual.sv fixed BP-095. BP-096    |
|     |          | swept all five binds across 46 files; class BOUNDED at   |
|     |          | these two, both repaired and proven live.                |
| 110 | tb       | CLOSED BP-096 by deletion. ittage_assert_bind.sv was     |
|     |          | compiled by no target; tb_ittage.sv's inline bind works, |
|     |          | so sim_ittage was always correct. The deletion was       |
|     |          | ordered by the BP-096 prompt and never authorised by     |
|     |          | Jeff -- recorded as a fact of the tree, not a precedent. |
|     |          | It left BP-096.md's manifest naming a missing path,      |
|     |          | corrected BP-097.                                        |
| 111 | tb       | CLOSED BP-097. Was: no watchdog in tb_ittage_cntrl,      |
|     |          | tb_ittage, tb_tage_tasks or tb_tage_manual. BP-096       |
|     |          | added those four. BP-097 swept all 18 testbenches:       |
|     |          |   - tb_tage, tb_loop_pred and tb_bp_history had none.    |
|     |          |     Added, time-based, proven both directions.           |
|     |          |   - tb_bp_cluster had one that could not fire:           |
|     |          |     repeat (200000) @(posedge clk). Clock frozen -> run  |
|     |          |     hung, make never returned. Converted to #200000.     |
|     |          |   - tb_bp_pkg needs none: no clock, cannot hang.         |
|     |          | RULE: a watchdog must be a TIME delay (#N), never a      |
|     |          | cycle count -- the hang it catches can stop the clock.   |
|     |          | 17 watchdogs now; tb_bp_cluster was the only cycle-based |
|     |          | one.                                                     |
|     |          | Residual, reported not fixed: magnitudes are not         |
|     |          | uniform. BP-096's four sit at 4.3x-6.1x of measured      |
|     |          | completion, the ten older ones at 20x-439x. No rule      |
|     |          | specifies a ratio and a late watchdog still fails        |
|     |          | correctly, so the older limits were left. The            |
|     |          | completion figures behind those ratios are coarse and    |
|     |          | strap-dependent; re-measure before setting a ratio rule. |
| 112 | planning | CLOSED 2026-09-17 by Jeff's ruling. Five session-063     |
|     |          | decisions were recorded only in                          |
|     |          | pa_handoffs/session_handoff-064.md and, partially, in    |
|     |          | ftq_bpu_interfaces.md:                                   |
|     |          |                                                          |
|     |          |   - the block-descriptor uBTB                            |
|     |          |   - the stage-named redirect model                       |
|     |          |   - the one-quantity comparison                          |
|     |          |   - the branch_id qualification                          |
|     |          |   - the two-group metadata write                         |
|     |          |                                                          |
|     |          | The TD also named two documents as still carrying the    |
|     |          | superseded pred_pc+32 dual-slot model. BOTH HAVE SINCE   |
|     |          | BEEN CORRECTED and the TD text was not updated:          |
|     |          | ras_decisions.md 6.1 was rewritten session-069, and      |
|     |          | loop_pred_interfaces.md records the model superseded     |
|     |          | under Slot PC derivation (BP-091). The claim that the    |
|     |          | gap was "actively producing wrong text elsewhere" no     |
|     |          | longer holds, which is what the TD rested on.            |
|     |          |                                                          |
|     |          | G8 and G17 remain SUPERSEDED by the five decisions.      |
|     |          | Promoting them into bp_cluster.md is not tracked here    |
|     |          | any more; bp_cluster.md carries its own contradictions   |
|     |          | with the current model and is the subject of a separate  |
|     |          | pass.                                                    |
| 113 | ftq      | CLOSED by BP-118 (session-075). bpu_blk_pft_p2 on the 4c |
|     |          | group is w_pft_p2, the not-taken term of the cluster's   |
|     |          | own p2 successor: the FTB fall-through when the FTB      |
|     |          | answers, else the p1 value carried forward. The FTQ      |
|     |          | rewrites pft_addr from it for every valid p2 block. Four |
|     |          | readers now see the corrected value: the fetch           |
|     |          | successor, the predecode W3 successor, the RAS commit    |
|     |          | return address and the FTB update fall-through. BP-118   |
|     |          | also built the RAS half of 4c, ruled session-071 and     |
|     |          | never built until then. Found by BP-107.                 |
| 114 | ftq      | CLOSED by INFRA-013 (session-074). 8 of 85 labels are    |
|     |          | absent from at least one build, all because the property |
|     |          | restates a direct assignment or tie-off and folds. I7,   |
|     |          | I10 and I11 fold the same way but stay compiled. Fixes   |
|     |          | are TD#144.                                              |
| 115 | icache   | CLOSED session-069 by planning/arch/itlb_decisions.md   |
|     |          | (ITLB-1..14) and mmu_decisions.md (MMU-1..25). L1I-U2   |
|     |          | ruled at 64 entries, not the recommended 32; L1I-U3     |
|     |          | adopted as recommended; L1I-U4 recommended and ruled.   |
|     |          | The ITLB is WRITTEN RTL, not a cachegen node. Original  |
|     |          | text follows.                                           |
|     |          |                                                          |
|     |          | OPEN. The ITLB is unspecified and the IFU cannot be     |
|     |          | built without it. L1I-3 makes the L1I physically         |
|     |          | indexed, so translation is in the fetch path ahead of    |
|     |          | the array, and l1i_ifu_interfaces.md IF-8 has the IFU    |
|     |          | issue a request only on a valid non-faulting             |
|     |          | translation.                                             |
|     |          |                                                          |
|     |          | icache_decisions.md L1I-U2 carries the parameters with   |
|     |          | a recommendation: 32 entries, fully associative, all     |
|     |          | three Sv39 page sizes, ASID tagged, 1-cycle hit.         |
|     |          | L1I-U3 carries the walker topology, recommending a       |
|     |          | shared L2 TLB node with a TileLink edge into l2 and a    |
|     |          | non-blocking ITLB. L1I-U4 carries PMP and PMA, which     |
|     |          | nothing in pacino has.                                   |
|     |          |                                                          |
|     |          | Needs itlb_decisions.md. L1I-U3 adds a node and an edge  |
|     |          | to the cachegen topology, so it is not a parameter       |
|     |          | choice.                                                  |
| 116 | ifu      | CLOSED session-074 by ruling (Jeff), now in              |
|     |          | ifu_decisions.md section 8 (TD-IFU-7 to 9) and           |
|     |          | icache_decisions.md L1I-U5.                              |
|     |          |                                                          |
|     |          | Line buffer depth a parameter, default 16, one slot per  |
|     |          | L1I request ID. Issue in order, oldest first; a block    |
|     |          | whose line matches the previous request reuses its ID    |
|     |          | and slot. The line buffer is the reorder store.          |
|     |          | Maintenance path moved to TD#136; line buffer on a       |
|     |          | redirect is TD#134.                                      |
| 117 | frontend | CLOSED session-069 by fe_decisions.md 15, FE-15..18.    |
|     |          | The top instantiates bp_cluster, ftq, ifu, L1I, the     |
|     |          | ITLB (FE-U10; added to this list session-070), ibuf     |
|     |          | and decode. The L1I is INSIDE it as a sibling of the    |
|     |          | IFU per L1I-2. Specified, not built. Original text      |
|     |          | follows.                                                 |
|     |          |                                                          |
|     |          | OPEN. There is no front-end top. ftq.sv deliberately     |
|     |          | does not instantiate bp_cluster, so two complete units   |
|     |          | have never been elaborated together and the loop between |
|     |          | them is closed only inside tb_ftq's modelled cluster.    |
|     |          | Carried from session-067 and unchanged.                  |
| 119 | icache   | CLOSED by BP-123 in the pacino RTL (end of row). As      |
|     |          | raised: no generated node emits an invalidate port of    |
|     |          | any kind, so icache_decisions.md L1I-18 has no           |
|     |          | hardware. Zicbom is mandatory in RVA23U64 and Zifencei   |
|     |          | in RVA23S64, which pacino is.                            |
|     |          |                                                          |
|     |          | The gap is two layers. l1i_ifu_interfaces.md 14.2 S8:    |
|     |          | the maintenance group is four booleans on the NODE and   |
|     |          | the schema has nowhere to describe a PORT. 14.3 E7: no   |
|     |          | emitter emits one. Schema first, then emitter.           |
|     |          |                                                          |
|     |          | The ports are specified, both ends:                      |
|     |          | l1i_ifu_interfaces.md 10, IFU to L1I, and 11, backend    |
|     |          | commit to IFU. Section 12 lists five assumptions about   |
|     |          | the producer, all unverifiable because no backend        |
|     |          | document exists.                                         |
|     |          | RULED session-076 (Jeff): built in the pacino RTL, not   |
|     |          | in cachegen. BP-123 copies the emitted l1i into          |
|     |          | rtl/core/frontend/icache and adds the ports there        |
|     |          | (cachegen_decisions.md CG-4, CG-D1); cachegen catches up |
|     |          | under CG-5. BP-123.                                      |
|     |          | CLOSED by BP-123 (session-077): the ports are built in   |
|     |          | the pacino copy, rtl/core/frontend/icache, and tb_fe_top |
|     |          | fencei and cboinval cover FENCE.I and cbo.inval end to   |
|     |          | end. The emission still lacks them: TD#173 (CG-5).       |
| 121 | ras.sv   | CLOSED by BP-126 (session-077): an occupancy count       |
|     |          | beside CSP; a full stack reads non-empty; a call on a    |
|     |          | full stack overwrites the oldest entry and the count     |
|     |          | holds at 32; a return on an empty stack does nothing.    |
|     |          | Was: Commit stack encodes empty as CSP == 0, so a full   |
|     |          | 32-entry stack reads as EMPTY after the wrap: the p0     |
|     |          | read and the empty-pop fallback lose their source.       |
|     |          | Entries intact, only the valid is wrong -- degrades      |
|     |          | fallback quality, never mispredicts. Wrap flag or 6-bit  |
|     |          | CSP. Decide with the 16/32 rebalance. ras_decisions.md   |
|     |          | 3.3. Tasked in BP-126 (session-077).                     |
| 122 | frontend | CLOSED session-074. VA_WIDTH 41 and the nine ITLB/MMU    |
|     |          | widths built by BP-109; the six L1I names declared in    |
|     |          | bp_defines_pkg and checked against l1i_pkg by            |
|     |          | rtl/core/frontend/l1i_param_chk (lint, lint_neg) by      |
|     |          | BP-115. PPN_WIDTH is PA_WIDTH - 12.                      |
| 123 | sc       | CLOSED by BP-126 (session-077): sc.sv builds the update  |
|     |          | queue, 8 entries of one update cycle each, both slots;   |
|     |          | new ports sc_uq_has_data and sc_uq_rd_en (P-3,           |
|     |          | confirmed). sim_sc 55 -> 144. Was: OPEN. THE SC UQ IS    |
|     |          | NOT BUILT AT THE UNIT LEVEL. bp_arb_spec.md 5.5          |
|     |          | specifies SC_UQ_DEPTH=8 and SC_UQ_WR_PORTS=2, and        |
|     |          | sc_interfaces.md calls the separate SC update queue the  |
|     |          | target arbitration model. sc.sv builds neither: it       |
|     |          | assigns sc_uq_not_full = 1'b1 and sc_upd_rdy = all-ones  |
|     |          | under a comment naming them arbitration-layer stubs.     |
|     |          | The credit arbiter itself IS implemented and tested, in  |
|     |          | bp_cluster: TD#73 closed by BP-094 group H covering all  |
|     |          | seven bp_arb_spec 4.5 grant rules. Only the unit-level   |
|     |          | queue is absent.  RAISED session-070 because closing     |
|     |          | TD#73 and TD#94 orphaned it. Neither was ever about      |
|     |          | building the queue, yet bp_arb_spec.md, sc_interfaces.md |
|     |          | and sc.sv (lines 30-32 and 148) all named them as the    |
|     |          | deferral. Those three citations now point here. The      |
|     |          | sc.sv comments are a two-line edit whenever an SC task   |
|     |          | next opens.  BP-121 replaced the credit rules            |
|     |          | (bp_arb_spec.md 4.5); the unit-level queue is still      |
|     |          | absent. Tasked in BP-126 (session-077).                  |
|     |          |                                                          |
| 124 | ftb/ubtb | CLOSED BP-110 (session-073). pftAddr is six bits from    |
|     |          | the aligned region base with NO CARRY, in the FTB and    |
|     |          | the uBTB. ubtb_pred_t.carry is deleted and nothing       |
|     |          | replaces it: no reader existed in rtl/, and a six-bit    |
|     |          | pftAddr reaches past the block boundary on its own.      |
|     |          | Pinned failing first: tb_ftb R1 and tb_ubtb TC16 read    |
|     |          | the end back 32 bytes short on the pre-edit tree.        |
|     |          |                                                          |
|     |          | ALSO FOUND: the FTB had NO fall-through bounds check at  |
|     |          | all. The session-069 restoration of FTB-G1 was recorded  |
|     |          | in ftb_decisions.md 4.5 and never reached the RTL, which |
|     |          | is what the ftb_cntrl.sv 500 comment meant. BP-110 built |
|     |          | FTB-G1 and FTB-G3. Second instance in two sessions of a  |
|     |          | document saying as-built when nothing was built; TD#127  |
|     |          | is the other.                                            |
|     |          |                                                          |
|     |          | The uBTB is ruled NOT bounds checked (session-073);      |
|     |          | ubtb_interfaces.md states it.                            |
|     |          |                                                          |
|     |          | Was: pftAddr could not represent an unaligned block end. |
|     |          | A four-bit slice in a five-bit field left the fifth bit  |
|     |          | dead, and at off = 64 the reconstruction gave base+32,   |
|     |          | wrong by 32 bytes, which FTB-G1 would not have caught    |
|     |          | because base+32 is still above the start.                |
| 125 | bpu      | CLOSED BP-110 (session-073). Stored positions are        |
|     |          | region-relative at FTB_BR_RPOS_BITS = 5, converted       |
|     |          | inside ftb_cntrl and ubtb (R-2), with the [k, k+16)      |
|     |          | window on the read. Entry 110 -> 113, RAM 109 -> 112,    |
|     |          | elaborated and checked in ftb_cntrl. O-1 built for       |
|     |          | conditionals, O-2 as FTB-G3, O-3a storage in region      |
|     |          | order, O-3b the read compaction. bp_cluster.sv no longer |
|     |          | forms any in-block address: w_blk_base_p1 and its        |
|     |          | localparams are gone and the miss successor is lookup PC |
|     |          | + 32 (R-3).                                              |
|     |          |                                                          |
|     |          | Pinned failing first: tb_ftb R2 and R3, tb_ubtb TC17,    |
|     |          | tb_bp_cluster K1 and TC-B on the pre-edit tree.          |
|     |          |                                                          |
|     |          | THE uBTB DIVERGES, RULED session-073: mask only, no      |
|     |          | compaction, no storage reorder, region-base targets, no  |
|     |          | bounds check, and br_idx names a storage field. A p1     |
|     |          | slot-order inversion is possible and the FTB corrects it |
|     |          | at p2. ubtb_interfaces.md is the home for it.            |
|     |          |                                                          |
|     |          | ftb_upd_br_idx_u0 is RATIFIED as a PORT SLOT as the      |
|     |          | update's start saw it (ftb_interfaces.md 2.5).           |
|     |          |                                                          |
|     |          | Was: the update path stored pos start-relative and       |
|     |          | bp_cluster.sv read it against the aligned region base,   |
|     |          | so every unaligned block got a branch PC wrong by the    |
|     |          | start offset and a branch an earlier start recorded was  |
|     |          | still reported. Found by the session-071 IA read.        |
| 126 | ftq      | CLOSED BP-112 (session-073). ftq_ifu.sv flushes the IFU  |
|     |          | at K for a front-end redirect and leaves the backend     |
|     |          | rows as they were. ftq_ptr needed the same correction:   |
|     |          | fetch_ptr rewound to K+1 for every surviving entry, so   |
|     |          | flushing at K alone would have meant K was flushed and   |
|     |          | never presented again. It now takes min(current, F) with |
|     |          | F = K for front-end causes, per 5.5 R1. Pinned failing   |
|     |          | first (F1, flush at K=12, got 13); F2 holds the backend  |
|     |          | half and passes before and after.                        |
|     |          |                                                          |
|     |          | THE RULE COULD NOT BE MET FROM THE INTERFACE IT WAS      |
|     |          | WRITTEN AGAINST. W3 keys the flush index on the redirect |
|     |          | cause, but ftq_npc drives RC_MISPREDICT with self=0 for  |
|     |          | p2, p3, predecode and the backend alike, so the          |
|     |          | distinction is not on the bus. BP-112 routed ftq_npc's   |
|     |          | arm_win, which until now was only terminated in ftq.sv.  |
|     |          | ftq_ifu_interfaces.md 7 and ftq_decisions.md must say    |
|     |          | that the arbitration arm is what distinguishes a         |
|     |          | front-end redirect, or the next reader finds a rule      |
|     |          | keyed on a cause that cannot carry it.                   |
|     |          |                                                          |
|     |          | Was: ftq_ifu.sv drove the flush at redir_idx when _self  |
|     |          | was set and redir_idx + 1 when clear, for every cause. A |
|     |          | p2, p3 or predecode redirect corrects K and K survives,  |
|     |          | so a fetch of K went out against the old prediction and  |
|     |          | truncated at the old taken_pos. Found by the session-071 |
|     |          | IA read.                                                 |
| 127 | ftq      | CLOSED BP-112 (session-073). ftq_ptr.sv carries          |
|     |          | xlate_ptr: it resets equal to fetch_ptr, advances on the |
|     |          | translation handshake, stops at the written frontier,    |
|     |          | cannot be passed by fetch_ptr (FQ-1), and takes          |
|     |          | min(current, F) on a redirect. Each rule is recorded in  |
|     |          | the results with the document section it came from.      |
|     |          | ftq_ifu.sv carries the 4.1 translation request group,    |
|     |          | FTQ side only, and ftq_entry.sv gained a sixth read      |
|     |          | port, pc only, at xlate_idx.                             |
|     |          |                                                          |
|     |          | Was: BP-107 completed the FTQ as a three-pointer design  |
|     |          | before ftq_decisions.md 5.1 added the fourth, so the     |
|     |          | built FTQ predated its own specification. Found by the   |
|     |          | session-071 IA read.                                     |
| 129 | build    | CLOSED by BP-132 (session-078): rtl/Makefile all and cov |
|     |          | RETIRED (they name tools/regress.sh and exit 1); clean   |
|     |          | reaches all 12 units (ruled, Jeff).                      |
|     |          | Was:                                                     |
|     |          | OPEN. THE TOP-LEVEL rtl/Makefile IS STILL NOT COMPLETE.  |
|     |          | Session-073 added ftq to its `all` and `clean`, but      |
|     |          | `cov` reaches only bpu cov_bpu, so cov_bp_cluster is     |
|     |          | unreachable from the top. Found by TOOLS-006.            |
|     |          | Either complete the top-level targets or retire them in  |
|     |          | favour of tools/regress.sh, which runs every target of   |
|     |          | every unit. Nothing depends on them today.               |
| 130 | tools    | CLOSED by BP-132 (session-078): the six targets parsed   |
|     |          | (tb_tage and cov_tage count tests, not checks), cov_bpu  |
|     |          | is the sum of its sub-runs, the known_failures.txt TD    |
|     |          | field validated (a malformed line fails the run), stale  |
|     |          | and malformed paths exercised.                           |
|     |          | Was:                                                     |
|     |          | OPEN. regress.sh REPORTING GAPS. None affect pass/fail;  |
|     |          | all are display or validation, found by TOOLS-006.       |
|     |          |   - six targets print no check total the parser reads:   |
|     |          |     sim_history, sim_tage, sim_tage_fast, cov_history,   |
|     |          |     sim_tage_tasks and cov_tage. They still print        |
|     |          |     per-test PASS/FAIL and exit non-zero on failure.     |
|     |          |   - cov_bpu reports the last sub-run's count (259/0) and |
|     |          |     not a total over the five cov_* it re-runs.          |
|     |          |   - the third field of a known_failures.txt line prints  |
|     |          |     as the TD without validation. A TD number is no      |
|     |          |     longer required, so an entry without one prints its  |
|     |          |     first description word in the TD column.             |
|     |          |   - the stale-entry path (an entry naming a target that  |
|     |          |     was not run) is implemented but never injected.      |
| 131 | decode   | CLOSED by BP-132 (session-078): EXPLAINED, ccache. The   |
|     |          | 5.048 install sets OBJCACHE ?= ccache, 5.020's does not; |
|     |          | uncached 5.048 is not faster. Decode builds about 42 s   |
|     |          | cold, 4 s warm: state the cache with any decode time.    |
|     |          | Was:                                                     |
|     |          | OPEN, UNEXPLAINED. THE DECODE SUITE GOT 3x FASTER AND    |
|     |          | NOBODY KNOWS WHY. Session-073: after lib and decode were |
|     |          | moved from Verilator 5.020 (found on PATH) to the        |
|     |          | project's 5.048, decode wall time fell 90 s -> 29 s.     |
|     |          | Check counts are identical (sim_exp 43, sim_dec 567,     |
|     |          | sim_predecode 476) and no warning appeared, so the same  |
|     |          | checks ran. Most likely compile and simulation speed     |
|     |          | under 5.048 with a warm ccache, but that is a guess.     |
|     |          | Confirm before trusting decode timing for anything:      |
|     |          | compare `make -n` output and the verilated build under   |
|     |          | both versions. Low risk, but an unexplained factor of    |
|     |          | three in a suite is not a fact until it is explained.    |
| 132 | bpu      | CLOSED BP-111 (session-073). The ITTAGE target field     |
|     |          | holds VA[40:1]. IT_MAX_TGT_WIDTH and IT_TBL_TGT_WIDTH    |
|     |          | are 40, the reconstruction is {stored, 1'b0}, and NO     |
|     |          | SITE ANYWHERE INFERS A TARGET BIT. Three extensions      |
|     |          | removed: the cluster reconstruction and the read and     |
|     |          | write casts in ittage_table. Entry widths 54/54/55/55/57 |
|     |          | -> 56/56/57/57/59; only TAG moves, to offset 48. Array   |
|     |          | 226,304 -> 234,496 bits, the 8,192 the ruling expected.  |
|     |          | The x2 is the TWO PER-SLOT RAM COPIES, not IT_TBL_BANKS, |
|     |          | which divide a copy; the ruling's wording gave the right |
|     |          | number for the wrong reason and is corrected in          |
|     |          | ittage_table_entry_formats.md and ftq_bpu_interfaces.md  |
|     |          | 5.2. ittage_pred_meta_t 143 -> 147, bp_ftq_meta_t 421 -> |
|     |          | 425, both as predicted; ittage_upd_inp_t 182 -> 188, all |
|     |          | of it target fields.                                     |
|     |          |                                                          |
|     |          | Pinned failing first: C1f4 (a target with bits 40:39 =   |
|     |          | 11 came back with them clear), G2b (THE STICKINESS: the  |
|     |          | update wrote the resolved target and the entry still     |
|     |          | produced the wrong one), TC-TGT40 at the unit level.     |
|     |          |                                                          |
|     |          | Was: the field held VA[38:1] and the cluster supplied    |
|     |          | bits 40:39 by extension. No extension rule is right for  |
|     |          | both a V=1 guest physical address (zero extended, bit 38 |
|     |          | significant) and a V=0 Sv39 kernel address (40:39 set),  |
|     |          | and a wrong entry could not be corrected by any update.  |
|     |          | Kernel function pointers, switch tables and vtables      |
|     |          | stopped being predicted. Found by BP-109. misc/prop1.md  |
|     |          | keeps the rejected alternatives.                         |
| 134 | ifu      | CLOSED by BP-118 (session-075). IFU-28 to IFU-32 built;  |
|     |          | ifu_assert U3 restated as the IFU-32 check and U4 added  |
|     |          | for IFU-31. Two rules the documents did not state,       |
|     |          | accepted (Jeff): a dropped block's presented L1I request |
|     |          | is held to acceptance and its response discarded         |
|     |          | (IFU-29a); the straddle register survives only with the  |
|     |          | block after it (IFU-28a).                                |
| 135 | ifu      | CLOSED, BP-123. THE UNCACHED                             |
|     |          | FETCH PATH. ifu_notes.md 6.8, MMU-14, IT-11, IFU-21. A   |
|     |          | fetch whose effective memory type is not cacheable and   |
|     |          | idempotent never reaches the L1I and takes the uncached  |
|     |          | path instead. WHERE THAT PATH GOES IS NOT ESTABLISHED:   |
|     |          | l1i_ifu_interfaces.md is the only IFU memory interface   |
|     |          | specified, so either the L1I gains a non-allocating mode |
|     |          | (a cachegen schema question) or the IFU gains a second   |
|     |          | port to the l2. Confirm against ifu_decisions.md IFU-21, |
|     |          | which the PA has not read, before assuming either.       |
|     |          |                                                          |
|     |          | Ruled session-073 (Jeff): deferred with TD#134. A ruling |
|     |          | on the port comes before the RTL.                        |
|     |          | RULED session-076 (Jeff): uncached fetch goes THROUGH    |
|     |          | THE L1I, marked uncached: forced miss, no allocation     |
|     |          | (L1I-24, IF-44), reversing IFU-21's separate source.     |
|     |          | IFU-22 and IFU-23 (commit gate, one instruction at a     |
|     |          | time) stand. Non-idempotent memory is never executable   |
|     |          | (MMU-15b), so a whole-line read is safe and IFU-U4 is    |
|     |          | closed. The L2 may hold the line while it is the point   |
|     |          | of coherence (L1I-25, Svpbmt checked). BP-123.           |
|     |          | CLOSED by BP-123 (session-077): one uncached instruction |
|     |          | per FTQ entry (IFU-23b, D1), under the IFU-22 gate; uc_nc|
|     |          | and uc_io programs.                                      |
| 136 | ifu      | CLOSED, BP-123. THE IFU HALF OF                          |
|     |          | FENCE.I AND CBO.INVAL. ifu_notes.md 6.9. The IFU routes  |
|     |          | the maintenance operation and gates the post-fence       |
|     |          | restart on the acknowledgements (l1i_ifu_interfaces.md   |
|     |          | IF-42, IF-43). Zifencei and Zicbom are mandatory in      |
|     |          | RVA23S64.                                                |
|     |          |                                                          |
|     |          | BLOCKED AT THE FAR END BY TD#119: the cachegen schema    |
|     |          | gap means the emitted L1I carries no invalidate port to  |
|     |          | receive it. The IFU side can be built against a stub and |
|     |          | unit-tested, but nothing is testable end to end until a  |
|     |          | TOOLS task closes TD#119. Doing TD#119 first avoids      |
|     |          | building against a port that does not exist.             |
|     |          |                                                          |
|     |          | Ruled session-073 (Jeff): deferred with TD#134.          |
|     |          | Also, from TD#116: the producer of l1i_ifu_interfaces.md |
|     |          | 11 is the backend commit stage, which has no document.   |
|     |          | RULED session-076: no longer blocked; BP-123 builds it   |
|     |          | against the pacino l1i copy (TD#119). The commit-side    |
|     |          | producer is modelled by tb_fe_top's backend.             |
|     |          | CLOSED by BP-123 (session-077): IF-33 to IF-37 and IF-41 |
|     |          | built, the line buffer cleared after done (IF-36), the   |
|     |          | group across fe_top; fencei and cboinval programs.       |
| 137 | ftb      | CLOSED BP-111 (session-073). ftb_cntrl encodes,          |
|     |          | status-checks and reconstructs the jump target from the  |
|     |          | JUMP PC, the region base plus the jump field's stored    |
|     |          | position, as BP-110 made a conditional target measured   |
|     |          | from the branch PC. FTB_JMP_TGT_BITS stays 21 and the    |
|     |          | entry arithmetic is unchanged: a base moved, not a       |
|     |          | width.                                                   |
|     |          |                                                          |
|     |          | THE ONE OBSERVABLE DIFFERENCE IS WHERE THE REACH WINDOW  |
|     |          | SITS. Any in-reach target reconstructs correctly under   |
|     |          | either base, since the region base and the jump PC are   |
|     |          | both shared by every start sharing the entry. BP-111     |
|     |          | pinned it with a jump target at the edge of the 21-bit   |
|     |          | reach (tb_ftb J2), wrong from both starts under the old  |
|     |          | base. Its J1 round-trip case could not be made to fail   |
|     |          | and the IA said so rather than manufacturing one.        |
|     |          |                                                          |
|     |          | Was: the jump target was a displacement from the region  |
|     |          | base. Ruled session-073 (Jeff): every target is a        |
|     |          | displacement from its own instruction.                   |
| 138 | ftq      | CLOSED session-073 by ruling, no RTL change. A REDIRECT  |
|     |          | AND A REQUEST HANDSHAKE IN THE SAME CYCLE. Ruled         |
|     |          | (Jeff): the document changes, not the RTL. NO REQUEST    |
|     |          | ACCOMPANIES A FLUSH. A request may be presented in the   |
|     |          | flush cycle but belongs to the old stream; the FTQ       |
|     |          | drives it from the pre-rewind pointer and discards the   |
|     |          | handshake, and the first request of the corrected        |
|     |          | stream is the one presented the cycle after.             |
|     |          |                                                          |
|     |          | THE OBLIGATION MOVES TO THE IFU: it must ignore any      |
|     |          | request presented while ftq_ifu_flush_val is set, on     |
|     |          | the section 4 and 4.1 groups both. Accepting one         |
|     |          | fetches the same entry twice under one generation tag    |
|     |          | when the pre-rewind pointer was behind F, and fetches a  |
|     |          | squashed entry when it was not. ftq_ifu_interfaces.md 5  |
|     |          | states it; the first IFU task must honour it.            |
|     |          |                                                          |
|     |          | Was: section 5 said the flush applies first and the      |
|     |          | request accompanying it is the first fetch of the        |
|     |          | corrected stream. No request port has ever done that,    |
|     |          | and meeting it would need a same-cycle path from the     |
|     |          | winning redirect through ftq_ptr's rewind to the request |
|     |          | outputs. Raised by BP-112; tb_ftq_ptr H53-H56 pin it.    |
| 139 | ftq      | CLOSED BP-113 (session-073). The redirect target is now  |
|     |          | allocated from the head 5.5 R1 rewinds to, in the        |
|     |          | redirect cycle: ftq_ptr exports alloc_req_ptr and        |
|     |          | alloc_idx is cut from it, so ftq.sv stays a rename, and  |
|     |          | alloc_ptr ends one past the rewound head when the        |
|     |          | request is accepted or on it when the queue is full. The |
|     |          | R1 values are unchanged. ftq_shadow took one new input,  |
|     |          | req_rewound, wired from squash_val: the rewound head IS  |
|     |          | squash_start, so without it the shadow squashed the      |
|     |          | target's own p1 write and the defect returned.           |
|     |          |                                                          |
|     |          | Pinned failing first: tb_ftq group G, 15 checks failing  |
|     |          | on the old code, each reading the PC the fetch carried.  |
|     |          | The index-only checks in the same group PASSED on the    |
|     |          | broken code, which is why D9 missed this for five        |
|     |          | sessions. FIVE EXISTING CHECKS HAD ENCODED THE DEFECT    |
|     |          | and were corrected with Jeff's approval, each carrying a |
|     |          | comment with its old value: tb_ftq D9, D13, D18, F5 and  |
|     |          | tb_ftq_ptr D9.                                           |
|     |          |                                                          |
|     |          | The two-cycle translation stall resolved with the index  |
|     |          | fix and no separate change. Measured after: front-end 1  |
|     |          | cycle, backend 2, the backend case because F is the      |
|     |          | target entry and its p1 write lands at the end of the    |
|     |          | first cycle. ftq_decisions.md 5.1 and ifu_decisions.md   |
|     |          | IFU-27 both separate them (IFU-27 checked session-074).  |
|     |          |                                                          |
|     |          | Was: in a redirect cycle the p0 request carried the      |
|     |          | pre-rewind alloc index, so the target block was written  |
|     |          | to a squashed entry and never fetched and the first 32   |
|     |          | bytes of the corrected stream were skipped, on every     |
|     |          | cause including RC_TRAP and RC_UNSPEC. Found by BP-112.  |
| 140 | ftq      | CLOSED BP-114 (session-073). Assertion I4, which is in   |
|     |          | ftq_ifu_assert.sv, agrees with ftq_entry_formats.md 4.3  |
|     |          | R3a: a second writeback naming an entry with wb_rcvd set |
|     |          | is legal, is accepted, and derives no redirect. BP-114   |
|     |          | found the property ALREADY held the no-redirect half --  |
|     |          | only its comment and message called the refetch          |
|     |          | writeback a protocol violation -- and added the          |
|     |          | acceptance half. Both proven by mutation, and restoring  |
|     |          | the old reading fires at the refetch, which shows the    |
|     |          | sequence is really exercised (tb_ftq F14-F19).           |
|     |          |                                                          |
|     |          | R3a ITSELF WAS WRONG AND IS CORRECTED. It said section   |
|     |          | 7's W1 and W2 apply to the second writeback's fields.    |
|     |          | Section 7 applies them only on ifu_ftq_mis_val, and the  |
|     |          | rewrite and the redirect are ONE EVENT (I5), so R3a as   |
|     |          | written would have split them and changed an entry's     |
|     |          | successor with no flush. A mispredict reported on the    |
|     |          | refetch is dropped whole; the backend redirect is the    |
|     |          | backstop. Found by BP-114, PA error.                     |
| 141 | ftq      | CLOSED BP-114 (session-073). THIS WAS A DEFECT, NOT A    |
|     |          | COMMENT MISMATCH. RC_UNSPEC squashes EVERY entry         |
|     |          | (ftq_backend_interfaces.md 5.1 U3), so the flush index   |
|     |          | must name the oldest live entry, which is commit_ptr's.  |
|     |          | ftq_ifu.sv drove fetch_idx, so every in-flight fetch     |
|     |          | between commit_ptr and fetch_ptr survived the flush and  |
|     |          | its writeback landed on a squashed entry. Pinned failing |
|     |          | first: tb_ftq group H, flush index 24 where commit_ptr   |
|     |          | was 6, 18 in-flight fetches left unflushed. ftq_ptr was  |
|     |          | already correct; ftq_ifu was the only module wrong.      |
|     |          | tb_ftq_ifu B6 had encoded the old value and was changed. |
|     |          |                                                          |
|     |          | 5.5 R1's F-by-source table never had an RC_UNSPEC row;   |
|     |          | it now does.                                             |
|     |          |                                                          |
|     |          | Was: the comment said the commit pointer's index and the |
|     |          | code drove fetch_idx. Raised by BP-112.                  |
| 142 | ftq      | CLOSED BP-114 (session-073). ftq_ifu_commit_ptr is on    |
|     |          | the section 4 fetch request group, FTQ_IDX_BITS wide,    |
|     |          | driven every cycle from commit_ptr with no valid and no  |
|     |          | handshake. ftq.sv passes the whole pointer and the slice |
|     |          | is taken in ftq_ifu, so ftq.sv stays wiring. Checked in  |
|     |          | tb_ftq_ifu group H across allocation, commit, redirect   |
|     |          | and wrap, including the IFU-22 case a block at           |
|     |          | commit_ptr may issue and one ahead must wait, on the     |
|     |          | live unit in tb_ftq group H, and every cycle by          |
|     |          | assertion I17.                                           |
|     |          |                                                          |
|     |          | Was: specified in ftq_ifu_interfaces.md 4 and not built. |
|     |          | Found incidentally by BP-112.                            |
| 143 | decode   | CLOSED by BP-119 (session-075). rvc_expander.sv and      |
|     |          | tb_rvc_expander.sv deleted; tb_ifu_rvc_exp and           |
|     |          | check_rva23_coverage.py no longer use them. Stale names  |
|     |          | of it in other files are carried by TD#155.              |
| 144 | ftq      | CLOSED by BP-116 Part A (session-074). Eleven labels     |
|     |          | deleted or restated; Q11, Q12, E9, E10 and the restated  |
|     |          | E8 each shown to fail under a scratch mutation.          |
|     |          | assert_labels in the ftq and ifu Makefiles guards        |
|     |          | removal; it cannot see a kept tautology, which the       |
|     |          | CLAUDE.md assertion rule covers. Gap left: tb_ftq_entry  |
|     |          | never samples E8's killed state.                         |
| 145 | decode   | CLOSED session-075 by ruling (Jeff): rvc_expander.sv is  |
|     |          | NOT repaired. It is retired with decode's old input path |
|     |          | under TD#143; ifu_rvc_exp is the expander in the design. |
|     |          | The finding stands: 12,456 of 49,152 encodings wrong in  |
|     |          | six classes, confirmed by BP-117's independent oracle.   |
| 146 | ifu, ftq | CLOSED by BP-117 (session-075). C6 predecode flushes at  |
|     |          | K+1, keyed on arm_win; C5 M1 on a JAL before the taken   |
|     |          | position, never JALR, outranking M2-M4 (Jeff); C19       |
|     |          | ifu_itlb_vpn [VA_WIDTH-13:0] on both lookups.            |
| 147 | ifu      | CLOSED by BP-132 (session-078), with TD#176.             |
|     |          | RULED session-077 (Jeff): option 2, a configurable path; |
|     |          | carried by TD#176 (a Vars.mk path variable for out-of-   |
|     |          | repo tools). BP-124 found the tools off PATH in the      |
|     |          | embecosm directory; asm_dec_words now depends on its     |
|     |          | clang-21 too.                                            |
|     |          | Was:                                                     |
|     |          | OPEN. oracle_ifu_rvc_exp, a regress target, runs LLVM    |
|     |          | from a toolchain at a fixed /usr/local path              |
|     |          | (RVC_ORACLE_TC in the ifu Makefile). On a machine        |
|     |          | without it regress.sh goes red. Either accept and record |
|     |          | that dependency, or make the path configurable. BP-117.  |
| 148 | ifu      | CLOSED by BP-125 (session-077): removed from             |
|     |          | ifu_pd_pkt_t (192 -> 190 bits), ifu_predecode, ifu_f3    |
|     |          | and ifu; T78 checks the width. Was: is_vsetvl and        |
|     |          | needs_vtype in ifu_pd_pkt_t have no reader once decode   |
|     |          | computes its own (dcd_decisions.md DCD-17). Kept so      |
|     |          | BP-118 needs no bp_structs_pkg change. Remove them from  |
|     |          | the struct, ifu_predecode and the ibuf. RULED            |
|     |          | session-077 (Jeff): removed by BP-125.                   |
| 151 | ftq, bpu | CLOSED by BP-119 (session-075). ftq_upd_conv, inside the |
|     |          | FTQ, forms every per-predictor payload; every field      |
|     |          | sourced. Integration found that a branch its FTQ entry   |
|     |          | did not hold formed no update at all, so TAGE, SC, LP    |
|     |          | and ITTAGE never trained and the FTB never learned it.   |
|     |          | Ruled (Jeff) and built: the resolution is placed in      |
|     |          | program order and trains every predictor of its row      |
|     |          | (ftq_entry_formats.md 3.1).                              |
| 152 | bpu, ftq | CLOSED by BP-119 (session-075). RETURN_CALL at 3'b111 in |
|     |          | bp_br_type_e, formed at p2, pop then push at p2, p3 and  |
|     |          | commit, uBTB and predecode report it, ftq_resolve trains |
|     |          | the FTB with call, ret and jalr set, ftq_entry commits   |
|     |          | it. TD-DCD-2 closed: the old RAS treated 3'b111 as a     |
|     |          | no-op.                                                   |
| 153 | ifu      | CLOSED by BP-119 (session-075). Parameter LB_RD_MAX,     |
|     |          | default 2*LB_DEPTH+1 = 33; assertion U5 fires above it.  |
|     |          | The 6-bit count never overflowed; the fixed bound was    |
|     |          | the defect.                                              |
| 154 | bpu      | CLOSED by BP-119 (session-075). The uBTB jump slot is    |
|     |          | predicted taken at p1.                                   |
| 155 | decode   | CLOSED by BP-120 (session-075). en_c, en_zcb and         |
|     |          | MASK_BITS removed; ext_enable_t and fe_top's ext_enable  |
|     |          | 16 bits; 5 tb_instr_decoder checks removed (654 -> 649); |
|     |          | the stale rvc_expander names, sim_main_exp.cpp and the   |
|     |          | ifu Makefile's DEC_DIR removed.                          |
| 156 | bpu      | CLOSED by BP-120 (session-075). ftb_cntrl.sv and ubtb.sv |
|     |          | keep a position only for the same branch; a different    |
|     |          | jump rewrites the field, a different conditional fills   |
|     |          | as new (ftb_decisions.md 5.5 gives the FTB mapping       |
|     |          | order). coro unchanged at 39 mispredicts: its two jumps  |
|     |          | now take turns, TD#168.                                  |
| 157 | ftq      | CLOSED by BP-120 (session-075). ftq_resolve keeps a      |
|     |          | per-channel flag keyed by entry index and position, so a |
|     |          | held resolution trains the FTB once. FTB updates in      |
|     |          | loops 109 -> 74 for 88 resolutions; loops mispredicts 51 |
|     |          | -> 58, the duplicates had been stepping conf.            |
| 158 | ftq      | CLOSED by BP-120 (session-075). A resolution naming an   |
|     |          | older one's slot is held; two placements in one entry    |
|     |          | take program-order slots. Age: nearer commit_ptr, then   |
|     |          | lower position, then port 0. Properties R18, R19.        |
| 159 | bpu      | CLOSED by BP-120 (session-075). Next-on-stack link built |
|     |          | in ras.sv, no port or package change. On the wrap the    |
|     |          | new entry links to BOS (the IA's choice, provisional).   |
|     |          | Moves no tb_fe_top number: the RAS rarely operates at    |
|     |          | p2, TD#162.                                              |
| 160 | ifu, bpu | CLOSED by BP-120 (session-075), expected. The 3 extra    |
|     |          | predecode redirects are passes of the halt loop in       |
|     |          | tb_fe_top's 200-cycle drain after the program retires; a |
|     |          | trained uBTB makes each pass 9 cycles instead of 10. The |
|     |          | count is not a program measure, TD#167.                  |
| 161 | bpu, ftq | CLOSED by BP-121 (session-075). bpu_slot_val_p3 gated on |
|     |          | the FTB having answered at p2; ftq_resolve now writes    |
|     |          | every resolved slot and ftq_entry clears the slots above |
|     |          | a resolved end, so the commit walk commits only what     |
|     |          | executed; the backend commits an entry only after its    |
|     |          | resolutions are accepted (A7, ruled).                    |
| 162 | bpu      | CLOSED by BP-121 (session-075). Ruled: ftq_npc holds p0  |
|     |          | in the cycle before an FTB update issues, so no lookup   |
|     |          | is dropped. Costs one p0 bubble per FTB update.          |
| 163 | bpu      | CLOSED by BP-121 (session-075). Ruled: the carried way   |
|     |          | is checked both ways; a stale miss merges into a         |
|     |          | same-tag way, a stale hit on a reused way allocates.     |
| 164 | bpu      | CLOSED by BP-121 (session-075). Ruled:                   |
|     |          | ftq_resolve_t.is_rvc, the resolved fall-through written  |
|     |          | at resolution of a taken jump, a 1-bit rvc in the FTB    |
|     |          | jump field; the RAS push and the p2 fall-through are the |
|     |          | jump PC + 2 or + 4.                                      |
| 165 | bpu      | CLOSED session-076 (Jeff), unreachable by construction.  |
|     |          | Two return-call repair pairings are wrong in ras.sv (p2  |
|     |          | return-call with p3 call, p2 call with p3 return-call;   |
|     |          | tb_ras TC-33c, d), but both need the p2 and p3 types of  |
|     |          | one slot to differ, and the p3 type is the registered p2 |
|     |          | type. BP-122 confirmed it from the RTL. Reopens only if  |
|     |          | the p3 type is ever taken from another source;           |
|     |          | ras_decisions.md 1 records the condition.                |
| 166 | bpu      | CLOSED by BP-121 (session-075). The p3 RAS repair        |
|     |          | compares the p3 view with p2 using p3 reachability (the  |
|     |          | SC direction); it now runs when SC reverses a direction  |
|     |          | that skips or reaches a call or return.                  |
| 167 | fe_top   | CLOSED by BP-121 (session-075). Counts stop at the last  |
|     |          | retirement. sim_main_predecode.cpp still unused          |
|     |          | (BP-122).                                                |
|     |          | sim_main_predecode.cpp deleted by BP-122.                |
| 169 | bpu      | CLOSED by BP-122 (session-076). The loop predictor reads |
|     |          | the entry before writing it, trains from the iteration   |
|     |          | number each prediction carries, advances a speculative   |
|     |          | count at p2 with a per-FTQ-entry checkpoint, and         |
|     |          | restores it on a redirect (option A, ruled: the          |
|     |          | redirecting block's entry exact, every other count       |
|     |          | invalidated on an FTQ rollback). A trusted p2 loop       |
|     |          | direction outranks TAGE and SC (ruled). Banks stay one   |
|     |          | per slot (TI6). LP used: lp 94 p1 / 86 p2, loops 56 / 49 |
|     |          | (0 before); lp's exit mispredicts at most once after     |
|     |          | warm-up. loop_pred_interfaces.md.                        |
| 170 | frontend | CLOSED by BP-122 (session-076). Properties for the       |
|     |          | BP-121 fixes: R20, R21 (ftq_resolve), E11-E13            |
|     |          | (ftq_entry), N11, N12 (ftq_npc), F1 (ftq top), H1, H2    |
|     |          | (bp_history), RS1 (ras), and LP1, LP2 for the loop       |
|     |          | predictor. Each fires with its fix reverted except H2,   |
|     |          | the checkpoint rewrite, which was not shown firing alone |
|     |          | (H1 fires first under the same mutation); H2 holds in    |
|     |          | every run. RS1 fires in tb_ras only; the case does not   |
|     |          | occur in the 19 programs.                                |
| 171 | decode   | CLOSED by BP-124 (session-077). The three rulings after  |
|     |          | BP-123 as one                                            |
|     |          | task: the decode representation and legality             |
|     |          | (dcd_decisions.md DCD-21 to DCD-35, the PA's R1 to R14,  |
|     |          | with the PA additions 10b lists, pending Jeff);          |
|     |          | FAULT_GPA_WIDTH = 56 and the unconditional kind-00       |
|     |          | offset (MMU-23, MMU-30 withdrawn); every leaf check,     |
|     |          | U against the privilege included, before the walker      |
|     |          | sets A, with itlb_l2t_priv and itlb_l2t_acc driven by    |
|     |          | the ITLB and held faults tagged (MMU-8c, MMU-24c,        |
|     |          | ITLB-10b). Package changes in all three packages.        |
| 172 | icache   | CLOSED by BP-125 (session-077): tb_l1i unc_merge_fill,   |
|     |          | which fails with fil_alloc's second term removed. It     |
|     |          | found a defect, fixed: a merged cacheable install did    |
|     |          | not update the replacement state (L1I-24). Was: The      |
|     |          | L1I-24 merge of a cacheable request onto an uncached     |
|     |          | MSHR in the fill's own cycle (the second term of         |
|     |          | fil_alloc) has no directed test; a merge on any earlier  |
|     |          | cycle is proven. BP-123 Deferred Work 2. Performance     |
|     |          | only: if it fails, a cacheable line is not allocated.    |
|     |          | Tasked in BP-125 (session-077).                          |
| 174 | ftq      | CLOSED by BP-125 (session-077): tb_ftq_ifu group L. Was: |
|     |          | W1 for a conditional keeps the entry's taken and         |
|     |          | corrects only the target (ftq_ifu_interfaces.md 7 W1,    |
|     |          | IFU-18; ruled session-077, Jeff). BP-124 found ftq_ifu's |
|     |          | predecode_correct writing taken = 0 for a conditional    |
|     |          | under M3, so the successor became the fall-through.      |
|     |          | Performance, not correctness.                            |
| 175 | decode   | CLOSED by BP-125 (session-077): 24742 illegal by class,  |
|     |          | sim_dec_sweep expects 208902 legal, T77 +30 words. Was:  |
|     |          | Every reserved vector encoding is illegal                |
|     |          | (dcd_decisions.md DCD-32, ruled session-077, Jeff): the  |
|     |          | 24742 encodings BP-124's sweep reported under rule VRSV, |
|     |          | by the classes DCD-32 lists. The sweep expectation and   |
|     |          | its tests follow.                                        |
| 176 | tools    | CLOSED by BP-132 (session-078): RVA_EXT_TOOLS in         |
|     |          | rtl/Vars.mk, default the embecosm bin directory;         |
|     |          | oracle_ifu_rvc_exp needs llvm-objdump and clang (objcopy |
|     |          | dropped, oracle byte-identical), asm_dec_words clang; a  |
|     |          | missing tool fails naming the variable.                  |
|     |          | Was:                                                     |
|     |          | OPEN. Scrub the LLVM tools from the necessary tools, and |
|     |          | add a definitive path environment variable to Vars.mk    |
|     |          | for necessary tools that do not reside in the repo       |
|     |          | (Jeff, session-077). The embecosm toolchain will never   |
|     |          | be in the repo because of its size, and there will be    |
|     |          | others like it. Today oracle_ifu_rvc_exp runs llvm-      |
|     |          | objdump, clang-21 and riscv64-unknown-elf-objcopy, and   |
|     |          | asm_dec_words runs clang-21, all from /usr/local/riscv-  |
|     |          | embecosm-embedded-ubuntu2204-20250309/bin                |
|     |          | (RVC_ORACLE_TC, ifu Makefile line 137). Carries TD#147   |
|     |          | (option 2, ruled). No GNU or LLVM change until this TD   |
|     |          | is tasked.                                               |
| 177 | icache   | CLOSED by BP-132 (session-078): tb_l1i t_fill_rpl, 31    |
|     |          | checks (sim_l1i 250 -> 281); fails with the gate removed.|
|     |          | Was:                                                     |
|     |          | OPEN, verification. The L1I-24 install-time replacement  |
|     |          | update is gated to installs from a register taken        |
|     |          | uncached: meta_fp_en = fil_valid && fil_rpl in l1i_ctrl, |
|     |          | so a cacheable register's install does not update the    |
|     |          | replacement state a second time after its lookup did.    |
|     |          | BP-125 reversion C5 removed the gate and no check        |
|     |          | failed: no test has an access to the set between a       |
|     |          | cacheable miss's lookup and its fill. Needs that test.   |
|     |          | BP-125 Deferred Work 2; ruled a TD session-077 (Jeff).   |
| 178 | csr      | CLOSED by SYS-001 (session-079).                         |
|     |          | planning/arch/csr_decisions.md defines the CSR packages; |
|     |          | csr_pkg and csr_tb_pkg built under rtl/core/csr; the     |
|     |          | config and csr groups are struct ports (fe_cfg_t,        |
|     |          | fe_csr_t, ptw_csr_t); every testbench sets them through  |
|     |          | csr_tb_pkg. Custom CSRs at 0x7C0 (enables) and 0x7C1     |
|     |          | (aging intervals). FE-20's csr group is covered. Was: A  |
|     |          | CSR definition, in a new planning file csr_decisions.md, |
|     |          | which will own the enable and configuration bits that    |
|     |          | now stand in for a CSR file that does not exist: FE-20's |
|     |          | config group (sc_enable, ftb_fastpath_en (G25),          |
|     |          | tage_enable_aging, tage_aging_interval,                  |
|     |          | ittage_enable_aging, ittage_aging_interval and decode's  |
|     |          | ext_enable) and FE-U6, the SC enable's behaviour         |
|     |          | (bp_arb_spec.md 0). Whether it also covers FE-20's csr   |
|     |          | group (V, privilege, satp, vsatp, hgatp, pmpcfg,         |
|     |          | pmpaddr) is decided when it is tasked. Implemented after |
|     |          | BP-126 (Jeff, session-077).                              |
| 182 | tage     | CLOSED by BP-134 (session-079). Opened session-079       |
|     |          | (Jeff) from BP-133's report. When T0 provided the TAGE   |
|     |          | prediction, its 2-bit counter reached the confidence     |
|     |          | decode and tage_extd_ctr zero-padded, {0, ctr}, and was  |
|     |          | read as a 3-bit tagged counter: a T0 predicting taken    |
|     |          | gave SC a not-taken term and a strongly taken T0 read    |
|     |          | weak. The decode and tage_extd_ctr now read a T0         |
|     |          | provider as {ctr[1], ctr[0], ctr[0]}: 00 -> 000, 01 ->   |
|     |          | 011, 10 -> 100, 11 -> 111 (ruled, Jeff). The stored      |
|     |          | tage_prm_ctr and tage_alt_ctr stay zero-padded (BP-134   |
|     |          | D1). tb_tage pred_t0_conf_tst; tb_bp_cluster G3 had      |
|     |          | encoded the defect and was reseeded.                     |
| 205 | bpu, ftq | CLOSED by BP-150 (8e55744), session-086. bp_cluster      |
|     |          | raises a p3 redirect only when the block's successor     |
|     |          | changes; SC can move the taken position without changing |
|     |          | it (a conditional taken to its fall-through, or a later  |
|     |          | slot taken to the same target). No flush fired, and the  |
|     |          | request presented in that p3 cycle read the stored p2    |
|     |          | slots, so the IFU truncated on the p2 view.              |
|     |          | ftq_entry.sv's fetch read port now writes through the p3 |
|     |          | slot write of the same cycle (ftq_decisions.md 1,        |
|     |          | ftq_ifu_interfaces.md 4). tb_fe_top sc_nored fails       |
|     |          | before and passes after at both slot counts; harness     |
|     |          | skips 3,823 -> 0 over 12 runs. Was: OPEN, CORRECTNESS.   |
|     |          | An SC p3 reversal to not-taken skips 4 to 580 bytes past |
|     |          | the branch's pc + 4. Found by PERF-002.                  |
| 211 | ftq      | CLOSED by BP-152 (0588b7b), session-086, for acceptance. |
|     |          | THE COMMIT WALK COMMITTED A CALL THAT DID NOT EXECUTE    |
|     |          | (ftq_decisions.md 5.4). (a) A backend redirect with      |
|     |          | _self clear now clears the named entry's slots after its |
|     |          | _pos, any cause but RC_UNSPEC. (b) A resolved end clears |
|     |          | every slot after the resolved branch's pos, whatever its |
|     |          | slot index. tb_ftq_entry J1 to J3, tb_fe_top rsv_twores  |
|     |          | and rsv_trapcall fail before and pass after;             |
|     |          | commit_unexecuted 25 -> 0 over BP-151's 25 runs. Was:    |
|     |          | OPEN, CORRECTNESS, found by BP-151.                      |
| 149 | bpu, ftq | CLOSED by BP-153 (073ab98), session-086, RC8, for        |
|     |          | acceptance. THE p3 RAS REPAIR WAS NOT IN THE SNAPSHOT: a |
|     |          | restore to a repaired entry undid the repair. The RAS    |
|     |          | now gives the p3 block's snapshot after the repair       |
|     |          | (ras_rep_val, ras_rep_snapshot) and the FTQ writes it    |
|     |          | into the entry (ras_decisions.md 4.1). Measured:         |
|     |          | commit_lost 20 -> 0, with RC6 and RC7 removing 100 of    |
|     |          | the then-remaining returns. tb_ras TC-80, tb_ftq_entry   |
|     |          | J5. Was: OPEN, measured by BP-121 and BP-151.            |
| 207 | bpu, ras | CLOSED by BP-153 (073ab98), session-086, for acceptance. |
|     |          | RETURN MISPREDICTS DEPENDED ON BACKEND TIMING. BP-151    |
|     |          | found the cause (the commit-stack fallback reading a     |
|     |          | popped frame); BP-152 built A1, B1, C1 and the undo;     |
|     |          | BP-153 the backend-found operations, the off-path pop    |
|     |          | undo, the peek, the record gating, the p3 snapshot, the  |
|     |          | p1 slots on an FTB miss, the count below, and commit 64. |
|     |          | Slot-held return mispredicts 123,712 -> 1,059 over       |
|     |          | BP-151's 25 runs; the 1,059 are ref_unmatched (1,009)    |
|     |          | and unwound (50); every RAS cause 0. Over the sweep      |
|     |          | returns no longer rise with resolve to commit (infra_1   |
|     |          | 2,791 to 2,848). RC11 (32 speculative entries) rejected: |
|     |          | BP-154.                                                  |

## Performance / Verification Debt

| #   | Unit     | Item and status                                          |
|-----|----------|----------------------------------------------------------|
| 168 | bpu      | CLOSED by BP-140 (session-081), see below. Was KEPT by   |
|     |          | ruling (Jeff, session-075, BP-121 decision 7: keep       |
|     |          | ftb_decisions.md 4.6). Every start in a region shared    |
|     |          | one FTB entry with one jump field, so two jumps of one   |
|     |          | region took turns. MEASURED (BP-121 and |
|     |          | BP-122, unchanged, mispredicts after warm-up / total):   |
|     |          | deep 91/146, nest 41/62, region 25/37, coro 25/32, recur |
|     |          | 21/33, nearly all returns. Also not open work:           |
|     |          | misp_call's repeating conditional (0x0a), which is       |
|     |          | pseudo-random by construction and cannot be learned.     |
|     |          | Tasks report neither as open.                            |
|     |          | MEASURED again by BP-131 (session-078): 73 of 260 FTB    |
|     |          | entries used by more than one start; 92% of block-end    |
|     |          | changes made by another start; 608 jump replacements.    |
|     |          | Revisited with TD#179 (Jeff).                            |
|     |          | CLOSED by BP-140 (2026-10-19): one entry per start PC    |
|     |          | (Jeff reopened ftb_decisions.md 4.6). coro's two jumps   |
|     |          | of the 0x600 region now have an entry each: mispredicts  |
|     |          | 32 -> 5 at both slot counts (BP-121 measured 39 on its   |
|     |          | tree), jump-field turn-taking 38 -> 0 in coro and 703 -> |
|     |          | 0 over the tb_fe_top programs.                           |
| 181 | bpu      | CLOSED session-086, on the PA's check at 3bface6. The    |
|     |          | bpu cov_* targets run $(VERILATOR_COVERAGE)              |
|     |          | (rtl/core/frontend/bpu/Makefile:917), which              |
|     |          | rtl/Vars.mk:9 sets to                                    |
|     |          | $(RVA_ROOT)/tools/bin/verilator_coverage, the 5.048      |
|     |          | copy; nothing in the Makefile runs verilator_coverage    |
|     |          | from PATH. Was: the bpu cov_* targets run                |
|     |          | verilator_coverage from PATH, /usr/local/bin v5.020, on  |
|     |          | coverage data written by the 5.048 build. Found by       |
|     |          | BP-132 (Deferred Work 2). For the formal verification    |
|     |          | coverage exercise (Jeff, session-078).                   |
| 189 | bpu      | CLOSED by ruling, session-084 (Jeff): c_bos is final     |
|     |          | (ras_decisions.md 12.11 CO5). BP-143 showed the          |
|     |          | exception guards a real fault (tb_ras TC-44: BOS moved   |
|     |          | back onto a reused slot reads empty over a live entry);  |
|     |          | BP-144 checks the converse of IV1 that fault breaks      |
|     |          | (RS4). Was: OPEN, CORRECTNESS RISK. RAS BOS ON A POP     |
|     |          | COMMIT. BP-140 Problem 4: a RETURN commit whose snapshot |
|     |          | is an empty stack moved BOS onto a slot the allocator    |
|     |          | had reused (RS2 in tb_fe_top region on the BP-140 tree). |
|     |          | Fixed PROVISIONAL in ras.sv (c_bos: such a commit leaves |
|     |          | BOS), accepted (Jeff); tb_ras TC-44. Still open: a pop   |
|     |          | commit with a non-empty snapshot can in principle reach  |
|     |          | a reused slot the same way after a full TOSW wrap (15    |
|     |          | allocations between the snapshot and the commit); not    |
|     |          | seen, not fixed. Opened session-081 (Jeff). The RS2 that |
|     |          | justified it judged held as above BOS; RULED session-084 |
|     |          | (Jeff): TOSR below BOS is not a fault (ras_decisions.md  |
|     |          | 3.2). BP-143 rechecks the provisional rule.              |
| 194 | bpu      | CLOSED by BP-142 (session-084), option A. A WRONG-PATH   |
|     |          | RECURSION COUNT IS NOT                                   |
|     |          | RESTORED. A redirect restores the RAS pointers from the  |
|     |          | snapshot; a recursion count incremented or decremented   |
|     |          | in place on the wrong path is array data and keeps its   |
|     |          | wrong-path value (ras.sv:335-343, 413-421, 808-811). No  |
|     |          | tb_ras case restores across such a change. A candidate   |
|     |          | for fd07's unexplained count of 4 (fd07_calls_returns.md |
|     |          | 154-159), not traced. Needs a tb_ras case, then a ruling |
|     |          | on a fix. For the next BP task that edits ras.sv. Found  |
|     |          | by DOC-011; opened session-082 (Jeff).                   |
| 195 | bpu      | CLOSED by BP-141 (session-084). STALE RAS COMMENTS IN    |
|     |          | THE RTL, none                                            |
|     |          | functional (DOC-011): ras.sv:23 "planning docs use       |
|     |          | equivalent s-stage"; ras.sv:80 "RAS-3 OPEN" (closed,     |
|     |          | ras_decisions.md 4.4); ras.sv:264 "Three rules" before   |
|     |          | four; tb_ras.sv:12 "TC-01 .. TC-43" (TC-44 exists);      |
|     |          | bp_defines_pkg.sv:552-553 and bp_structs_pkg.sv:144-146  |
|     |          | "Simple circular buffer" (linked since BP-120). For the  |
|     |          | next BP task that edits those files. Opened session-082  |
|     |          | (Jeff).                                                  |
| 201 | tb       | CLOSED by INFRA-015 (session-085). TB_FE_TOP COLD        |
|     |          | COMPILE. Cause measured: tb_fe_top's program-running     |
|     |          | initial block was one C++ coroutine of 10.06 MB, with    |
|     |          | module tasks inlined at every call (chk 866 copies;      |
|     |          | reset_all, run_and_check, report and others 42 each);    |
|     |          | gcc took 530 s on it, and the 58 compiles ran one at a   |
|     |          | time. Fix: --build-jobs 0 on the tb_fe_top build (fe_top |
|     |          | Makefile); chk, the fe_tb_csr.svh tasks and              |
|     |          | run_and_check are one call each to a class method (ck_c, |
|     |          | csr_hlp_c, prg_c), with the check counts as members of   |
|     |          | CK. Cold build 711 s -> 54.6 s (2 slots), 675 s -> 53.2  |
|     |          | s (1 slot). Every program's log is unchanged.            |
|     |          | tb_fe_top.sv:3436 reads the oracle by FE_RVC_ORACLE, an  |
|     |          | absolute path the Makefile defines, and slot1 runs make  |
|     |          | in slot1/. Opened session-085 (Jeff).                    |

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


# BUG Records

- BUG-001: HAND-FIX-003. T0 CTR INC/DEC condition
  wrong in tage_cntrl.sv. Found by tage_ctr_test
  row 13a. Fixed BP-041. See session-handoff-045.
- BUG-002: BP-049a renamed t_tgt_wr_u0 to t_prm/t_alt in
  ittage_cntrl.sv and ran only sim_ittage. tb_ittage_cntrl
  and tb_ittage_table were left uncompilable; their 77/0 and
  32/0 counts carried in handoff-048 were stale (not from a
  run). Found and repaired BP-050a. Cause of the all-targets-
  must-run rule.
- BUG-003: tage_cntrl.sv uaon_upd_ff gate missing && u_alt_tagged[s]. UAON
  counter moved on single-hit transactions (provider tagged T1-T4 hit,
  alternate fell through to untagged T0/BIM) where the prm-vs-alt comparison
  carries no training signal. Found by TC-81, fixed BP-057. Same class as BUG
  (ITTAGE #59, BP-051).
- BUG-004: bp_history.sv folded-history geometry wrong vs the
  Xiangshan FoldedHistory it mimics. Four defects:
  (1) incremental insert at fold bit 0, not the high end;
  (2) wrap-out bit removed at position 0, not (H-1) % W;
  (3) rollback recompute (fold_ghr) used a separate, inequivalent
  fold definition (forward walk i->i) vs the incremental path;
  (4) 32b fold helpers truncate SC ST3 (H=W=64), making ST3
  unrepresentable. Surfaced during BP-070 dual-slot test planning
  (session-054). The old 12-test tb_bp_history passed only because
  the fold window never filled past TC7 -- the bug lived in the
  full-window region. Fixed BP-071 (single Xiangshan-geometry fold:
  newest at high end, wrap-out at (H-1) % W, recompute posmap(i) =
  (i+W-1) % W; 64b helpers). Single-slide equivalence proven offline
  in BP-071. In-sim proof (single + dual-slot) completed BP-072
  (19224 golden comparisons); externally anchored BP-073; geometry
  captured natively in bp_history_decisions.md s6, doc-RTL verified
  BP-074. CLOSED. BP-070 abandoned. See also BUG-005 (the
  increment-oriented integration defect found while landing this
  fix).
- BUG-005: bp_history BP-069/BP-071 never co-resident; the merged
  module-owned-pointer + fold geometry was never integrated or
  tested in session-054. Root cause: session-054 left the BP-069
  module-owned-pointer RTL only in versions/bp_history.sv and the
  BP-071 fold-geometry fix only in the active rtl/ file; no single
  file held both, so the pointer-to-fold addressing for an
  incrementing module-owned pointer was never written or run.
  handoff-054 and PROJECT_STATUS recorded both BP-069 and BP-071 as
  landed and lint-clean -- inaccurate (the records were corrected
  session-055). Surfaced in BP-072: merging the two produced an
  incremental fold that diverged from the rollback recompute
  (rolling back to an un-diverged checkpoint corrupted folded,
  0x92 -> 0x00), because BP-071's geometry walk and BP-069's
  incrementing pointer disagreed on direction. Fixed BP-072
  (authorized scope expansion): increment-oriented walk (fold_ghr
  ptr-i; fold_step evicts the leaving bit at write_addr-H) plus a
  POST-advance checkpoint with recompute anchor ckpt-1. The BP-071
  posmap and high-end insertion are unchanged; this is an addressing
  reconciliation, not a geometry change, and no table-consumed fold
  value moved. recompute == incremental proven in-sim BP-072;
  externally anchored BP-073; geometry made native in
  bp_history_decisions.md s6 (BP-074). versions/bp_history.sv is
  superseded by the merged rtl/ file and should be retired. CLOSED.
- BUG-006: BP-081 manifest omission. The BP-081 task Context Loaded /
  Deliverables listed the tage testbenches from the BP-080 Phase-1
  reference list, which was itself scoped to the Phase-1 manifest and
  did NOT enumerate every file referencing tage_high_conf.
  tb_tage_tasks.sv (not in the manifest) referenced the removed field
  at two lines and blocked sim_tage_tasks compilation. The IA halted
  and requested authorization; the user authorized the out-of-scope
  edit and it was made. Root cause: task manifest built from a prior
  investigation's file list rather than a grep of the symbol across
  the unit tree -- the same class as BUG-002 (all-targets) and the
  session-059 "manifest by inference" postmortem. Corrective rule:
  any task that deletes or renames a struct field must grep the symbol
  across the unit and repair the full reference set in-scope, reporting
  the found set, rather than relying on a hand-listed manifest.
  Proposed for ANTIPATTERNS.md. CLOSED (edit made; rule pending).



---

