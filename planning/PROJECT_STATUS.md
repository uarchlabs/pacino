<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Project Status -- RISC-V RVA23 Processor Co-Design
```
 FILE:    PROJECT_STATUS.md
 SOURCE:  various
 STATUS:  WORKING
 UPDATED: 2026-07-03 (pa session 061)
 CONTACT: Jeff Nye
```

Updated every session. Paste into Claude.ai at session start,
along with the latest session_handoff-NNN.md and CLAUDE.md.

Paste PROJECT_CORE.md only when methodology is under discussion.

---

## Session-061: Planning Document Audit (INFRA-008/009/010)

Before starting bp_cluster top-level design, three read-only IA
audits checked the FTB, TAGE/SC, and ITTAGE/RAS planning documents
against the shipped RTL/tb/Makefile for each group:

  INFRA-008 (ftb):        clean, no issues found.
  INFRA-009 (tage, sc):   12 findings, all doc drift, all fixed.
  INFRA-010 (ittage, ras): 10 findings -- 8 doc drift (fixed) plus
                            2 real design/RTL gaps, each resolved by
                            a Jeff ruling (doc fixed this session,
                            RTL-side gap opened as a new TD):
    - Indirect-CALL ownership: ITTAGE predicts the target, RAS
      separately pushes the return address. Both are in scope for
      indirect CALL, each for a different job. ittage_interfaces.md
      corrected (previously said RAS "exclusively").
    - ITTAGE IT5: NOT a BrIMLI table. The "BrIMLI, no folds" framing
      in bp_history_decisions.md and bp_cluster.md was a copy-paste
      artifact from SC's real BrIMLI table (ST4). IT5 has real
      folded history (FH=9b, FH1=9b, FH2=8b, hist=32b, per
      bp_defines_pkg.sv, which was already correct). Docs corrected.
      RTL gap (bp_history.sv never generates the IT5 folds it's
      wired to) opened as TD #102.

New TDs opened this session: #101 (ras.sv ras_pc_p2 dead/undocumented
port), #102 (bp_history.sv missing IT5 fold generation), #104 (two
stale RTL comments found during INFRA-008, see Technical Debt table).

CONFLICT TO RESOLVE: TD#103 (added by Jeff, tage T0 init value) states
T0 should initialize to weakly-taken (2'b10) and that the current
00 (strongly-not-taken) init is a bug. INFRA-009 this same session
corrected tage_cntrl_decisions.md's T0 init description FROM "10" TO
"00" -- that correction was made to match CURRENT RTL/package behavior
(TAGE_SRAM_INIT_VALUE=0 in bp_defines_pkg.sv), not to assert 00 is the
intended value. The doc now accurately describes what the RTL does
today, which TD#103 says is wrong. When TD#103 is resolved (RTL and/or
TAGE_SRAM_INIT_VALUE changed to 2), tage_cntrl_decisions.md's T0 init
line must be updated again to match. Do not treat the session-061 doc
correction as having settled the "what should T0 init to" question --
it only documented current behavior.

