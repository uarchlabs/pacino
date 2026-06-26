<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Project Status -- RISC-V RVA23 Processor Co-Design
```
 FILE:    PROJECT_STATUS.md
 SOURCE:  various
 STATUS:  WORKING
 UPDATED: 2026-06-26 (pa session 055)
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
|                         |             |                   | RAS params added BP-062:         |
|                         |             |                   | RAS_SPEC_ENTRIES=16,             |
|                         |             |                   | RAS_COMMIT_ENTRIES=32,           |
|                         |             |                   | RAS_RCTR_WIDTH=4, RAS_PTR_BITS=4,|
|                         |             |                   | RAS_COMMIT_PTR_BITS=5.           |
|                         |             |                   | FTB params added/fixed BP-065/   |
|                         |             |                   | 065a/066a (FTB_WAYS=4, widths,   |
|                         |             |                   | conf init, FTB_RAM_*).           |
| bp_structs_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE structs complete.|
|                         |             |                   | IT5 fold fields pending (II1).   |
|                         |             |                   | bp_ras_snapshot_t comment        |
|                         |             |                   | updated session-050.             |
|                         |             |                   | tb_bp_pkg.sv 6->4b literal fix   |
|                         |             |                   | (BP-062, authorized).            |
| bp_pkg.sv               | Deprecated  | --                | Deleted.                         |
| bp_history.sv           | Complete    | tb_bp_history     | Module-owned pointer (BP-069).   |
|                         |             |                   | Fold geometry corrected to       |
|                         |             |                   | Xiangshan, 64b helpers (BP-071); |
|                         |             |                   | increment-oriented walk +        |
|                         |             |                   | post-advance ckpt reconciled     |
|                         |             |                   | (BP-072). Dual-slot fold         |
|                         |             |                   | equivalence proven in-sim        |
|                         |             |                   | (TD #74, BP-072): 16 TCs,        |
|                         |             |                   | 19224 golden comparisons.        |
|                         |             |                   | External fold anchor TC14-16     |
|                         |             |                   | (BP-073). Canonical fold def     |
|                         |             |                   | captured in decisions.md s6;     |
|                         |             |                   | doc-RTL consistency verified     |
|                         |             |                   | (BP-074). Full bpu 33/33 green.  |
|                         |             |                   | See BUG-004 / BUG-005.           |
| bp_history_decisions.md | Draft       | --                | Created session-054. Resolves    |
|                         |             |                   | G20/G21/G22; rules pointer       |
|                         |             |                   | module-owned, rollback by index. |
|                         |             |                   | s6 canonical Fold Definition     |
|                         |             |                   | added session-055 (native        |
|                         |             |                   | geometry; Xiangshan demoted to   |
|                         |             |                   | origin footnote s6.6, sha TBD).  |
|                         |             |                   | s7 checkpoint POST-advance       |
|                         |             |                   | ratified. s10 pointer-authority  |
|                         |             |                   | wording corrected. Doc-RTL       |
|                         |             |                   | consistency verified BP-074.     |
|                         |             |                   | Functionally authoritative;      |
|                         |             |                   | header still DRAFT pending s6.6  |
|                         |             |                   | sha + HI2/HI5.                   |
| bp_history_interfaces.md| Draft       | --                | Rewritten session-054 from the   |
|                         |             |                   | BP-002 draft to target interface |
|                         |             |                   | (module-owned ptr, dual-slot,    |
|                         |             |                   | rollback by index, stale folds). |
|                         |             |                   | Checkpoint Timing (post-advance) |
|                         |             |                   | confirmed consistent with        |
|                         |             |                   | decisions.md s7 (BP-074).        |
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
| tage_cntrl_uaon         | Complete    | --                | session-036: verified.           |
| _update_rules.md        |             |                   | Debt #45 closed BP-032.          |
|                         |             |                   | Promoted Complete BP-057.        |
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
| tage_cntrl.sv           | Complete    | --                | BP-008a/b complete.              |
|                         |             |                   | BP-012 complete.                 |
|                         |             |                   | BP-034/5 issues (#66) closed     |
|                         |             |                   | BP-045.                          |
|                         |             |                   | HAND-FIX-002 applied (debt #30). |
|                         |             |                   | HAND-FIX-003 applied (BP-041).   |
|                         |             |                   | T0 CTR u_both_t0 path corrected. |
|                         |             |                   | BUG-003 UAON single-hit guard    |
|                         |             |                   | fixed BP-057.                    |
| tage.sv                 | Complete    | tb_tage           | BP-056 through BP-061 complete.  |
|                         |             |                   | BP-010 through BP-030 complete.  |
|                         |             |                   | 103 tests pass. Directed         |
|                         |             |                   | validation complete. All         |
|                         |             |                   | coverage targets closed or       |
|                         |             |                   | deferred.                        |
|                         |             |                   | tage_assert.sv bound via bind.   |
| tage_assert.sv          | Complete    | sim_tage          | ADR-001 and row 18 assertions.   |
|                         |             | sim_tage_fast     | assert_inhibit port added        |
|                         |             | sim_tage_tasks    | (BP-042a). CE-06 gated.          |
|                         |             | sim_tage_manual   | Bound in tb_tage.sv,             |
|                         |             |                   | tb_tage_manual.sv,               |
|                         |             |                   | tage_assert_bind.sv removed from |
|                         |             |                   | sim_tage_manual (BP-042b).       |
|                         |             |                   | sim_tage 81 tests as of BP-057   |
|                         |             |                   | sim_tage 87 tests as of BP-058   |
|                         |             |                   | sim_tage 95 tests as of BP-059   |
|                         |             |                   | sim_tage 102 tests as of BP-060  |
|                         |             |                   | sim_tage 103 tests as of BP-061  |
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
| ittage_cntrl_uaon_update_rules.md | Complete    | --    | Created session-033.             |
|                                   |             |       | Promoted Complete BP-051.        |
| ittage_cntrl_use_update_rules.md  | Complete    | --    | session-045: DIFF corrected      |
|                                   |             |       | (prm_tgt != alt_tgt).            |
|                                   |             |       | HIT=0 row added.                 |
|                                   |             |       | Notes corrected and aligned.     |
|                                   |             |       | Aging disabled section added.    |
|                                   |             |       | Promoted Complete BP-051.        |
| ittage_table_hash_rules.md        | Complete    | --    | Created session-033.             |
|                                   |             |       | session-036: verified.           |
|                                   |             |       | Defines fold CONSUMPTION only;   |
|                                   |             |       | fold COMPUTATION is in           |
|                                   |             |       | bp_history_decisions.md s6.      |
| ittage_table.sv                   | Complete    | tb_ittage_table | BP-033/033-FIX-1 complete. |
| ittage_cntrl.sv                   | Complete    | tb_ittage_cntrl | Prediction path complete BP-034|
|                                   |             |                 | Update path complete BP-035      |
|                                   |             |                 | Testbench complete BP-036        |
|                                   |             |                 | CTR/USE tests complete BP-044/a/b/c |
|                                   |             |                 | 147 tests passing w/ BP-048       |
|                                   |             |                 |  UAON/aging/alloc verified BP-051/2/3 |
|                                   |             |                 |  ittage_cntrl is complete   |
| ittage.sv                         | Complete    | tb_ittage | BP-034/035/35a/35b                |
|                                   |             |           | shell without arb cntrl complete  |
|                                   |             |           | sim_ittage 211 pass / 0 fail      |
|                                   |             |           | tests added BP-054.               |
|                                   |             |           | round trip tests added in BP-055. |
| ras_decisions.md | Draft       | --             | Created session-050.             |
|                  |             |                | G5/G6/G8/G17 decisions recorded. |
|                  |             |                | Reconciled to RTL BP-064         |
|                  |             |                | (sec 1/1.2, 3.2, 3.3/4.5).       |
|                  |             |                | See BP Cluster Open TBDs.        |
| ras_interfaces.md| Draft       | --             | Created session-050. IC-RAS-11   |
|                  |             |                | repair semantics appended BP-064.|
| ras.sv           | Complete    | tb_ras         | RTL BP-062, tb BP-063. sim_ras   |
|                  |             |                | 87/0 this session (BP-064).      |
|                  |             |                | TD #78 pinned (TC-21); TD #79    |
|                  |             |                | (commit_rctr) deferred.          |
| ftb_decisions.md | Complete    | --             | Created session-051. Storage     |
|                  |             |                | split, bimodal conf, fast-path,  |
|                  |             |                | position fix (session-053).      |
|                  |             |                | Promoted Complete session-053.   |
| ftb_interfaces.md| Complete    | --             | Created session-052. Storage     |
|                  |             |                | ports (3/3a) + IC-FTB-12..15     |
|                  |             |                | session-053.                     |
| ftb_confidence   | Complete    | --             | conf = bimodal direction,        |
| _override        |             |                | fast-path, ftb_fastpath_en       |
| _rules.md        |             |                | (session-053).                   |
| ftb_array.sv     | Complete    | sim_ftb        | 1R1W data RAM, no reset.         |
|                  |             |                | BP-065 / BP-065a.                |
| ftb_plru.sv      | Complete    | sim_ftb        | entry-valid + tree-PLRU flops,   |
|                  |             |                | cold init. BP-065a.              |
| ftb_cntrl.sv     | Complete    | sim_ftb        | All FTB logic. BP-066 /          |
|                  |             |                | BP-066a (conf/fast-path) /       |
|                  |             |                | BP-066b (position).              |
| ftb.sv           | Complete    | tb_ftb         | Structural top. BP-067.          |
|                  |             | sim_ftb        | sim_ftb 99/0 (BP-068).           |
| SC               | Not started | --             | Last unbuilt predictor           |
| bp_cluster (top) | Not started | --             | After predictors complete        |
| fetch            | Not started | --             | After BP cluster                 |

---

## Technical Debt

| # | Item                                   | Resolution path                 |
|---|----------------------------------------|---------------------------------|
| 1  | NUM_PRED_SLOTS=1 reduction.           | Cleanup session after TAGE      |
|    | Generate removal and NUM_PRED_SLOTS=1 | complete. Dual-slot *testing*   |
|    | tests pending.                        | tracked separately in #74.      |
| 2  | Instruction fusion                    | Deferred to rename/dispatch     |
| 3  | UOP expansion for RVV segments        | Policy TBD at vector execution  |
| 4  | predecode.sv clk/rstn unused          | Resolve at pipeline stage assign|
| 5  | ENUM hole at 7'd2 (VALU_FP)           | Minor, acceptable for now       |
| 6  | vtype_hazard intra-bundle policy      | TBD at rename/dispatch          |
| 7  | curs/curs_v rollback undefined.       | Resolve at bp_cluster impl or   |
|    | Seznec uses SLIM structure. Inline    | migrate to SLIM-style external  |
|    | fields have no defined                | structure. See rollback test    |
|    | checkpoint/rollback path.             | items #69/#70.                  |
| 15 | CLOSED. EPC field semantics now       | Field implemented; write path   |
|    | implemented and documented.           | modified BP-044c. Live work is  |
|    |                                       | EPC write proof, see #55/#56.   |
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
| 37 | trx_type forwarded combinationally    | Investigate before closing.     |
|    | from arb_grant_upd instead of from    | When concurrent pred+upd tests  |
|    | registered arb_trx_r.trx_type.        | are added (arb item #73),       |
|    | Verify grant signal stability through | verify grant stability through  |
|    | tage_cntrl pipeline under concurrent  | the pipeline. If unstable,      |
|    | pred+upd.                             | promote arb_trx_r.trx_type and  |
|    |                                       | adjust write-enable timing.     |
| 38 | Verilator 5.048 covergroup #7099      | Re-check #7099 status in 5.048  |
|    | status not yet verified.              | release notes before closing.   |
| 39 | TB-ARB-08 Rule 2 starvation override  | Verify PRED_CREDITS <           |
|    | untestable at current params.         | STARVE_THRESH is intentional.   |
|    | PRED_CREDITS=4 < STARVE_THRESH=8 so   | If Rule 2 must be testable,     |
|    | starve_ctr never reaches threshold.   | adjust params before bp_cluster |
|    | Rule 4 is the effective ceiling.      | integration. See arb item #73.  |
| 40 | TB-ARB-05 spec discrepancy.           | Update bp_arb_spec.md 10.1 to   |
|    | bp_arb_spec.md 10.1 "backpressure 2   | match TAGE_UQ_DEPTH=8 before    |
|    | cycles" does not match UQ_DEPTH=8.    | bp_cluster integration. No RTL  |
|    | No RTL risk.                          | change required.                |
| 42 | Pipeline diagram shows ITTAGE at s3,  | Revisit after SC definition.    |
|    | should be s2 (alongside FTB, TAGE).   | Update diagram and discussions. |
|    |                                       | See prediction-side item #65.   |
|    |                                       | #65 is now CLOSED, BP-054       |
| 43 | Reduce ITTAGE CTR width 3b -> 2b.     | Impacts bp_defines_pkg.sv,      |
|    |                                       | ittage_table_interfaces.md, RTL |
|    |                                       | and testbenches. Confirm no     |
|    |                                       | testcase impact (see #44).      |
| 44 | Confirm ittage_pred_strong change in  | CLOSED                          |
|    |                                       | Changed session-040: provider   |
|    | ittage_cntrl_decisions.md.            | ctr was !=3 & !=4, now > 0 (NOT |
|    |                                       | NULL). Ensure #43 does not      |
|    |                                       | impact any testcase.            |
| 49 | Arb queue status pin renaming.         | pq_not_full/upd_rdy ->          |
|    |                                        | tage_pq_not_full/tage_uq_not_   |
|    |                                        | full and ittage_ equivalents.   |
|    |                                        | Scope: RTL, tb, bp_arb_spec.md, |
|    |                                        | tage_interfaces.md,             |
|    |                                        | ittage_interfaces.md.           |
| 51 | CTR/USE/TGT update audit.              | CLOSED.                         |
|    |                                        | CTR fixed BP-044b, USE fixed    |
|    | Parent audit item.                     | BP-044c (both were provider-    |
|    |                                        | gating inversions). Survivors   |
|    |                                        | broken out: TGT #57,            |
|    |                                        | allocation #62/#63.             |
| 52 | Move arb logic into submodule out of   | Top modules should be           |
|    | top in tage and ittage.                | structural only. New arb module |
|    | (Refactor; pairs with #73 test.)       | for tage and ittage. Co-        |
|    |                                        | sequence with arb test #73.     |
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
| 67 | tage sram_init non-fast path.          | All tests used +FAST_INIT,      |
|    | Untested here; confirm not elsewhere.  | bypassing real sram_init        |
|    |                                        | cycling. sram_init.md Complete  |
|    |                                        | with COMP tests -- confirm they |
|    |                                        | cover non-fast path; do not     |
|    |                                        | assume.                         |
| 68 | ittage sram_init non-fast path.        | Same as #67. Fast-init initial  |
|    | Untested here; confirm not elsewhere.  | block in ittage_table.sv writes |
|    |                                        | RAM directly; real post-reset   |
|    |                                        | init sequence never exercised.  |
| 69 | tage rollback / history recompute.     | G20/G21/G22 RESOLVED            |
|    | Dark; tracks arch TBDs.                | session-054 (the blocker).      |
|    |                                        | bp_history GHR/PHR fold         |
|    |                                        | recompute on rollback proven    |
|    |                                        | in-sim (BP-072; canonical fold  |
|    |                                        | def decisions.md s6). Still     |
|    |                                        | deferred to bp_cluster for      |
|    |                                        | rollback stimulus. See TD #7.   |
| 70 | ittage rollback / history recompute.   | Same as #69 for ittage. Shared  |
|    | Dark; tracks arch TBDs.                | GHR/PHR fold logic. G20/G21/G22 |
|    |                                        | RESOLVED session-054; fold      |
|    |                                        | recompute proven in-sim BP-072. |
|    |                                        | Defer to bp_cluster for         |
|    |                                        | stimulus.                       |
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
| 73 | Arbitration layer behavioral test.     | PQ/UQ FIFOs + credit arbiter.   |
|    | Deferred. Pairs with refactor #52.     | Folds in #37, #39, #40. Defer   |
|    |                                        | until uBTB, loop, tage, ittage  |
|    |                                        | units tested. Concurrent        |
|    |                                        | pred+upd is the untested        |
|    |                                        | interaction of interest.        |
| 74 | Dual-slot (NUM_PRED_SLOTS=2) test.     | bp_history part CLOSED          |
|    | bp_history dual-slot fold equivalence  | (BP-072). G20 RESOLVED          |
|    | proven; broader cluster dual-slot      | session-054 (decisions.md s3).  |
|    | still deferred.                        | bp_history dual-slot fold       |
|    |                                        | equivalence (incremental vs     |
|    |                                        | recompute) proven in-sim        |
|    |                                        | BP-072 (19224 golden            |
|    |                                        | comparisons; single-slot,       |
|    |                                        | dual-slot, GHR-wrap, SC ST3).   |
|    |                                        | Externally anchored BP-073.     |
|    |                                        | Broader cluster dual-slot       |
|    |                                        | (slot 1 update path across      |
|    |                                        | TAGE/ITTAGE, both slots         |
|    |                                        | together) still deferred until  |
|    |                                        | after arb #73 and full BPU.     |
|    |                                        | Reduction work in #1.           |
| 75 | ittage there are no fast versions of   | The equivalent TAGE target is   |
|    | the ittage sim targets.                | sim_tage_fast. There is no similar|
|    |                                        | target for ittage, create one   |
|    |                                        | called sim_ittage_fast          |
| 76 | ittage should have independent index   | CLOSED with BP-048 |
|    | buses for primary and alternative      | |
|    | table updates.                         | |
|    | | Since there are different history lengths, and the indexes are |
|    | | hashed based on history length we do in fact need an index bus |
|    | | for primary and alternative. |
|    | | the names should be t_prm_upd_index_u0 and t_alt_upd_index |
|    | | Secondly the names of the ports of ittage_cntrl that touch the tables |
|    | | should use the same convention as tage_cntrl, and begin with t_      |
| 77 | scrub prompts and redact any absolute path | This is not a design TD   |
|    | information not using the RVA_ROOT env var | more of a tools and infra |
|    |                                            | task, possibly manual     |
| 78 | RAS p3 undo-pop does not reverse a   | LEAVE AS-IS. The undo-pop      |
|    | recursion pop. The p3 repair re-     | re-expose moves TOSR back and  |
|    | expose reverses a TOSR-moving pop    | reloads addr/rctr; a pop that  |
|    | only. A pop that only decremented a  | only decremented rctr (TOSR    |
|    | recursion counter (TOSR held) is not | held) leaves no recoverable    |
|    | reversible from post-pop state.      | pre-pop rctr. BP-064 adds a    |
|    |                                      | directed test pinning the      |
|    |                                      | current non-reversing          |
|    |                                      | behavior. Revisit at           |
|    |                                      | bp_cluster integration if an   |
|    |                                      | s2/s3 repair over a recursion  |
|    |                                      | pop is ever required. Related: |
|    |                                      | #79 (commit-side recursion     |
|    |                                      | depth).                        |
| 79 | RAS commit-stack recursion depth not | DEFER (was: fix, reversed      |
|    | preserved. ras.sv writes             | session-051 after evidence).   |
|    | commit_rctr[csp] <= 0 on every       | The field is write-only: it is |
|    | commit push; the field is never      | never read by any output path  |
|    | read. A recursive call that commits  | (pop fallback uses             |
|    | reads back from the commit-stack     | commit_top_addr/valid only),   |
|    | fallback as a single entry, not at   | so a wrong value cannot cause a |
|    | its true recursion depth.            | functional break -- only a     |
|    | Root cause: the commit interface     | degraded fallback prediction.  |
|    | carries no recursion count           | Real fix needs a recursion-    |
|    | (ras_commit_ret_addr is a bare       | count source on the commit     |
|    | address; bp_ras_snapshot_t is        | interface (snapshot/struct      |
|    | pointers only), so there is no       | change) or local commit-stack  |
|    | value at the port to carry.          | detection -- decide at          |
|    |                                      | bp_cluster/FTQ integration when |
|    |                                      | the commit interface is built. |
|    |                                      | Related: #78.                  |
| 80 | FTB confidence hysteresis tuning.    | FTB conf is a 3-bit bimodal     |
| | | direction counter (FTB_CONF_WIDTH=3); the MSB is the predicted       |
| | | direction. At a saturated endpoint (111/000) with ftb_fastpath_en=1, |
| | | FTB commits its direction at s2 and skips the TAGE/SC override for   |
| | | that branch (the fast-path; saves the s3 SC wait). If perf analysis  |
| | | shows the hysteresis is wrong, FTB_CONF_WIDTH is the knob (a         |
| | | parameter sweep; moves FTB_RAM_ENTRY_WIDTH; conf appears in both     |
| | | br0/br1). Options if it degrades: widen FTB_CONF_WIDTH, or disable   |
| | | the fast-path via ftb_fastpath_en. Pure width/policy sweep, not a    |
| | | format change; no explicit direction bit is added (the conf MSB is  |
| | | the direction). Revisit at bp_cluster SPEC numbers. |
| 81 | tb_ftb coverage skews to br0.        | br1 direction/conf-init is     |
| | | exercised once (free-field write); ftb_fastpath_p2[1] and a br1       |
| | | saturation->fast-path path are not directly exercised. The fast-path |
| | | is generated per-field in a loop (shared logic with the tested       |
| | | bit0), so risk is low, but untested. Optional: a small symmetric br1 |
| | | augment to tb_ftb. Not a blocker; the unit is verified green         |
| | | (sim_ftb 99/0, BP-068). |
| 82 | bp_history if/else-if slot cleanup.  | bp_history_decisions.md 3.5:   |
| | | the num_branches>=1 and ==2 cases are two separate if blocks that     |
| | | both assign the fold registers (correct by NBA last-write-wins, dead  |
| | | slot-0 assignment on the ==2 path). Convert to if/else-if. NOT done   |
| | | in BP-071/072/073/074 (each scoped narrowly). Fold into the next      |
| | | bp_history RTL touch or a small cleanup task. No behavior change.     |
| 83 | bp_history decisions.md s6.6 origin  | Fill <XS-COMMIT-SHA> /         |
| | | citation placeholders. The Xiangshan FoldedHistory origin commit and  |
| | | capture date are unset in s6.6. Informational only -- s6 is the       |
| | | authority, not a live dependency -- but the citation should pin a     |
| | | real commit/date so the origin is archivable. Manual, low priority.   |
| 84 | Producer/consumer end-to-end fold    | bp_history fold output proven  |
| | | check. BP-073 proved the bp_history fold VALUE against the canonical  |
| | | definition (decisions.md s6); it did NOT run that fold through the    |
| | | actual TAGE/ITTAGE table index hash to confirm the derived index.     |
| | | Drive a known GHR, take the bp_history fold, hash it in the table,    |
| | | confirm the index against an independently-known value. End-to-end    |
| | | format agreement between producer and consumers. Needs cluster        |
| | | stimulus; resolve at bp_cluster integration. (decisions.md s9.)       |

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
| G5  | RAS commit stack entry count          | RESOLVED session-050.  |
|     |                                       | 16 spec + 32 commit,   |
|     |                                       | static partition.      |
|     |                                       | ras_decisions.md s3.   |
| G6  | RAS recursion counter width           | RESOLVED session-050.  |
|     |                                       | 4b per entry.          |
|     |                                       | ras_decisions.md s5.   |
| G7  | SC threshold value                    | TBD, fixed at impl     |
| G8  | Dual pred bundle split point          | RESOLVED session-050.  |
|     |                                       | Fixed boundary split.  |
|     |                                       | Slot 0: pred_pc+0:31.  |
|     |                                       | Slot 1: pred_pc+32:63. |
|     |                                       | ras_decisions.md s6.1. |
| G9  | Update channel arbitration            | TBD. FTB-3 / IC-FTB-09 |
|     |                                       | also fold in here.     |
| G10 | TAGE/ITTAGE meta overload scheme      | TBD at implementation. |
|     |                                       | FTB-2 (conf x TAGE     |
|     |                                       | meta) folds in here.   |
| G14 | Confidence counter purpose            | Reserved, 4b           |
| G15 | Fold recompute timing concern         | REFRAMED session-054.  |
|     |                                       | No longer a correctness|
|     |                                       | gate; now a perf       |
|     |                                       | measurement (G22       |
|     |                                       | decoupled, stale-fold  |
|     |                                       | cost). decisions.md    |
|     |                                       | s5.3/5.4.              |
| G16 | ignored labeling gap                  |                        |
| G17 | Slot 1 PC derivation (pred_pc+32)     | RESOLVED session-050.  |
|     |                                       | Always pred_pc+32.     |
|     |                                       | Static, not dependent  |
|     |                                       | on slot 0 prediction.  |
|     |                                       | ras_decisions.md s6.1. |
| G18 | carry field consumer in cluster       | TBD at bp_cluster impl |
| G19 | NO_BRANCH target on hit:              | TBD                    |
|     | fall-through PC or zero?              |                        |
|     | See also UI4 in ubtb_interfaces       |                        |
| G20 | bp_history dual slot update path      | RESOLVED session-054.  |
|     | not defined for NUM_PRED_SLOTS=2      | Combined slot-0-then-  |
|     | See HI1 in bp_history_interfaces      | slot-1, bundle ckpt.   |
|     |                                       | decisions.md s3.       |
|     |                                       | Proven in-sim BP-072.  |
|     |                                       | (= HI1)                |
| G21 | rollback_en + pred_valid same-cycle   | RESOLVED session-054.  |
|     | priority undefined                    | Rollback wins, mutually|
|     |                                       | exclusive with update. |
|     |                                       | decisions.md s4.       |
|     |                                       | Proven in-sim BP-072.  |
|     |                                       | (= HI3)                |
| G22 | One-cycle folded output invalid       | RESOLVED session-054.  |
|     | window after rollback                 | Folds STALE not        |
|     |                                       | invalid; predictions   |
|     |                                       | allowed on stale folds.|
|     |                                       | Decoupled from G15.    |
|     |                                       | decisions.md s5.       |
|     |                                       | Proven in-sim BP-072.  |
|     |                                       | (= HI4)                |
| G23 | Checkpoint slot reclaim protocol      | TBD at FTQ impl.       |
|     |                                       | (= bp_history HI5)     |
| G24 | FTB flush protocol (ftb_flush_px)     | TBD at bp_cluster.     |
|     |                                       | IC-FTB-07. Port        |
|     |                                       | reserved, no behavior. |
| G25 | FTB fast-path enable source           | TBD at bp_cluster.     |
|     | (ftb_fastpath_en: CSR / tie /         | confidence doc s10.    |
|     | runtime)                              |                        |

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
- RAS: Dual-stack, static partition, 16 speculative +
  32 commit entries. Simple circular buffer speculative
  stack, pointer-only snapshot recovery.
  See planning/arch/ras_decisions.md.
- FTB: single set-associative array (4-way / 2048 / 512
  sets), 26-bit full tag, tree-PLRU, 2 conditional + 1 jump
  per entry. Storage split: ftb_array (pure 1R1W RAM) +
  ftb_plru (valid + PLRU flops) + ftb_cntrl (logic). conf
  is a bimodal DIRECTION counter; saturated-endpoint
  fast-path (ftb_fastpath_en). FTB target is the ITTAGE-miss
  / RAS-empty fallback. See planning/arch/ftb_decisions.md.
- BPU is decoupled frontend, self-generates next PC
- FTQ depth 64, split fast/slow SRAMs
- History: GHR 256b, PHR 32b, folds recomputed on rollback.
  Pointer module-owned (bp_history holds it, advances by
  num_branches, rollback by checkpoint INDEX). Fold geometry
  is canonical in bp_history_decisions.md s6 (project-owned;
  Xiangshan FoldedHistory cited as origin only). One fold
  definition for update and recompute; increment-oriented
  walk, post-advance checkpoint. Proven in-sim BP-072,
  externally anchored BP-073, doc-RTL verified BP-074.
  (session-055)
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
  TI6 is a TAGE/ITTAGE convention; it does NOT apply to FTB
  (FTB is a single array, both branches from one entry).
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
- Dual pred bundle split: fixed boundary. Slot 0 covers
  pred_pc+0:31, slot 1 covers pred_pc+32:63. Slot 1 PC
  always pred_pc+32. G8/G17 RESOLVED session-050.

### Shared planning documents
    - planning/arch/bp_arb_spec.md                    In progress
        - Dynamic prediction/training arbitration balancing
    - planning/arch/bp_cluster.md                     In progress
        - Branch prediction cluster summary data
    - planning/arch/ras_decisions.md                  Draft
        - RAS micro-architectural decisions (session-050)
    - planning/arch/sram_init.md                      Complete
        - Post reset RAM initialization operation
    - planning/testbenches/manual_tb_decisions.md     Complete
        - General rules for manual testbench creation

### TAGE decomposition
- RTL is available
    - Unit testbenches written
    - Manual testbench written
    - Line coverage > 90%
    - Directed validation complete
    - remaining items deferred
        - #69 rollback -> bp_cluster
        - #67 sram_init non-fast
        - #74 dual-slot (bp_history part closed BP-072;
          TAGE/cluster dual-slot still deferred)
    - Formal validation not started
- BP-006 through BP-032: complete.
- BP-041 manual checks for tage CTR and USE complete
    - tage_cntrl_ctr_update_rules.md -- updated and verified
    - tage_cntrl_use_update_rules.md -- corrected and verified
      session-045. All 6 USE rows pass.
- BP-056 through BP-061: TAGE directed validation
    - BP-056 EPC write proof (#55)
    - BP-057 UAON trigger rules (#58), BUG-003 fixed
    - BP-058 aging / epoch path (#60)
    - BP-059 allocation + write gating (#62)
    - BP-060 prediction-side correctness (#64)
    - BP-061 round-trip capstone (#71)
- Tage planning documents
    - planning/arch/tage_cntrl_alloc_rules.md         Complete
        - Table entry allocation rules
    - planning/arch/tage_cntrl_ctr_update_rules.md    Complete
        - CTR field update rules
    - planning/arch/tage_cntrl_decisions.md           Complete
        - TAGE control behavior, conventions and rules
    - planning/arch/tage_cntrl_uaon_update_rules.md   Complete
        - UAON (Use ALT on newly allocated)  trigger rules
    - planning/arch/tage_cntrl_use_update_rules.md    Complete
        - USE(ful) field update rules. Corrected session-045.
    - planning/arch/tage_table_hash_rules.md          Complete
        - Address and tag generation hashing. Consumes folds
          per bp_history_decisions.md s6 (computation there).
    - planning/arch/tage_table_entry_formats.md       Complete
        - Central specification of table entry fields and ordering
    - planning/interfaces/tage_interfaces.md          Complete
        - TAGE module interface contracts
    - planning/interfaces/tage_table_interfaces.md    Complete
        - TAGE table module interface contracts

### ITTAGE decomposition
- RTL is available
    - Unit testbenches written
    - Line coverage > 90% in progress
    - Directed validation complete
    - remaining items deferred
        - #69/#70 rollback -> bp_cluster
        - #43 CTR width
        - #75 sim_ittage_fast
        - #68 sram_init non-fast
    - Formal validation not started
- BP-034 - BP-042 complete (BP-033 abandoned)
- ITTage planning documents
    - planning/arch/ittage_cntrl_alloc_rules.md         Complete
        - Table entry allocation rules
    - planning/arch/ittage_cntrl_ctr_update_rules.md    Complete
        - CTR field update rules. 33-row table. session-045.
    - planning/arch/ittage_cntrl_decisions.md           Complete
        - ITTAGE control behavior, conventions and rules
    - planning/arch/ittage_cntrl_uaon_update_rules.md   Complete
        - UAON (Use ALT on newly allocated)  trigger rules
    - planning/arch/ittage_cntrl_use_update_rules.md    Complete
        - USE(ful) field update rules. Corrected session-045.
    - planning/arch/ittage_table_entry_formats.md       Complete
        - Central specification of table entry fields and ordering
    - planning/arch/ittage_table_hash_rules.md          Complete
        - Address and tag generation hashing. Consumes folds
          per bp_history_decisions.md s6 (computation there).
    - planning/interfaces/ittage_interfaces.md          Complete
        - ITTAGE module interface contracts
    - planning/interfaces/ittage_table_interfaces.md    Complete
        - ITTAGE table module interface contracts

### RAS decomposition
- Planning document created session-050.
    - planning/arch/ras_decisions.md                  Draft
        - RAS micro-architectural decisions
    - planning/interfaces/ras_interfaces.md           Draft
        - RAS module interface contracts
- RTL available:
    - rtl/ras.sv                   complete (BP-062)
    - tb/tb_ras.sv                 complete (BP-063)
    - sim_ras 87/0 (BP-064 this session)
    - TD #78 pinned (tb_ras TC-21), TD #79 (commit_rctr)
      deferred -- see PROJECT_STATUS Technical Debt.
- Key decisions session-050:
    - G5: 16 speculative + 32 commit, static partition
    - G6: 4b recursion counter, in scope for initial design
    - G8: fixed boundary bundle split
    - G17: slot 1 PC always pred_pc+32
    - Internal structure: simple circular buffer

### FTB decomposition
- RTL available and verified (session-053):
    - rtl/core/frontend/bpu/rtl/ftb_array.sv   complete (BP-065/065a)
    - rtl/core/frontend/bpu/rtl/ftb_plru.sv    complete (BP-065a)
    - rtl/core/frontend/bpu/rtl/ftb_cntrl.sv   complete (BP-066/066a/066b)
    - rtl/core/frontend/bpu/rtl/ftb.sv         complete (BP-067)
    - rtl/core/frontend/bpu/tb/tb_ftb.sv       complete (BP-068)
    - sim_ftb 99/0 (BP-068). Full bpu suite green, no regression.
- Structure:
    - ftb_array: 1R1W DATA RAM, FTB_RAM_SET_WIDTH=420, no reset
    - ftb_plru:  entry-valid + tree-PLRU, resettable flops (cold
                 init; FTB has no sram_init)
    - ftb_cntrl: all logic (read / classify / way-match / allocate /
                 update / conf bimodal direction + fast-path)
    - ftb:       structural top
- Key decisions session-053:
    - Storage split for eventual SRAM migration (ftb_array pure RAM;
      ftb_plru holds resettable valid + PLRU; IC-FTB-12/13/14)
    - conf = 3-bit bimodal DIRECTION counter (MSB = direction); no
      always_taken bit; ftb_brI_taken_p2 = valid & conf[MSB]
    - Saturated-endpoint fast-path (ftb_fastpath_en / ftb_fastpath_p2);
      self-correcting; TAGE/SC still trained under fast-path
    - Position field sourced/sunk (FTB-4 closed; IC-FTB-15)
    - Final widths: logical 106/424, RAM 105/420
- Deferred to bp_cluster: flush (IC-FTB-07 / G24), conf x TAGE meta
  (FTB-2 / G10), update arbitration (FTB-3 / IC-FTB-09 / G9), FTQ
  round-trip (IC-FTB-10), ftb_fastpath_en source (G25)
- FTB planning documents
    - planning/arch/ftb_decisions.md                   Complete
        - FTB micro-architectural decisions (canonical authority)
    - planning/interfaces/ftb_interfaces.md            Complete
        - FTB module interface contracts
    - planning/arch/ftb_confidence_override_rules.md   Complete
        - conf bimodal direction + saturated-endpoint fast-path policy

### bp_history decomposition
- COMPLETE at unit level (session-055). Module-owned pointer,
  corrected/increment-oriented fold geometry, canonical fold
  definition captured natively, suite green.
- Planning documents (session-054, extended session-055):
    - planning/arch/bp_history_decisions.md           Draft
        - G20/G21/G22 resolution + module-owned pointer
        - s6 canonical Fold Definition (session-055): age
          indexing, posmap(i)=(i+W-1)%W, eviction at (H-1)%W,
          recompute==incremental invariant, worked example
          (0xD3 -> 0xE5). Xiangshan demoted to origin footnote
          s6.6 (sha TBD, #83).
        - s7 checkpoint POST-advance ratified; s10 pointer-
          authority wording corrected.
    - planning/interfaces/bp_history_interfaces.md    Draft
        - Target interface (module-owned ptr, dual-slot,
          rollback by index, stale folds). Checkpoint Timing
          (post-advance) consistent with decisions.md s7
          (confirmed BP-074).
- RTL:
    - rtl/core/frontend/bpu/rtl/bp_history.sv         Complete
        - Module-owned pointer (BP-069)
        - Fold geometry corrected to Xiangshan, 64b helpers
          (BP-071); increment-oriented walk + post-advance
          checkpoint reconciled with the incrementing pointer
          (BP-072). See BUG-004 / BUG-005.
        - Lint clean; no bpu regression.
- Verification:
    - BP-072: dual-slot fold equivalence (TD #74) proven in-sim;
      16 directed TCs, 19224 golden fold comparisons; single-slot,
      dual-slot, GHR-boundary wrap, SC ST3 (H=W=64). sim_history /
      cov_history / cov_bpu restored green.
    - BP-073: external fold-value anchor (TC14-16) against the
      canonical definition (TAGE T1 0xE5, ITTAGE IT1 0x9, SC ST3
      0xC000_0000_0000_0000). Hash-rule docs found to define fold
      CONSUMPTION only -> motivated the s6 capture.
    - BP-074: doc-RTL consistency audit of s6; repo drift isolated;
      cross-references resolve; s6 matches fold_ghr/fold_step;
      worked examples re-derived from s6 reproduce the committed
      literals and DUT output; full bpu 33/33 green.
- Key decisions session-054:
    - G20: combined slot-0-then-slot-1 dual-slot update, bundle
      checkpoint granularity
    - G21: rollback wins (mutually exclusive with update)
    - G22: folds stale not invalid; predictions allowed on stale
      folds; decoupled from G15
    - Pointer module-owned: internal sequential advance, rollback
      by checkpoint index. Mispredict-only restore (exceptions /
      interrupts reinitialize history, do not use the checkpoint
      path)
- Key decisions session-055:
    - Fold geometry captured natively (decisions.md s6); the
      definition no longer depends on the external Xiangshan source
    - Checkpoint timing ratified POST-advance (s7); recompute
      anchor ckpt-1, num_branches-independent
- Open / deferred:
    - HI2 (PHR fold mixing) -> TAGE/ITTAGE hashing
    - HI5 (checkpoint slot reclaim) -> FTQ (= G23)
    - #82 if/else-if slot cleanup (decisions 3.5; not done)
    - #83 s6.6 Xiangshan origin sha/date fill (manual)
    - #84 producer/consumer end-to-end fold check -> bp_cluster
    - #69/#70 rollback stimulus -> bp_cluster
    - versions/bp_history.sv (stale BP-069 copy) superseded by the
      merged rtl/ file; retire it (BUG-005)

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