FTB/TAGE-SC/ITTAGE-RAS planning docs are current as of this audit
(module the TD#103 conflict above, which is an open RTL question, not
a doc-vs-doc conflict). Safe to treat as interface authority for
bp_cluster top-level design.

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
|                         |             |                   | SC params session-056:           |
|                         |             |                   | SC_NUM_TABLES=5 (SC_NUM_ALL_TBLS |
|                         |             |                   | removed); dynamic threshold      |
|                         |             |                   | SC_THRSH_BITS/MIN/MID/MAX,        |
|                         |             |                   | SC_TC_BITS, SC_LSUM_BITS,         |
|                         |             |                   | SC_CHOOSER_*; SC_LO/HI_THRESHOLD  |
|                         |             |                   | removed (now dynamic).           |
|                         |             |                   | Threshold values corrected       |
|                         |             |                   | session-057: SC_THRSH_BITS=10,   |
|                         |             |                   | SC_THRSH_MID=10, SC_THRSH_MAX=   |
|                         |             |                   | 512, SC_TC_BITS=7 (O-GEHL).      |
|                         |             |                   | SC arb params: SC_UQ_DEPTH,      |
|                         |             |                   | SC_UQ_WR_PORTS, SC_RESP_BUF_     |
|                         |             |                   | DEPTH, SC_PRED_CREDITS, SC_UPD_  |
|                         |             |                   | CREDITS, SC_STARVE_THRESH; no    |
|                         |             |                   | SC_PQ_DEPTH.                     |
| bp_structs_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE structs complete.|
|                         |             |                   | IT5 fold fields present in       |
|                         |             |                   | struct (II1); generation gap in  |
|                         |             |                   | bp_history.sv tracked TD#102.    |
|                         |             |                   | bp_ras_snapshot_t comment        |
|                         |             |                   | updated session-050.             |
|                         |             |                   | tb_bp_pkg.sv 6->4b literal fix   |
|                         |             |                   | (BP-062, authorized).            |
|                         |             |                   | SC structs session-056:          |
|                         |             |                   | sc_pred_meta_t, sc_upd_inp_t      |
|                         |             |                   | populated; bp_sc_meta_t and       |
|                         |             |                   | cond_pred_meta_t/cond_pred_upd_   |
|                         |             |                   | inp_t commented out (superseded); |
|                         |             |                   | bp_sc_chooser_e, br_imli_mode_e   |
|                         |             |                   | added; tage_pred_meta_t gains     |
|                         |             |                   | tage_extd_ctr field (TAGE gen     |
|                         |             |                   | TD#87/#88). SC session-057:       |
|                         |             |                   | sc_pred_meta_t.pc_range removed;  |
|                         |             |                   | captured_phr commented out.       |
|                         |             |                   | Session-058: sc_pred_meta_t       |
|                         |             |                   | sc_upd_idx/sc_upd_ctr -> packed   |
|                         |             |                   | 2D arrays (Verilator).           |
|                         |             |                   | Session-060 BP-081: tage_pred_    |
|                         |             |                   | weak re-added to tage_pred_meta_t;|
|                         |             |                   | tage_high_conf/tage_provider_ctr  |
|                         |             |                   | confirmed absent (internal only). |
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
|                         |             |                   | Session-061 (INFRA-010): IT5     |
|                         |             |                   | fold generation confirmed MISSING|
|                         |             |                   | -- ittage.sv wires it_t5_* to    |
|                         |             |                   | outputs this module never drives.|
|                         |             |                   | TD#102.                          |
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
|                         |             |                   | Session-061 (INFRA-010): removed |
|                         |             |                   | incorrect "IT5 (BrIMLI), no      |
|                         |             |                   | folds" claim (s1, s8); IT5 has   |
|                         |             |                   | real folded history, not BrIMLI. |
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
|                         |             |                   | applied. Session-061 (INFRA-009):|
|                         |             |                   | tage_pred_strong corrected from  |
|                         |             |                   | "NOT WEAK" to the actual TD#87   |
|                         |             |                   | one-hot decode; tage_extd_ctr    |
|                         |             |                   | added; dead tage_high_conf ref   |
|                         |             |                   | removed.                         |
| tage_table_interfaces.md| Draft       | --                | Created session-016.             |
|                         |             |                   | Updates pending.                 |
| tage_cntrl_use          | Complete    | --                | session-037: complete.           |
| _update_rules.md        |             |                   | session-045: DIFF corrected.     |
|                         |             |                   | TTM row added. Notes corrected.  |
|                         |             |                   | Aging disabled section added.    |
| tage_cntrl_uaon         | Complete    | --                | session-036: verified.           |
| _update_rules.md        |             |                   | Debt #45 closed BP-032.          |
|                         |             |                   | Promoted Complete BP-057.        |
|                         |             |                   | Session-060: reconciled to TD#87 |
|                         |             |                   | (UAON gate on tage_pred_weak;    |
|                         |             |                   | strong redefined {000,111}) via  |
|                         |             |                   | tage_tmp_uaon_update_rules.md,   |
|                         |             |                   | folded into canonical doc.       |
| tage_cntrl              | Complete    | --                | session-044: X entries expanded. |
| _ctr_update_rules.md    |             |                   | Unreachable rows removed.        |
|                         |             |                   | ADR-001 added.                   |
|                         |             |                   | Verified session-045 via         |
|                         |             |                   | tage_use_test all 6 rows pass.   |
| tage_cntrl_decisions.md | Complete    | --                | Session-061 (INFRA-009): T0 RAM  |
|                         |             |                   | index corrected pc[11:1] ->      |
|                         |             |                   | pc[12:2]; T0 init value corrected|
|                         |             |                   | to 00 to MATCH CURRENT RTL (see  |
|                         |             |                   | TD#103 conflict, top of file --  |
|                         |             |                   | this doc now describes current   |
|                         |             |                   | behavior, not necessarily correct|
|                         |             |                   | behavior); "decoration flags"    |
|                         |             |                   | list updated for TD#87/#88;      |
|                         |             |                   | CTR-update summary "rows 18-21"  |
|                         |             |                   | corrected to note that case is   |
|                         |             |                   | architecturally impossible.      |
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
|                         |             |                   | Session-060 BP-081: tage_high_   |
|                         |             |                   | conf deleted; TD#87 strong/med/  |
|                         |             |                   | weak decode + TD#88 extd_ctr     |
|                         |             |                   | generated; UAON gate moved to    |
|                         |             |                   | tage_pred_weak (behavior-        |
|                         |             |                   | preserving). Elaborates, lints   |
|                         |             |                   | clean. TD#103 OPEN: T0 init      |
|                         |             |                   | value under review (00 vs        |
|                         |             |                   | intended weakly-taken 10).       |
| tage.sv                 | Complete    | tb_tage           | BP-056 through BP-061 complete.  |
|                         |             |                   | BP-010 through BP-030 complete.  |
|                         |             |                   | Directed validation complete.    |
|                         |             |                   | All coverage targets closed or   |
|                         |             |                   | deferred.                        |
|                         |             |                   | tage_assert.sv bound via bind.   |
|                         |             |                   | Session-060 BP-081: uq_data_mem/ |
|                         |             |                   | rb_meta_mem retyped off cond_    |
|                         |             |                   | pred_* to tage_upd_inp_t/tage_   |
|                         |             |                   | pred_meta_t (whole-struct        |
|                         |             |                   | writes). Elaborates green.       |
|                         |             |                   | sim_tage 105/0, sim_tage_fast    |
|                         |             |                   | 105/0.                           |
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
|                         |             |                   | sim_tage 105 tests as of BP-081  |
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
|                         |             |                   | session-045. Session-060 BP-081: |
|                         |             |                   | 4 tage_high_conf taps removed    |
|                         |             |                   | (incl tb_tage_manual_tasks.svh); |
|                         |             |                   | sim_tage_manual 3/3.             |
| ittage_interfaces.md              | Draft       | --    | session-036: corrections applied.|
|                                   |             |       | session-037: II6 resolved.       |
|                                   |             |       | session-038: redundancy collapse |
|                                   |             |       | applied. Session-061 (INFRA-010):|
|                                   |             |       | indirect-CALL ownership corrected|
|                                   |             |       | (ITTAGE + RAS both in scope, not |
|                                   |             |       | "RAS exclusively"); IT5 BrIMLI/  |
|                                   |             |       | no-folds language removed (II1); |
|                                   |             |       | IT_SRAM_INIT_VALUE name corrected|
|                                   |             |       | (was ITTAGE_SRAM_INIT_VALUE).    |
| ittage_table_interfaces.md        | Draft       | --    | Created session-036.             |
|                                   |             |       | session-038: redundancy collapse |
|                                   |             |       | applied. Session-061 (INFRA-010):|
|                                   |             |       | "4 total writes" claim corrected |
|                                   |             |       | (ITTAGE writes one CTR per slot  |
|                                   |             |       | per update, unlike TAGE); single |
|                                   |             |       | tgt_wr_u0 port split into        |
|                                   |             |       | prm_tgt_wr_u0/alt_tgt_wr_u0 to   |
|                                   |             |       | match RTL.                       |
| ittage_cntrl_alloc_rules.md       | Complete    | --    | Created session-033.             |
|                                   |             |       | session-036: verified. Session-  |
|                                   |             |       | 061 (INFRA-010): allocation      |
|                                   |             |       | write-data field order corrected |
|                                   |             |       | [TAG,EPC,USE,CTR,TGT,VALID] ->   |
|                                   |             |       | [TAG,TGT,EPC,USE,CTR,VALID]      |
|                                   |             |       | (was building a corrupt entry if |
|                                   |             |       | followed literally); doc         |
|                                   |             |       | cross-reference corrected.       |
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
| ittage_table_entry_formats.md     | Complete    | --    | Session-061 (INFRA-010): TAG     |
|                                   |             |       | field width parameter corrected  |
|                                   |             |       | IT_TBL_TGT_WIDTH -> IT_TBL_TAG[t]|
|                                   |             |       | (was citing the target-width     |
|                                   |             |       | parameter for the tag field).    |
| ittage_table.sv  | Complete       | tb_ittage_table | BP-033/033-FIX-1 complete. |
| ittage_cntrl.sv  | Complete       | tb_ittage_cntrl | Prediction path complete BP-034|
|                  |                |                 | Update path complete BP-035      |
|                  |                |                 | Testbench complete BP-036        |
|                  |                |                 | CTR/USE tests complete BP-044/a/b/c |
|                  |                |                 | 147 tests passing w/ BP-048       |
|                  |                |                 |  UAON/aging/alloc verified BP-051/2/3 |
|                  |                |                 |  ittage_cntrl is complete   |
| ittage.sv        | Complete       | tb_ittage | BP-034/035/35a/35b                |
|                  |                |           | shell without arb cntrl complete  |
|                  |                |           | sim_ittage 211 pass / 0 fail      |
|                  |                |           | tests added BP-054.               |
|                  |                |           | round trip tests added in BP-055. |
|                  |                |           | Session-061: IT5 fold ports       |
|                  |                |           | confirmed wired to bp_history.sv  |
|                  |                |           | outputs that are never driven     |
|                  |                |           | (permanently 0). TD#102.          |
| ras_decisions.md | Draft          | --             | Created session-050.             |
|                  |                |                | G5/G6/G8/G17 decisions recorded. |
|                  |                |                | Reconciled to RTL BP-064         |
|                  |                |                | (sec 1/1.2, 3.2, 3.3/4.5).       |
|                  |                |                | Renamed to p-naming session-057. |
|                  |                |                | See BP Cluster Open TBDs.        |
|                  |                |                | Session-061 (INFRA-010):         |
|                  |                |                | RAS_COMMIT_PTR_WIDTH corrected to|
|                  |                |                | RAS_COMMIT_PTR_BITS (param       |
|                  |                |                | already exists, doc wrongly said |
|                  |                |                | "not yet added"), sections 9/11. |
| ras_interfaces.md| Draft          | --             | Created session-050. IC-RAS-11   |
|                  |                |                | repair semantics appended BP-064.|
|                  |                |                | Session-061 (INFRA-010): added   |
|                  |                |                | previously-undocumented port     |
|                  |                |                | ras_pc_p2 to the port list        |
|                  |                |                | (present in ras.sv, unread; see  |
|                  |                |                | TD#101).                          |
| ras.sv           | Complete       | tb_ras         | RTL BP-062, tb BP-063. sim_ras   |
|                  |                |                | 87/0 this session (BP-064).      |
|                  |                |                | TD #78 pinned (TC-21); TD #79    |
|                  |                |                | (commit_rctr) deferred. TD#101   |
|                  |                |                | OPEN: ras_pc_p2 input declared,  |
|                  |                |                | unread -- confirm needed or      |
|                  |                |                | remove.                          |
| ftb_decisions.md | Complete       | --             | Created session-051. Storage     |
|                  |                |                | split, bimodal conf, fast-path,  |
|                  |                |                | position fix (session-053).      |
|                  |                |                | Promoted Complete session-053.   |
| ftb_interfaces.md| Complete       | --             | Created session-052. Storage     |
|                  |                |                | ports (3/3a) + IC-FTB-12..15     |
|                  |                |                | session-053.                     |
| ftb_confidence   | Complete       | --             | conf = bimodal direction,        |
| _override        |                |                | fast-path, ftb_fastpath_en       |
| _rules.md        |                |                | (session-053).                   |
| ftb_array.sv     | Complete       | sim_ftb        | 1R1W data RAM, no reset.         |
|                  |                |                | BP-065 / BP-065a.                |
| ftb_plru.sv      | Complete       | sim_ftb        | entry-valid + tree-PLRU flops,   |
|                  |                |                | cold init. BP-065a.              |
| ftb_cntrl.sv     | Complete       | sim_ftb        | All FTB logic. BP-066 /          |
|                  |                |                | BP-066a (conf/fast-path) /       |
|                  |                |                | BP-066b (position). Session-061  |
|                  |                |                | (INFRA-008): stale header comment|
|                  |                |                | "107 bits/way" noted, actual 105.|
|                  |                |                | Comment-only, not fixed this     |
|                  |                |                | session; see TD#104.             |
| ftb.sv           | Complete       | tb_ftb         | Structural top. BP-067.          |
|                  |                | sim_ftb        | sim_ftb 99/0 (BP-068). Session-  |
|                  |                |                | 061 (INFRA-008): stale comment   |
|                  |                |                | noted -- says ftb_fastpath_en is |
|                  |                |                | "beyond the interface draft";    |
|                  |                |                | it's a documented port now.      |
|                  |                |                | Comment-only, not fixed this     |
|                  |                |                | session; see TD#104.             |
| sc_decisions.md  | Draft          | --             | Created session-056. Five pure-  |
|                  |                |                | counter tables ST0-ST4, no tags, |
|                  |                |                | ST4=BrIMLI. Dynamic threshold    |
|                  |                |                | (O-GEHL). Two-corner chooser.    |
|                  |                |                | BrIMLI register/update/index from|
|                  |                |                | cookbook predictor.h. Update gate|
|                  |                |                | verified vs gem5 SC / Jimenez-Lin|
|                  |                |                | perceptron / 2011 MICRO.         |
|                  |                |                | Session-057: 056 open items      |
|                  |                |                | closed; counter capture/sign/    |
|                  |                |                | override fixed; pc_range removed;|
|                  |                |                | threshold params corrected;      |
|                  |                |                | TD#93 added. Session-057 at rest.|
|                  |                |                | Session-059: s12 br_imli_mode    |
|                  |                |                | specified compile-time parameter |
|                  |                |                | (BP-079); s9 st4 note.           |
| sc_table.sv      | Complete       | tb_sc_table    | ST0-ST3 counter tables. BP-075/  |
|                  |                | sim_sc_table   | 075a. sim_sc_table 6/0 (+fast).  |
|                  |                |                | Two bw_ram per slot (TI6).       |
| sc_brimli.sv     | Complete       | tb_sc_brimli   | ST4 BrIMLI table. BP-076.        |
|                  |                | sim_sc_brimli  | sim_sc_brimli 7/0 (+fast).       |
|                  |                |                | BR_IMLI_MODE compile-time param  |
|                  |                |                | (BP-079).                        |
| sc_cntrl.sv      | Complete       | tb_sc_cntrl    | SC control layer. BP-077.        |
|                  |                | sim_sc_cntrl   | sim_sc_cntrl 98/0. br_imli_mode  |
|                  |                |                | + t_br_imli_mode ports removed   |
|                  |                |                | (BP-079).                        |
| sc.sv            | Complete       | tb_sc          | SC structural top. BP-078.       |
|                  |                | sim_sc         | sim_sc 55/0, sim_sc_fast 52/0.   |
|                  |                |                | Index-width adapters; single     |
|                  |                |                | sram_init sized to ST4; arb      |
|                  |                |                | ports stubbed (TD#73/#94);       |
|                  |                |                | SC_BR_IMLI_MODE param (BP-079).  |
| sc_interfaces.md | Complete       | --             | Written session-058. Session-061 |
|                  |                |                | (INFRA-009): Arbitration Model   |
|                  |                |                | section corrected -- SC update   |
|                  |                |                | queue is currently STUBBED at    |
|                  |                |                | unit level (was documented as    |
|                  |                |                | functional), real arbiter        |
|                  |                |                | deferred to bp_cluster (TD#73/   |
|                  |                |                | #94).                            |
| sc_table_interfaces.md | Complete  | --             | Written session-058. Session-061 |
|                  |                |                | (INFRA-009): br_imli_mode        |
|                  |                |                | corrected from documented runtime|
|                  |                |                | port to actual compile-time      |
|                  |                |                | parameter (BR_IMLI_MODE,         |
|                  |                |                | BP-079).                          |
| sc_table_hash_rules.md | Complete  | --             | Written session-058. Session-061 |
|                  |                |                | (INFRA-009): br_imli_mode param  |
|                  |                |                | status corrected, same as above. |
| sc_tb_decisions.md | Complete     | --             | Session-061 (INFRA-009): ST0 tb  |
|                  |                |                | coverage claim corrected --      |
|                  |                |                | tb_sc_table.sv only instantiates |
|                  |                |                | ST1; ST0's zero-fold path is     |
|                  |                |                | untested at unit level. Coverage |
|                  |                |                | gap noted, no TD assigned.       |
| SC (unit)        | Complete       | --             | Tables+control+top green         |
|                  |                |                | (BP-075..079). Remaining unit    |
|                  |                |                | item: sc_coverage_plan.md.       |
|                  |                |                | Cluster prereqs #89-#92 open     |
|                  |                |                | (#87/#88 CLOSED BP-081).         |
| bp_cluster (top) | Not started    | --             | After predictors complete. Doc-  |
|                  |                |                | audit (INFRA-008/009/010)        |
|                  |                |                | complete session-061; planning   |
|                  |                |                | docs current (TD#103 excepted,   |
|                  |                |                | see note at top of file).        |
| fetch            | Not started    | --             | After BP cluster                 |

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
| 40 | TB-ARB-05 spec discrepancy.           | bp_arb_spec.md testbench section|
|    | Old "backpressure 2 cycles" note did  | (was 10.1) removed session-057; |
|    | not match TAGE_UQ_DEPTH=8.            | tb requirements now live in the |
|    | No RTL risk.                          | implementing task file. Verify  |
|    |                                       | UQ_DEPTH there before bp_cluster|
|    |                                       | integration. No RTL change.     |
| 42 | Pipeline diagram shows ITTAGE at s3,  | Revisit after SC definition.    |
|    | should be s2 (alongside FTB, TAGE).   | Update diagram and discussions. |
|    |                                       | See prediction-side item #65.   |
|    |                                       | #65 is now CLOSED, BP-054       |
| 43 | Reduce ITTAGE CTR width 3b -> 2b.     | Impacts bp_defines_pkg.sv,      |
|    |                                       | ittage_table_interfaces.md, RTL |
|    |                                       | and testbenches. Confirm no     |
|    |                                       | testcase impact (see #44).      |
| 49 | Arb queue status pin renaming.         | pq_not_full/upd_rdy ->          |
|    |                                        | tage_pq_not_full/tage_uq_not_   |
|    |                                        | full and ittage_ equivalents.   |
|    |                                        | Scope: RTL, tb, bp_arb_spec.md, |
|    |                                        | tage_interfaces.md,             |
|    |                                        | ittage_interfaces.md.           |
| 52 | Move arb logic into submodule out of   | Top modules should be           |
|    | top in tage and ittage.                | structural only. New arb module |
|    | (Refactor; pairs with #73 test.)       | for tage and ittage. Co-        |
|    |                                        | sequence with arb test #73.     |
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
| | | SC ST1-ST3 are additional consumers of the same folds -- fold this    |
| | | into the SC end-to-end check (handoff-057).                           |
| 85 | bp_structs_pkg.sv    | review BPU structures for opportunities to    |
|    |                      | combine/share fields and potential storage/flops     |
| 86 | sc_cntrl  | choosing not to add the scaled tage ctr into the SC sum  |
|    |           | calculation, concerns about timing.                      |
|    |           |                                                          |
|    |           | The current sum (sc_decisions.md s8) includes            |
|    |           | tage_extd_ctr at weight 1. This TD is the 8x-weighted     |
|    |           | variant, deferred.                                       |
|    |           |                                                          |
|    |           | Consider this equation once PD and perf are in progress  |
|    |           |                                                          |
|    |           | sum = (2 * ST0[st0_idx].ctr + 1)                         |
|    |           |     + (2 * ST1[st1_idx].ctr + 1)                         |
|    |           |     + (2 * ST2[st2_idx].ctr + 1)                         |
|    |           |     + (2 * ST3[st3_idx].ctr + 1)                         |
|    |           |     + (2 * ST4[st4_idx].ctr + 1)                         |
|    |           |     + 8 * (2 * tage_provider_ctr + 1) (see below)        | 
|    |           |                                                          |
|    |           | (of course no multiplies would be used.)                 |
|    |           | NOTE: this has changed, tage_provider_ctr is now called  |
|    |           | tage_extd_ctr. The tage term in the equation above has   |
|    |           | changed to:                                              |
|    |           |     + tage_extd_ctr
|    |           |                                                          |
| 87 | tage      | CLOSED BP-081 (session-060). Strong/medium/weak decode   |
|    |           | generated in tage_cntrl on the post-mux provider CTR per |
|    |           | the table below; tage_pred_weak re-added to              |
|    |           | tage_pred_meta_t; tage_pred_strong redefined to strictly |
|    |           | {000,111} (was NOT WEAK). Functional coverage added in   |
|    |           | tb_tage (pred_conf_decode_tst, all 8 CTR values x both   |
|    |           | slots). UAON gate moved to tage_pred_weak (behavior-     |
|    |           | preserving); tage_cntrl_uaon_update_rules.md reconciled. |
|    |           |                                                          |
|    |           | 000  strongly not taken  tage_pred_strong = 1'b1         |
|    |           | 001  medium   not taken  tage_pred_medium = 1'b1         |
|    |           | 010  medium   not taken  tage_pred_medium = 1'b1         |
|    |           | 011  weak     not taken  tage_pred_weak   = 1'b1         |
|    |           | 100  weak     taken      tage_pred_weak   = 1'b1         |
|    |           | 101  medium   taken      tage_pred_medium = 1'b1         |
|    |           | 110  medium   taken      tage_pred_medium = 1'b1         |
|    |           | 111  strongly taken      tage_pred_strong = 1'b1         |
|    |           |                                                          |
|    |           | SC prediction (sc_decisions.md s8) consumes              |
|    |           | tage_pred_medium; now generated for real (was interim    |
|    |           | tie-off plan; superseded).                               |
| 88 | tage      | CLOSED BP-081 (session-060). tage_extd_ctr generated in  |
|    |           | tage_cntrl from the post-mux provider CTR:               |
|    |           |                                                          |
|    |           | provider_ctr = tage_using_primary                        |
|    |           |              ? tage_prm_ctr : tage_alt_ctr               |
|    |           |   (equals the existing post-mux CTR; reused, no new mux) |
|    |           |                                                          |
|    |     | logic signed [TAGE_MAX_CTR_WIDTH+1:0] tage_extd_ctr;           |
|    |     | tage_extd_ctr = $signed({2'b00, provider_ctr, 1'b0}) - 5'sd7;  |
|    |           |                                                          |
|    |           | Observed extd_ctr sweep -7,-5,-3,-1,+1,+3,+5,+7 verified |
|    |           | in tb_tage. provider_ctr stays an internal convenience   |
|    |           | signal, NOT a struct field. SC sum (sc_decisions.md s8)  |
|    |           | consumes tage_extd_ctr; now generated for real.          |
|    |           |                                                          |
|    |           | NOTE: BP-081 wraps the concat->signed-5b assignment in   |
|    |           | an inline lint_off/on WIDTHTRUNC bracket (lint_tage_     |
|    |           | cntrl/lint_tage carry no project WIDTHTRUNC suppress).   |
|    |           | Range [-7,+7] fits; top concat bit is redundant sign     |
|    |           | extension. Review the bracket is minimal next touch.     |
| 89 | ftb       | Change the FTB definition to store 20 additional bits.   |
|    |           | These are PC bits [15:6] of branch location              |
|    |           | These will be supplied to sc_upd_inp.branch_range
|    |           |                                                          | 
| 90 | ftb       | Change the FTB to store 2 additional bits. the signs of  |
|    |           | the branch targets for conditional branch 0/1 should be  |
|    |           | stored as backwards_branch0/1.                           |
|    |           | These will be supplied to sc_upd_inp.backwards_branch    |
|    |           | There are two bits, one for each prediction slot         |
|    |           | |
| 91 | bpc       | TD#91 Top level bpc needs to route tage_pred_inp.pc to   |
|    |           | the ports of the SC, this must be staged from p0 to p2.  |
|    |           | SC will get additional port(s) pc[0:NUM_PRED_SLOTS-1];   |
|    |           | There are two of these, one for each prediction slot     |
|    |           |                                                          | 
| 92 | bpc/sc    | TD#92 add SC port that captures bits [9:0] of            |
|    |           | bp_folded_hist.tage_phr internally SC pipes this to p2,  |
|    |           | signal is called sc_phr_p2                               |
|    |           |                                                          | 
| 93 | sc    | SC efficacy and threshold/band tuning -- deferred         |
|    |       | investigation. Prior (non-reusable) analysis showed       |
|    |       | marginal-to-no benefit from a baseline SC over TAGE       |
|    |       | alone. This design pulls later-literature mechanisms      |
|    |       | (O-GEHL dynamic threshold, two-corner chooser, BrIMLI)    |
|    |       | specifically to test whether they recover gains the       |
|    |       | baseline SC did not. Open questions to settle at PD/perf: |
|    |       | (1) does SC earn its area/power here at all; (2) seed     |
|    |       | SC_THRSH_MID=10 (Seznec: ~num_tables; 2x for the          |
|    |       | 2 * ctr+1 weighting) and SC_THRSH_MAX=512 vs achievable   |
|    |       | |sum|~322 -- confirm under real traces; (3) the vlo/vvlo  |
|    |       | band split (threshold>>1, >>2) is NOT from O-GEHL         |
|    |       | (single-threshold there) -- it is local; validate or      |
|    |       | replace; (4) 8x-weighted TAGE term (TD#86) interacts      |
|    |       | with threshold scale. Refs: O-GEHL ISCA 2005 (Seznec);    |
|    |       | Storage-Free Confidence HPCA 2011; TAGE-LSC (Seznec       |
|    |       | 2011 MICRO). Gate any SC die-area commitment on this.     |
| 94 | bp_arb_spec | Reconciled session-057. bp_arb_spec.md rewritten to |
|    |       | the standalone-SC model: cond_pred_* retired, separate SC |
|    |       | UQ, TAGE response buffer as SC PQ, CSR enable. Residual:  |
|    |       | confirm no downstream doc still references cond_pred_* or |
|    |       | a shared SC/TAGE UQ; sections 9/10 reduced to stubs (tb   |
|    |       | reqs move to the implementing task file).                 |
|    |       |                                                           |
|    |       | Session-059 (BP-080): tage.sv still TYPES two live FIFOs  |
|    |       | (uq_data_mem, rb_meta_mem) on the retired cond_pred_*     |
|    |       | wrappers -> tage does not elaborate.                      |
|    |       |                                                           |
|    |       | CLOSED BP-081 (session-060): uq_data_mem/rb_meta_mem      |
|    |       | retyped to tage_upd_inp_t/tage_pred_meta_t, per-subfield  |
|    |       | writes collapsed to whole-struct (dead .sc/.sc_valid/     |
|    |       | .resolved_taken/.cond_mispredict dropped). tage           |
|    |       | elaborates green. No cond_pred_* type remains referenced. |
|    |       |                                                           |
|    |       | Session-061 (INFRA-009/010): section 3.4 (TAGE/SC/ITTAGE  |
|    |       | redirect ports) and section 5.4 (ITTAGE_RESP_BUF_DEPTH)   |
|    |       | annotated -- these describe bp_cluster-level signals not  |
|    |       | present on any current unit-level RTL; the response       |
|    |       | buffer named in 5.4 was removed BP-038b. Clarification,   |
|    |       | not a correction (doc wasn't factually wrong, just         |
|    |       | readable as describing an existing unit port).            |
| 95 | tage  | The tage prediction response structure tage_pred_meta_t   |
|    |       | was changed in bp_structs_pkg. Add support for additions, |
|    |       | remove deletions, reverify tests and planning docs.       |
|    |       |                                                           |
|    |       | CLOSED BP-081 (session-060). tage_high_conf deleted from  |
|    |       | tage_cntrl.sv (write + high_conf_p1 decl/reset/compute);  |
|    |       | 4 tb taps removed (tb_tage_manual.sv +                    |
|    |       | tb_tage_manual_tasks.svh); an additional dead reference   |
|    |       | in tb_tage_tasks.sv removed (authorized out-of-scope --   |
|    |       | it blocked sim_tage_tasks compile; see BUG-006). SC-      |
|    |       | facing fields now GENERATED (not tied off) -- see         |
|    |       | TD#87/#88. All tage targets green this session:           |
|    |       | lint_tage_cntrl/lint_tage/lint_tage_table 0/0;            |
|    |       | sim_tage 105/0; sim_tage_fast 105/0; sim_tage_tasks 0     |
|    |       | fail; sim_tage_manual 3/3; sim_tage_table 15/0. Full bpu  |
|    |       | (make all) exit 0, sim_ittage 211/211 confirmed          |
|    |       | separately; SC targets green as cross-check.              |
| 96 | bpc   | flush operation has scattered mention across documents    |
|    |       | this task will define flush behavior, implement it, and   |
|    |       | update all references to flush operation                  | 
|    |       | this can not be done until bpc is completed               | 
| 97 | bp_arb| To determine is this feature will be implemented          |
|    |       | Future: shared upstream PQ                                |
|    |       |                                                           |
|    |       | A shared upstream PQ broadcasting to all predictor PQs may|
|    |       | be introduced later if the independent PQ approach creates|
|    |       | fan-out or timing problems.  This is deferred.  The per-  |
|    |       | predictor PQ interfaces defined here are compatible with  |
|    |       | being driven from either a shared or independent source.  |
| 98 |sc_cntrl| sc_cntrl shared scalar state under dual-slot update.        |
|    |       | threshold, TC, choose_hi_vlo, choose_med_vvlo, br_imli,     |
|    |       | bb_hist, last_back_pc are scalar (sc_decisions.md s8), one  |
|    |       | copy shared across both prediction slots. sc_decisions.md   |
|    |       | does not define adaptation when both slots carry a valid    |
|    |       | update in the same cycle. Two contention scopes: the        |
|    |       | threshold/TC/chooser counters contend whenever both slots   |
|    |       | update (do_update gate, s10); the BrIMLI registers contend  |
|    |       | only when both slots are resolved-taken backward branches   |
|    |       | (backwards_branch=1 in both sc_upd_inp copies, s12).        |
|    |       | TEMPORARY (BP-077): lowest-indexed valid update slot drives |
|    |       | the shared threshold/TC/chooser/BrIMLI adaptation; per-slot |
|    |       | counter writes proceed independently for every valid slot   |
|    |       | (each slot owns its per-slot table RAM, no write conflict). |
|    |       | Recorded in the sc_cntrl module header.                     |
|    |       | Resolution path: evaluate at PD/perf the benefit of         |
|    |       | (a) duplicating the shared state per slot, (b) sharing with |
|    |       | a defined merge of the two slots' contributions, or         |
|    |       | (c) keeping the single-slot-drives rule. Gate any area/     |
|    |       | correctness commitment on that evaluation. Related: TD#93   |
|    |       | (SC efficacy/threshold tuning), TD#86 (8x TAGE term).       |
| 99 | bpu   | Create a process for PR/CI/CD the pipeline                  |
|    |       | This will be enforced once top level bpu is created         |
|    |       |                                                            |
|    |       | Motivating evidence (session-060, BP-081): `make all`      |
|    |       | silently omits sim_ittage, sim_tage_manual, and the cov_*  |
|    |       | targets. CLAUDE.md already mandates every target run, but   |
|    |       | no single command enforces it. The CI process must run the  |
|    |       | complete target set, not `make all`.                        |
| 100 | tage  | tage line coverage below the previously-stated >90%.       |
|     |       | Session-060 BP-081 measured cov_tage 73.7% (6242/8468),    |
|     |       | cov_tage_table 79.5% (399/502). The TAGE decomposition     |
|     |       | section previously asserted ">90%"; that figure is stale   |
|     |       | vs this run. UNRESOLVED whether the drop is genuine under- |
|     |       | coverage of the new TD#87/#88 decode+extd_ctr logic or a   |
|     |       | coverage-accounting artifact. Review the cov report; add   |
|     |       | directed coverage if the new logic is under-covered, or    |
|     |       | correct the accounting. Gate the ">90%" claim on this.     |
| 101 | ras.sv | declares input ras_pc_p2, unread in the module.       |
|     |        | Undocumented in ras_interfaces.md prior to session-061    |
|     |        | (INFRA-010; doc now documents the port and cites this TD). |
|     |        | Confirm at RAS cleanup whether needed; if not, remove from |
|     |        | ras.sv and tb_ras.sv.                                       |
| 102 | bp_history.sv | does not generate IT5 folds. ittage.sv wires  |
|     |       | it_t5_idx_fh/tag_fh1/tag_fh2 to bp_history.sv outputs that   |
|     |       | are never driven -- permanently 0. IT5 has real history      |
|     |       | (IT_TBL_HIST[5]=32, IT_TBL_FH[5]=9, FH1[5]=9, FH2[5]=8, per  |
|     |       | bp_defines_pkg.sv). Add IT5 fold generation to bp_history.sv |
|     |       | (same pattern as IT1-IT4). Found session-061 (INFRA-010);   |
|     |       | IT5 is NOT BrIMLI -- that framing in bp_history_decisions.md |
|     |       | and bp_cluster.md was a copy-paste error from SC's real      |
|     |       | BrIMLI table (ST4), corrected same session.                  |
| 103 | tage  | tage logic now initializes T0 to 00 (strongly not taken)   \
|     |       | this is not intended, T0 entries should be initialized as  |
|     |       | weakly taken. This impacts how TAGE_SRAM_INIT_VALUE is used|
|     |       | with sram_init. Init value should be b10 (2) weakly taken. |
|     |       | NOTE (session-061): tage_cntrl_decisions.md's T0 init line |
|     |       | was corrected this session to describe the CURRENT (00)    |
|     |       | behavior, matching TAGE_SRAM_INIT_VALUE=0 as it stands      |
|     |       | today -- this is documenting the bug this TD tracks, not    |
|     |       | resolving it. When this TD closes (RTL and/or               |
|     |       | TAGE_SRAM_INIT_VALUE changed to 2), update                  |
|     |       | tage_cntrl_decisions.md's T0 init line again.               |
| 104 | ftb   | Two stale RTL header comments found during the session-061  |
|     |       | planning-doc audit (INFRA-008). Not doc errors -- the docs   |
|     |       | and actual behavior are correct; only the comments in the   |
|     |       | RTL are stale. Comment-only, no behavior change:             |
|     |       |   - ftb_cntrl.sv (~line 163): header comment says "Private   |
|     |       |     RAM entry layout (107 bits/way)". Actual struct/package  |
|     |       |     value is 105 bits (FTB_RAM_ENTRY_WIDTH). 107 predates    |
|     |       |     the session-053 always_taken removal.                    |
|     |       |   - ftb.sv (~lines 33-35, 80-82): comment states             |
|     |       |     ftb_fastpath_en is "a top port beyond the current        |
|     |       |     ftb_interfaces.md draft". Stale -- ftb_interfaces.md 2.4 |
|     |       |     lists it as a documented top input (renamed from         |
|     |       |     chicken_bit_enable, session-053). Only the "source TBD"  |
|     |       |     clause in the comment is still accurate.                 |

| 105 |loop_pred| loop_pred dual-slot retrofit. loop_pred.sv is single-slot; |
|     |         | modify loop_pred to support dual prediction modify         |
|     |         | RTL, test cases, testbenches. |
|     |         | rename pred_p0 to pred_p1     |
|     |         | correct loop_pred_interfaces.md to match RTL |


on. fe_decisions.md 2.1 and ftq_bpu_interfaces.md
describe both LP and uBTB presenting NUM_PRED_SLOTS predictions per cycle.
Retrofit loop_pred to dual prediction: slot dimension on pred_pc_p0,
pred_valid_p0, pred_p0, upd_p0, upd_valid_p0, and the internal tables per TI6.
Touches loop_pred.sv, tb_loop_pred.sv, and loop_pred_interfaces.md. Fold in the
pred_p0 to pred_p1 rename while the testbenches are already being touched.
Found INFRA-011 / session-063.|     |       | comment-cleanup task if none is
scheduled soon.               |

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
| G7  | SC threshold value                    | REFRAMED session-056,  |
|     |                                       | values corrected 057.  |
|     |                                       | Threshold is DYNAMIC   |
|     |                                       | (O-GEHL), not a single |
|     |                                       | fixed value. Seed      |
|     |                                       | SC_THRSH_MID=10        |
|     |                                       | (Seznec: ~num_tables), |
|     |                                       | SC_THRSH_MAX=512,      |
|     |                                       | SC_THRSH_BITS=10,      |
|     |                                       | SC_TC_BITS=7; bounds   |
|     |                                       | SC_THRSH_MIN, adapts   |
|     |                                       | via TC counter. Tuning |
|     |                                       | deferred TD#93.        |
|     |                                       | sc_decisions.md s9/s10.|
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
| G14 | Confidence counter purpose            | Reserved, 4b. SC       |
|     |                                       | (session-056) uses its |
|     |                                       | own chooser counters;  |
|     |                                       | does not consume this  |
|     |                                       | field.                 |
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
- ITTAGE overrides FTB target at s2 for indirect branches
  (including indirect CALL -- see indirect-CALL ownership note,
  session-061, top of file). RAS overrides FTB target at s2 for
  returns and separately pushes the return address on indirect/
  direct CALL for its own stack bookkeeping.
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
  (session-055). ITTAGE IT5 has real folded history (FH=9b,
  FH1=9b, FH2=8b, hist=32b) -- it is NOT a BrIMLI table; that
  framing was a copy-paste error corrected session-061. RTL
  generation of the IT5 fold in bp_history.sv is TD#102, open.
- TAGE entry: T0 2b CTR only, T1-T4 valid+tag+CTR+useful.
  T0 init value under review, TD#103 open (RTL currently
  initializes 00/strongly-not-taken; TD#103 argues for
  10/weakly-taken).
- ITTAGE entry: IT1-IT5 valid+tag+EPC+USE+CTR(3b)+TGT(38b).
  No IT0 base table. CTR is confidence not direction.
  Target written on misprediction when CTR is null only.
- SC index: sc_upd_idx[0:SC_NUM_TABLES-1] uniform 5-entry
  array (ST4/BrIMLI index folded into the array; the earlier
  sc_imli_idx split retired session-056). sc_upd_ctr likewise
  a uniform 5-entry array.
- SC has no tag bits. All 5 tables are pure counter arrays.
  BrIMLI table (ST4) is SC only -- not ITTAGE.
- SC threshold dynamic (O-GEHL); two-corner chooser
  (TAGE-hi/SC-vlo, TAGE-med/SC-vvlo) with separate saturating
  counters. SC counter-update gate: SC-wrong OR |sum| <
  threshold, train toward resolved. BrIMLI (ST4) per cookbook
  predictor.h. See planning/arch/sc_decisions.md (session-057,
  draft).
- SC arbitration: single-port RAM predict-vs-update contention
  via the section 4.5 credit arbiter; SC has no independent
  prediction FIFO (TAGE response buffer is SC's PQ); separate
  SC update queue -- currently STUBBED at the unit level
  (sc_uq_not_full tied 1, sc_upd_rdy tied all-ones), real
  arbiter deferred to bp_cluster (TD#73/#94); CSR sc_enable
  gates SC participation. See planning/arch/bp_arb_spec.md
  (session-057).
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
  SC follows TI6 (two RAMs per table, one per slot).
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
- SC br_imli_mode is a COMPILE-TIME MODULE PARAMETER
  (sc_brimli BR_IMLI_MODE, default IDX_IMLI_PHR; propagated
  from sc.sv SC_BR_IMLI_MODE), not a runtime port. bp_cluster
  sets it at the sc.sv instantiation for a non-default perf
  build. (session-059, BP-079.)
- TAGE confidence outputs GENERATED (session-060, BP-081):
  tage_pred_strong = provider CTR in {000,111}; tage_pred_weak
  = {011,100}; tage_pred_medium = the remainder; one-hot on
  the post-mux provider CTR (TD#87). tage_extd_ctr = signed
  ({2'b00, provider_ctr, 1'b0}) - 5'sd7 (TD#88). strong is
  now STRICTLY {000,111} (previously NOT WEAK); the UAON
  update gate keys on tage_pred_weak to preserve behavior.

### Shared planning documents
    - planning/arch/bp_arb_spec.md                    In progress
        - Dynamic prediction/training arbitration balancing
        - RECONCILED session-057: the merged TAGE+SC metadata /
          shared-UQ model is retired. SC uses its own
          sc_pred_meta_t / sc_upd_inp_t (cond_pred_meta_t and
          cond_pred_upd_inp_t commented out). arb_spec rewritten
          to the standalone-SC model (separate SC UQ, TAGE
          response buffer as SC PQ, CSR enable). TD#94 CLOSED
          BP-081 (tage FIFOs retyped; no cond_pred_* remains).
          Session-061: sections 3.4/5.4 annotated as describing
          bp_cluster-level signals, not current unit ports.
    - planning/arch/bp_cluster.md                     In progress
        - Branch prediction cluster summary data. Session-061
          (INFRA-010): indirect-CALL ownership and ITTAGE IT5
          BrIMLI/no-folds claim corrected -- see top of file.
    - planning/arch/ras_decisions.md                  Draft
        - RAS micro-architectural decisions (session-050;
          p-naming session-057). Session-061: RAS_COMMIT_PTR_
          WIDTH -> RAS_COMMIT_PTR_BITS corrected.
    - planning/arch/sram_init.md                      Complete
        - Post reset RAM initialization operation
    - planning/testbenches/manual_tb_decisions.md     Complete
        - General rules for manual testbench creation

### Session-061 planning document audit (INFRA-008/009/010)

Read-only audit of the FTB, TAGE/SC, and ITTAGE/RAS planning
documents against shipped RTL/tb/Makefile, run ahead of bp_cluster
top-level design so the docs can be trusted as interface authority
when the cluster instantiates all seven predictors at once.

  - INFRA-008 (ftb): clean. Two stale RTL comments noted, tracked
    TD#104 (comment-only, not fixed this session).
  - INFRA-009 (tage, sc): 12 findings, all doc drift, all fixed this
    session. See per-file notes in Module Status above.
  - INFRA-010 (ittage, ras): 10 findings. 8 doc drift, fixed. 2 real
    design/RTL gaps, each resolved by a Jeff ruling with the doc
    fixed this session and the RTL-side gap opened as a TD:
    indirect-CALL ownership (ITTAGE predicts target + RAS pushes
    return address, both in scope) and ITTAGE IT5 (real folded
    history, NOT BrIMLI -- TD#102 tracks the missing bp_history.sv
    fold generation).

New TDs from this session: #101 (ras_pc_p2 dead/undocumented port),
#102 (IT5 fold generation missing), #104 (FTB stale RTL comments).

Open conflict surfaced (not created) this session: TD#103 (tage T0
init value) vs. the tage_cntrl_decisions.md correction made during
INFRA-009 -- see the note at the top of this file. The doc now
describes current (00) RTL behavior; TD#103 argues that behavior is
wrong. Not contradictory once read together, but flagged so the next
reader doesn't mistake the doc correction for a resolution of TD#103.

### TAGE decomposition
- Session-060 (BP-081): tage RECONCILED and GREEN. The retired
  cond_pred_* FIFO element types (TD#94) were retyped to
  tage_upd_inp_t/tage_pred_meta_t; dead tage_high_conf deleted
  (TD#95); TD#87 strong/medium/weak decode and TD#88 tage_extd_ctr
  GENERATED on the post-mux provider CTR (no longer tie-off);
  tage_pred_weak re-added to the package; UAON gate moved to
  tage_pred_weak (behavior-preserving). tage elaborates, all tage
  targets green this session (sim_tage 105/0).
- Session-061: planning docs (tage_interfaces.md,
  tage_cntrl_decisions.md) reconciled to the TD#87/#88 decode and
  T0 index/init corrections. See INFRA-009 note above. TD#103 open
  on T0 init value -- see conflict note at top of file.
- RTL is available
    - Unit testbenches written
    - Manual testbench written
    - Line coverage: cov_tage 73.7% / cov_tage_table 79.5%
      (session-060). NOTE: previously stated ">90%"; that claim is
      stale vs the BP-081 run. TD#100 tracks whether the new
      TD#87/#88 logic is under-covered or the accounting drifted.
    - Directed validation complete
    - remaining items deferred
        - #69 rollback -> bp_cluster
        - #67 sram_init non-fast
        - #74 dual-slot (bp_history part closed BP-072;
          TAGE/cluster dual-slot still deferred)
        - #100 coverage review (cov_tage vs prior >90% claim)
        - #103 T0 init value (open, session-061 flagged conflict
          with the planning-doc correction -- see top of file)
    - #87/#88 SC-facing signals (tage_pred_strong/medium/weak,
      tage_extd_ctr): CLOSED BP-081 -- generated for real in TAGE.
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
- BP-081: struct reconciliation + TD#87/#88 generation
    - cond_pred_* FIFO retype (TD#94), tage_high_conf delete
      (TD#95), strong/medium/weak decode (TD#87), tage_extd_ctr
      (TD#88), pred_conf_decode_tst coverage, UAON gate on
      tage_pred_weak, uaon_update_rules.md doc reconciliation.
- Tage planning documents
    - planning/arch/tage_cntrl_alloc_rules.md         Complete
        - Table entry allocation rules
    - planning/arch/tage_cntrl_ctr_update_rules.md    Complete
        - CTR field update rules
    - planning/arch/tage_cntrl_decisions.md           Complete
        - TAGE control behavior, conventions and rules. Session-061:
          T0 index/init and CTR-update summary corrections -- see
          Module Status.
    - planning/arch/tage_cntrl_uaon_update_rules.md   Complete
        - UAON (Use ALT on newly allocated)  trigger rules.
          Reconciled to TD#87 session-060 (gate on tage_pred_weak;
          strong = strictly {000,111}).
    - planning/arch/tage_cntrl_use_update_rules.md    Complete
        - USE(ful) field update rules. Corrected session-045.
    - planning/arch/tage_table_hash_rules.md          Complete
        - Address and tag generation hashing. Consumes folds
          per bp_history_decisions.md s6 (computation there).
    - planning/arch/tage_table_entry_formats.md       Complete
        - Central specification of table entry fields and ordering
    - planning/interfaces/tage_interfaces.md          Complete
        - TAGE module interface contracts. Session-061: strong/
          medium/weak/extd_ctr corrections -- see Module Status.
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
        - #102 IT5 fold generation missing in bp_history.sv (new,
          session-061)
    - Formal validation not started
- BP-034 - BP-042 complete (BP-033 abandoned)
- Session-061 (INFRA-010): indirect-CALL ownership and IT5 BrIMLI/
  no-folds claim corrected across ittage_interfaces.md,
  bp_history_decisions.md, bp_cluster.md; ittage_cntrl_alloc_rules.md
  write-data field order corrected; ittage_table_interfaces.md
  tgt_wr_u0 split and "4 total writes" claim corrected;
  ittage_table_entry_formats.md TAG width param corrected. See
  Module Status for per-file detail.
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
        - RAS module interface contracts. Session-061: ras_pc_p2
          port added (was undocumented; TD#101).
- RTL available:
    - rtl/ras.sv                   complete (BP-062)
    - tb/tb_ras.sv                 complete (BP-063)
    - sim_ras 87/0 (BP-064 this session)
    - TD #78 pinned (tb_ras TC-21), TD #79 (commit_rctr)
      deferred -- see PROJECT_STATUS Technical Debt.
    - TD #101 open (ras_pc_p2 declared, unread; session-061)
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
- SC-facing additions deferred (session-056; revised session-057):
  FTB stores branch PC[15:6] (TD#89, supplied to sc_upd_inp.branch_
  range) and the per-slot backwards-branch sign (TD#90, supplied to
  sc_upd_inp.backwards_branch) for SC BrIMLI maintenance.
- Session-061 (INFRA-008): audit clean, no doc-vs-RTL discrepancy.
  Two stale RTL header comments found (107 bits/way in ftb_cntrl.sv;
  fastpath_en "beyond interface draft" in ftb.sv) -- tracked TD#104,
  not fixed this session (comment-only, deferred to next FTB touch).
- FTB planning documents
    - planning/arch/ftb_decisions.md                   Complete
        - FTB micro-architectural decisions (canonical authority)
    - planning/interfaces/ftb_interfaces.md            Complete
        - FTB module interface contracts
    - planning/arch/ftb_confidence_override_rules.md   Complete
        - conf bimodal direction + saturated-endpoint fast-path policy

### SC decomposition
- Planning COMPLETE and RTL COMPLETE at unit level (session-058/059).
  sc_decisions.md and bp_arb_spec.md at rest and consistent with the
  packages. The SC unit (tables + control + structural top) is written
  and green; remaining unit item is sc_coverage_plan.md.
    - planning/arch/sc_decisions.md                   Draft
        - Five pure-counter tables ST0-ST4, no tags. ST4 = BrIMLI.
        - SC index: sc_upd_idx[0:SC_NUM_TABLES-1] uniform 5-entry
          array (sc_imli_idx split retired). ST0 unhashed PC slice;
          ST1-ST3 PC hashed with folds (bp_history_decisions.md s6);
          ST4 BrIMLI index.
        - Dynamic threshold (O-GEHL). SC_THRSH_MID=10 seed (corrected
          session-057 from 2048), SC_THRSH_MAX=512, SC_TC_BITS=7. TC
          adaptation. References: O-GEHL (ISCA 2005), Storage-Free
          Confidence (HPCA 2011).
        - Two-corner chooser (TAGE-hi/SC-vlo, TAGE-med/SC-vvlo),
          separate saturating counters (choose_hi_vlo,
          choose_med_vvlo). vlo/vvlo band split is local, not O-GEHL
          (tuning deferred TD#93).
        - SC counter-update gate: (SC-wrong) OR (|sum| < threshold),
          train toward resolved. Verified vs gem5 SC source,
          Jimenez-Lin perceptron paper (TOCS 2002), Seznec 2011
          MICRO; BrIMLI from cookbook predictor.h.
        - Prediction phase counter capture fixed session-057: ctr
          read signed, value*=(ctr<<<1)+1 local to sum, raw ctr
          captured; sc_override captured. pc_range removed; BrIMLI
          reads sc_upd_inp.branch_range / backwards_branch.
        - BrIMLI register/update/index defined (last_back_pc[15:6]
          region, br_imli saturating count, bb_hist on region
          change, f_brimli = (br_imli==0)?phr:br_imli, index =
          pc ^ f_idx ^ (pc>>4)).
        - Session-059 (s12): br_imli_mode is a COMPILE-TIME MODULE
          PARAMETER (sc_brimli BR_IMLI_MODE, propagated from sc.sv
          SC_BR_IMLI_MODE), not a runtime port. Default IDX_IMLI_PHR.
          Implemented BP-079.
    - planning/interfaces/sc_interfaces.md            Written (058)
        - SC top-level ports. ST4 PC width resolved to inp_pc_p2[15:6]
          (IC-SC-03). br_imli_mode later made a parameter (059), no
          longer a port. Session-061: Arbitration Model section
          corrected (SC UQ is stubbed at unit level, not functional).
    - planning/arch/sc_table_hash_rules.md            Written (058)
        - sc_idx_hash (ST0-ST3), get_br_imli_idx (ST4). Session-061:
          br_imli_mode parameter status corrected.
    - planning/interfaces/sc_table_interfaces.md      Written (058)
        - sc_table (ST0-ST3), sc_brimli (ST4). Counter-only entry.
          Session-061: br_imli_mode parameter status corrected.
    - planning/testbenches/sc_tb_decisions.md         Written (058)
        - Unit-tb conventions (SC_FAST_INIT, mem[b][i] paths).
          Session-061: ST0 tb-coverage claim corrected (no ST0
          instance exists; coverage gap noted, no TD).
    - planning/arch/sc_cntrl_ctr_update_rules.md      NOT WRITTEN
        - Optional; write at coverage/tb time citing sc_decisions s10.
    - verification/sc_coverage_plan.md                NOT WRITTEN
        - Remaining SC unit item.
    - DROPPED session-057 (do not write):
      sc_cntrl_decisions.md (no content independent of sc_decisions
      s8-s10); sc_table_entry_formats.md (SC entry is a single signed
      counter).
    - sram_init.md: shared standalone file; SC fast-init inline in
      sc_decisions s13. Session-061: SC moved from "future consumer"
      to confirmed consumer; plusarg name corrected +TAGE_FAST_INIT
      -> +SC_FAST_INIT.
- RTL COMPLETE at unit level (BP-075 through BP-079):
    - rtl/core/frontend/bpu/rtl/sc_table.sv    ST0-ST3 (BP-075/075a)
    - rtl/core/frontend/bpu/rtl/sc_brimli.sv   ST4 BrIMLI (BP-076)
    - rtl/core/frontend/bpu/rtl/sc_cntrl.sv    control (BP-077)
    - rtl/core/frontend/bpu/rtl/sc.sv          structural top (BP-078)
    - tb: tb_sc_table / tb_sc_brimli / tb_sc_cntrl / tb_sc
    - Green: sim_sc 55/0, sim_sc_fast 52/0, sim_sc_cntrl 98/0,
      sim_sc_table 6/0 (+fast), sim_sc_brimli 7/0 (+fast); all lints
      0/0. Default-mode equivalence held across BP-079.
    - sc.sv notes: 9b ST0-ST3 index buses adapted to the 10b
      SC_MAX_IDX_WIDTH controller buses (zero-extend up / slice down);
      one sram_init sized to ST4 (1024x6); arb-status ports stubbed
      (sc_uq_not_full=1; SC UQ / credit arbiter deferred to bp_cluster
      TD#73/#94); -Wno-SYNCASYNCNET added (sram_init async reset).
    - BP-079: br_imli_mode runtime port -> compile-time parameter
      across sc_brimli / sc_cntrl / sc.sv; tb_sc_brimli covers all
      three modes via parameter-override instances.
- Package changes (session-056; corrected session-057):
    - bp_defines_pkg.sv: SC params (SC_NUM_TABLES=5; dynamic
      threshold SC_THRSH_BITS=10/MIN/MID=10/MAX=512; SC_TC_BITS=7;
      SC_LSUM_BITS; SC_CHOOSER_*; SC_CTR_MIN/MAX; SC_LO/HI_THRESHOLD,
      SC_NUM_ALL_TBLS, SC_IMLI_INDEX_BITS removed). SC arb params:
      SC_UQ_DEPTH, SC_UQ_WR_PORTS, SC_RESP_BUF_DEPTH, SC_PRED_CREDITS,
      SC_UPD_CREDITS, SC_STARVE_THRESH; no SC_PQ_DEPTH.
    - bp_structs_pkg.sv: sc_pred_meta_t, sc_upd_inp_t populated;
      pc_range removed, captured_phr commented out (session-057);
      bp_sc_meta_t and cond_pred_meta_t/cond_pred_upd_inp_t commented
      out; bp_sc_chooser_e and br_imli_mode_e added; tage_pred_meta_t
      gains tage_extd_ctr. Session-058: sc_pred_meta_t.sc_upd_idx /
      sc_upd_ctr converted to packed 2D arrays. Session-060 (BP-081):
      tage_pred_weak re-added; provider_ctr stays internal (not a
      field); tage_high_conf confirmed absent.
- Prerequisites for cluster integration (TD; not sc.sv unit work):
    - #87 (tage_pred_medium/strong/weak) and #88 (tage_extd_ctr):
      CLOSED BP-081 -- SC prediction sum and chooser now have real
      generated values from TAGE (were interim tie-off; superseded).
    - #89 / #90 (FTB stores branch PC[15:6] and per-slot backwards
      sign).
    - #91 (route PC p0->p2 to SC), #92 (capture phr[9:0] -> sc_phr_p2).
    - #84 end-to-end fold check extends to SC ST1-ST3 consumers.
- RTL: COMPLETE at unit level; sc_coverage_plan.md remaining.

### bp_history decomposition
- COMPLETE at unit level (session-055). Module-owned pointer,
  corrected/increment-oriented fold geometry, canonical fold
  definition captured natively, suite green.
- Session-061 (INFRA-010): incorrect "IT5 is BrIMLI, no folds" claim
  removed from bp_history_decisions.md sections 1 and 8, and from
  bp_cluster.md. IT5 has real folded history (FH=9b, FH1=9b, FH2=8b,
  hist=32b per bp_defines_pkg.sv, which was already correct). RTL gap
  (bp_history.sv does not generate the IT5 fold it's wired to in
  ittage.sv) opened as TD#102.
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
        - Session-061: IT5 BrIMLI/no-folds claim corrected -- IT5
          is a real folded-history table.
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
        - TD#102 open: IT5 fold generation missing (session-061).
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
      (now also covers SC ST1-ST3 consumers)
    - #69/#70 rollback stimulus -> bp_cluster
    - #102 IT5 fold generation missing (new, session-061)
    - versions/bp_history.sv (stale BP-069 copy) superseded by the
      merged rtl/ file; retire it (BUG-005)

### Shared components track
- components/rtl  components/tb

