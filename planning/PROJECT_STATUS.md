<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Project Status -- RISC-V RVA23 Processor Co-Design
```
 FILE:    PROJECT_STATUS.md
 SOURCE:  various
 STATUS:  WORKING
 UPDATED: 2026-08-08 (pa session 063)
 CONTACT: Jeff Nye
```

Updated every session. Paste into Claude.ai at session start,
along with the latest session_handoff-NNN.md and CLAUDE.md.

Paste PROJECT_CORE.md only when methodology is under discussion.

---

## Session-063: bp_cluster built. BPU green, cluster unverified.

bp_cluster.sv now instantiates all eight modules (seven predictors
plus bp_history), wires p0 through p3, and carries the full
prediction and update behaviour. All 45 bpu Makefile targets pass:
18 lint, 21 sim, 6 cov.

NOTHING IN bp_cluster HAS EVER BEEN SIMULATED. There is no
tb_bp_cluster and no sim target for it. lint_bp_cluster is the only
target that touches the module. Every claim about cluster behaviour
comes from reading RTL and from elaboration, not from a run. This is
the largest verification gap in the unit and it is the next session's
work.

Tasks run: INFRA-011 (port inventory), BP-082 (package dual-slot
entry, found already applied), BP-083 (tb_bp_pkg retrofit), BP-084
(cluster structural top), BP-085 (cluster behavioural), BP-086 (uBTB
block-descriptor rewrite), BP-090 (cluster rewire + metadata ports +
tb and comment closure).

BP-087, BP-088 and BP-089 were ABANDONED, all three for incomplete
specification by the PA. None of their RTL reached the tree. BP-090
was written against the tree state and closed the work in one run.
See session_handoff-064.md postmortem.

New planning documents:
  planning/interfaces/bpu_port_inventory.md   (INFRA-011)
  planning/interfaces/ftq_bpu_interfaces.md   FTQ/BPU port spec
  planning/interfaces/ubtb_interfaces.md      rewritten

New TDs: #105 (loop_pred dual-slot retrofit).
CLOSED: #91, #92 (SC PC and phr staged p0->p2 in bp_cluster).

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

New TDs opened session-061: #101 (ras.sv ras_pc_p2 dead/undocumented
port), #102 (bp_history.sv missing IT5 fold generation), #104 (two
stale RTL comments found during INFRA-008, see Technical Debt table).

CONFLICT TO RESOLVE: TD#103 (added by Jeff, tage T0 init value) states
T0 should initialize to weakly-taken (2'b10) and that the current
00 (strongly-not-taken) init is a bug. INFRA-009 that same session
corrected tage_cntrl_decisions.md's T0 init description FROM "10" TO
"00" -- that correction was made to match CURRENT RTL/package behavior
(TAGE_SRAM_INIT_VALUE=0 in bp_defines_pkg.sv), not to assert 00 is the
intended value. The doc now accurately describes what the RTL does
today, which TD#103 says is wrong. When TD#103 is resolved (RTL and/or
TAGE_SRAM_INIT_VALUE changed to 2), tage_cntrl_decisions.md's T0 init
line must be updated again to match. Do not treat the session-061 doc
correction as having settled the "what should T0 init to" question --
it only documented current behavior.

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
|                         |             |                   | SESSION-063: uBTB block params   |
|                         |             |                   | added and MOVED below the FTB    |
|                         |             |                   | section (they derive from the    |
|                         |             |                   | FTB values): UBTB_BLOCK_BYTES,   |
|                         |             |                   | UBTB_OFFSET_BITS,                |
|                         |             |                   | UBTB_BR_POS_BITS,                |
|                         |             |                   | UBTB_PFTADDR_BITS,               |
|                         |             |                   | UBTB_BR_TGT_BITS,                |
|                         |             |                   | UBTB_JMP_TGT_BITS,               |
|                         |             |                   | UBTB_CONF_WIDTH, INIT_TKN/NTK,   |
|                         |             |                   | UBTB_ENTRY_WIDTH=100,            |
|                         |             |                   | UBTB_SET_WIDTH=400. Index/tag    |
|                         |             |                   | comment corrected off PC[26:7]   |
|                         |             |                   | to block granularity (BP-090).   |
| bp_structs_pkg.sv       | Complete    | tb_bp_pkg         | TAGE and ITTAGE structs complete.|
|                         |             |                   | IT5 fold fields present in       |
|                         |             |                   | struct (II1); generation gap in  |
|                         |             |                   | bp_history.sv tracked TD#102.    |
|                         |             |                   | SC structs session-056/057/058.  |
|                         |             |                   | Session-060 BP-081: tage_pred_   |
|                         |             |                   | weak re-added; tage_high_conf/   |
|                         |             |                   | tage_provider_ctr absent.        |
|                         |             |                   | SESSION-063:                     |
|                         |             |                   | bp_ftq_entry_t split into block- |
|                         |             |                   | scalar fields plus a per-slot    |
|                         |             |                   | bp_ftq_slot_t[NUM_PRED_SLOTS-1:0]|
|                         |             |                   | array (BP-082, commit 2b60115).  |
|                         |             |                   | bp_ftq_slot_t gains pos          |
|                         |             |                   | (FTB_BR_POS_BITS) for the        |
|                         |             |                   | in-block branch position.        |
|                         |             |                   | ftb_pred_meta_t added (hit, way, |
|                         |             |                   | jmp_pos); bp_ftq_meta_t gains an |
|                         |             |                   | ftb member so the FTB carried    |
|                         |             |                   | writeWay travels in the struct.  |
|                         |             |                   | bp_redirect_t: ftq_idx removed   |
|                         |             |                   | (scalar at the port beside the   |
|                         |             |                   | per-slot array); s2/s3 comments  |
|                         |             |                   | to p2/p3.                        |
|                         |             |                   | uBTB types reshaped to the FTB   |
|                         |             |                   | entry form: ubtb_cond_t (22b),   |
|                         |             |                   | ubtb_jmp_t (30b), ubtb_entry_t   |
|                         |             |                   | (100b), ubtb_blk_t new,          |
|                         |             |                   | ubtb_pred_t gains pos and conf,  |
|                         |             |                   | ubtb_upd_t reshaped to mirror    |
|                         |             |                   | the FTB update port (13 fields;  |
|                         |             |                   | br_type and carry REMOVED).      |
|                         |             |                   | branch_id comments corrected to  |
|                         |             |                   | "FTQ entry index" (TD-FE-5);     |
|                         |             |                   | bp_pred_src_e stage labels to    |
|                         |             |                   | p1/p2/p3.                        |
| bp_pkg.sv               | Deprecated  | --                | Deleted.                         |
| bp_history.sv           | Complete    | tb_bp_history     | Module-owned pointer (BP-069).   |
|                         |             |                   | Fold geometry corrected (BP-071);|
|                         |             |                   | increment-oriented walk +        |
|                         |             |                   | post-advance ckpt (BP-072).      |
|                         |             |                   | Dual-slot fold equivalence proven|
|                         |             |                   | in-sim (TD #74, BP-072): 16 TCs, |
|                         |             |                   | 19224 golden comparisons.        |
|                         |             |                   | External fold anchor TC14-16     |
|                         |             |                   | (BP-073). Canonical fold def in  |
|                         |             |                   | decisions.md s6; doc-RTL         |
|                         |             |                   | verified (BP-074).               |
|                         |             |                   | See BUG-004 / BUG-005.           |
|                         |             |                   | Session-061 (INFRA-010): IT5     |
|                         |             |                   | fold generation MISSING. TD#102. |
|                         |             |                   | Session-063: driven from the     |
|                         |             |                   | cluster's formed p1 prediction;  |
|                         |             |                   | pred_taken/pred_pc compacted by  |
|                         |             |                   | branch number, not slot number.  |
| bp_history_decisions.md | Draft       | --                | Created session-054. Resolves    |
|                         |             |                   | G20/G21/G22. s6 canonical Fold   |
|                         |             |                   | Definition (session-055). s7     |
|                         |             |                   | checkpoint POST-advance.         |
|                         |             |                   | Session-061: IT5 BrIMLI/no-folds |
|                         |             |                   | claim removed. Header still      |
|                         |             |                   | DRAFT pending s6.6 sha + HI2/HI5.|
| bp_history_interfaces.md| Draft       | --                | Rewritten session-054. Checkpoint|
|                         |             |                   | Timing consistent with s7        |
|                         |             |                   | (BP-074).                        |
| ubtb.sv                 | Complete    | tb_ubtb           | SESSION-063 BP-086: REWRITTEN to |
|                         |             | sim_ubtb          | the single-lookup block          |
|                         |             |                   | descriptor model. One index, one |
|                         |             |                   | tag, one way search from         |
|                         |             |                   | pred_pc_p0; the matched entry    |
|                         |             |                   | supplies every slot. The         |
|                         |             |                   | pred_pc_p0 + 32 slot-1 lookup is |
|                         |             |                   | GONE. New blk_p1 output          |
|                         |             |                   | (ubtb_blk_t): entry hit and      |
|                         |             |                   | reconstructed fall-through.      |
|                         |             |                   | Target encode/reconstruct,       |
|                         |             |                   | fall-through reduce/reconstruct  |
|                         |             |                   | and the bimodal step ported from |
|                         |             |                   | ftb_cntrl against UBTB widths.   |
|                         |             |                   | Round-robin replacement and the  |
|                         |             |                   | single array retained.           |
|                         |             |                   | sim_ubtb 259/0, cov_ubtb 98.6%.  |
|                         |             |                   | Mutation tested, 5 injected      |
|                         |             |                   | defects, all caught.             |
|                         |             |                   | CLI-012 port naming retrofit now |
|                         |             |                   | reflected in the doc.            |
| ubtb_interfaces.md      | Draft       | --                | SESSION-063: REWRITTEN for the   |
|                         |             |                   | single-lookup model. UI1 closed  |
|                         |             |                   | (pred_pc+32 retired). UI4 closed |
|                         |             |                   | (a hit with no valid slot is the |
|                         |             |                   | no-branch state; successor is    |
|                         |             |                   | blk_p1.pft_addr; no sentinel).   |
|                         |             |                   | Port names carry stage suffixes. |
|                         |             |                   | UI2 (carry consumer) and UI3     |
|                         |             |                   | (both channels one entry) remain.|
| loop_pred.sv            | Complete    | tb_loop_pred      | BP-004c-f complete.              |
|                         |             |                   | SINGLE SLOT. Dual-slot retrofit  |
|                         |             |                   | and the pred_p0 -> pred_p1       |
|                         |             |                   | rename are TD#105 (session-063). |
|                         |             |                   | Port naming retrofit pending     |
|                         |             |                   | (CLI-011)                        |
| tage_interfaces.md      | Complete    | --                | session-036: 6 corrections.      |
|                         |             |                   | Session-061 (INFRA-009): strong/ |
|                         |             |                   | medium/weak and extd_ctr         |
|                         |             |                   | corrections.                     |
| tage_table_interfaces.md| Draft       | --                | Created session-016.             |
|                         |             |                   | Updates pending.                 |
| tage_cntrl_use          | Complete    | --                | session-037/045.                 |
| _update_rules.md        |             |                   |                                  |
| tage_cntrl_uaon         | Complete    | --                | Session-060: reconciled to TD#87 |
| _update_rules.md        |             |                   | (UAON gate on tage_pred_weak).   |
| tage_cntrl              | Complete    | --                | session-044/045.                 |
| _ctr_update_rules.md    |             |                   |                                  |
| tage_cntrl_decisions.md | Complete    | --                | Session-061 (INFRA-009): T0 RAM  |
|                         |             |                   | index pc[11:1] -> pc[12:2]; T0   |
|                         |             |                   | init corrected to 00 to MATCH    |
|                         |             |                   | CURRENT RTL (see TD#103 conflict,|
|                         |             |                   | top of file).                    |
| bw_ram / sat_alu        | Complete    | tb_components     | COMP-001 PASS                    |
| dual_lm1                | Complete    | tb_components     | COMP-002 now uses generate       |
| sram_init               | Complete    | tb_components     | COMP-003                         |
| tage_hash.sv            | Complete    | tb_tage_hash      | BP-006 abandoned.                |
| tage_table.sv           | Complete    | tb_tage_table     | BP-007 through BP-012 complete.  |
|                         |             |                   | Signal naming debt #17 pending.  |
| tage_bim.sv             | Complete    | --                | BP-009b complete.                |
| tage_cntrl.sv           | Complete    | --                | BP-008a/b, BP-012, BP-045.       |
|                         |             |                   | BUG-003 fixed BP-057.            |
|                         |             |                   | Session-060 BP-081: TD#87 decode |
|                         |             |                   | + TD#88 extd_ctr generated.      |
|                         |             |                   | TD#103 OPEN: T0 init value.      |
| tage.sv                 | Complete    | tb_tage           | BP-056 through BP-061 complete.  |
|                         |             |                   | Session-060 BP-081: FIFOs retyped|
|                         |             |                   | off cond_pred_*.                 |
|                         |             |                   | sim_tage 105/0, sim_tage_fast    |
|                         |             |                   | 105/0.                           |
| tage_assert.sv          | Complete    | sim_tage          | ADR-001 and row 18 assertions.   |
|                         |             | sim_tage_fast     | sim_tage 105 tests as of BP-081. |
| ittage_assert.sv        | Complete    | sim_ittage        | New session-045.                 |
| tb_tage_manual.sv       | Complete    | sim_tage_manual   | ctr rows 1-17, use rows 1-6.     |
|                         |             |                   | sim_tage_manual 3/3.             |
| ittage_interfaces.md    | Draft       | --                | Session-061 (INFRA-010):         |
|                         |             |                   | indirect-CALL ownership and IT5  |
|                         |             |                   | corrections.                     |
| ittage_table_interfaces.md| Draft     | --                | Session-061 (INFRA-010): "4 total|
|                         |             |                   | writes" and tgt_wr_u0 split      |
|                         |             |                   | corrections.                     |
| ittage_cntrl_alloc_rules.md| Complete | --                | Session-061: write-data field    |
|                         |             |                   | order corrected.                 |
| ittage_cntrl_ctr_update_rules.md| Complete| --           | session-045: 33-row table.       |
| ittage_cntrl_decisions.md| Complete   | --                | session-036/037/038.             |
| ittage_cntrl_uaon_update_rules.md| Complete| --          | Promoted Complete BP-051.        |
| ittage_cntrl_use_update_rules.md| Complete| --           | session-045 corrections.         |
| ittage_table_hash_rules.md| Complete  | --                | Fold CONSUMPTION only.           |
| ittage_table_entry_formats.md| Complete| --               | Session-061: TAG width param     |
|                         |             |                   | corrected.                       |
| ittage_table.sv         | Complete    | tb_ittage_table   | BP-033/033-FIX-1 complete.       |
| ittage_cntrl.sv         | Complete    | tb_ittage_cntrl   | BP-034/035/036/044/048/051-053.  |
|                         |             |                   | 147 tests passing.               |
| ittage.sv               | Complete    | tb_ittage         | sim_ittage 211/0.                |
|                         |             |                   | Session-061: IT5 fold ports wired|
|                         |             |                   | to bp_history outputs never      |
|                         |             |                   | driven (permanently 0). TD#102.  |
| ras_decisions.md        | Draft       | --                | Created session-050. G5/G6/G8/G17|
|                         |             |                   | recorded. Session-061:           |
|                         |             |                   | RAS_COMMIT_PTR_BITS correction.  |
| ras_interfaces.md       | Draft       | --                | Created session-050. Session-061:|
|                         |             |                   | ras_pc_p2 documented (TD#101).   |
| ras.sv                  | Complete    | tb_ras            | RTL BP-062, tb BP-063.           |
|                         |             |                   | sim_ras 87/0.                    |
|                         |             |                   | TD #78 pinned, TD #79 deferred.  |
|                         |             |                   | TD#101 OPEN: ras_pc_p2 declared, |
|                         |             |                   | unread. Session-063: the cluster |
|                         |             |                   | now DRIVES it from the staged p2 |
|                         |             |                   | PC; still unread inside ras.sv.  |
| ftb_decisions.md        | Complete    | --                | Created session-051. Promoted    |
|                         |             |                   | Complete session-053.            |
| ftb_interfaces.md       | Complete    | --                | Created session-052. IC-FTB-12..15|
| ftb_confidence          | Complete    | --                | conf = bimodal direction,        |
| _override_rules.md      |             |                   | fast-path (session-053).         |
| ftb_array.sv            | Complete    | sim_ftb           | 1R1W data RAM, no reset.         |
| ftb_plru.sv             | Complete    | sim_ftb           | entry-valid + tree-PLRU flops.   |
| ftb_cntrl.sv            | Complete    | sim_ftb           | All FTB logic. Stale "107 bits/  |
|                         |             |                   | way" header comment, TD#104.     |
| ftb.sv                  | Complete    | tb_ftb            | Structural top. sim_ftb 99/0.    |
|                         |             | sim_ftb           | Stale fastpath_en comment, TD#104|
| sc_decisions.md         | Draft       | --                | Created session-056. Corrected   |
|                         |             |                   | 057. s12 br_imli_mode parameter  |
|                         |             |                   | (059).                           |
| sc_table.sv             | Complete    | tb_sc_table       | ST0-ST3. sim_sc_table 6/0.       |
| sc_brimli.sv            | Complete    | tb_sc_brimli      | ST4 BrIMLI. sim_sc_brimli 7/0.   |
| sc_cntrl.sv             | Complete    | tb_sc_cntrl       | sim_sc_cntrl 98/0.               |
| sc.sv                   | Complete    | tb_sc             | sim_sc 55/0, sim_sc_fast 52/0.   |
|                         |             |                   | Arb ports stubbed at unit level; |
|                         |             |                   | the real credit arbiter now lives|
|                         |             |                   | in bp_cluster (session-063).     |
| sc_interfaces.md        | Complete    | --                | Written session-058. Session-061:|
|                         |             |                   | Arbitration Model corrected.     |
| sc_table_interfaces.md  | Complete    | --                | Written session-058.             |
| sc_table_hash_rules.md  | Complete    | --                | Written session-058.             |
| sc_tb_decisions.md      | Complete    | --                | Session-061: ST0 tb coverage gap |
|                         |             |                   | noted.                           |
| SC (unit)               | Complete    | --                | Remaining unit item:             |
|                         |             |                   | sc_coverage_plan.md. Cluster     |
|                         |             |                   | prereqs: #89/#90 open; #87/#88   |
|                         |             |                   | CLOSED BP-081; #91/#92 CLOSED    |
|                         |             |                   | session-063.                     |
| tb_bp_pkg.sv            | Complete    | sim               | BP-083: retrofitted to the       |
|                         |             |                   | dual-slot entry, 16 -> 23 checks,|
|                         |             |                   | mutation tested (4 defects).     |
|                         |             |                   | BP-090: SLOT_BITS gains the pos  |
|                         |             |                   | term; width checks added for     |
|                         |             |                   | ftb_pred_meta_t and              |
|                         |             |                   | bp_ftq_meta_t (neither had one); |
|                         |             |                   | pos driven, read back and        |
|                         |             |                   | rewritten on both slots; packing |
|                         |             |                   | tests added for ftb_pred_meta_t  |
|                         |             |                   | and the bp_ftq_meta_t ftb member.|
|                         |             |                   | 28 checks. 13 mutations, all     |
|                         |             |                   | fired.                           |
| bp_cluster.sv           | Complete    | lint_bp_cluster   | SESSION-063. BP-084 structural,  |
|                         | RTL only    | (no sim yet)      | BP-085 behavioural, BP-090       |
|                         |             |                   | rewire + metadata + closure.     |
|                         |             |                   | Eight instances, p0-p3 wiring,   |
|                         |             |                   | stage registers, p1 selection    |
|                         |             |                   | mux, RAS branch-type decode,     |
|                         |             |                   | redirect derivation at p2 and p3,|
|                         |             |                   | update fan-out by resolved type, |
|                         |             |                   | SC credit arbiter, and the p2/p3 |
|                         |             |                   | prediction metadata write groups.|
|                         |             |                   | Every boundary output driven; no |
|                         |             |                   | -Wno-UNDRIVEN. lint clean.       |
|                         |             |                   | NOT SIMULATED -- no tb_bp_cluster|
|                         |             |                   | exists. This is the next task.   |
| bpu_port_inventory.md   | Working     | --                | INFRA-011. 140 ports across the  |
|                         |             |                   | eight top-level modules, read    |
|                         |             |                   | from RTL and compared to the     |
|                         |             |                   | eight interface docs. 4 findings,|
|                         |             |                   | all in ubtb and bp_history.      |
| ftq_bpu_interfaces.md   | Draft       | --                | SESSION-063. FTQ/BPU port        |
|                         |             |                   | specification: request, p1       |
|                         |             |                   | prediction, late predictions,    |
|                         |             |                   | redirects, prediction metadata,  |
|                         |             |                   | updates, history checkpoint.     |
|                         |             |                   | Section 10 lists the corrections |
|                         |             |                   | other files still need.          |
| fe_decisions.md         | Draft       | --                | Created session-062. Front-end   |
|                         |             |                   | theory of operation. Two         |
|                         |             |                   | corrections outstanding: RAS top |
|                         |             |                   | of stack is p0 not p1 (2.2, 9),  |
|                         |             |                   | and 3.1 names per-predictor      |
|                         |             |                   | redirect ports that do not exist.|
| fetch                   | Not started | --                | After BP cluster                 |

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
|    | PRED_CREDITS=4 < STARVE_THRESH=8 so   | The bp_cluster SC arbiter       |
|    | starve_ctr never reaches threshold.   | (session-063) implements Rule 2;|
|    | Rule 4 is the effective ceiling.      | testability of it in            |
|    |                                       | tb_bp_cluster depends on the    |
|    |                                       | same parameter relationship.    |
|    |                                       | Resolve before that testbench.  |
| 40 | TB-ARB-05 spec discrepancy.           | bp_arb_spec.md testbench section|
|    | Old "backpressure 2 cycles" note did  | (was 10.1) removed session-057; |
|    | not match TAGE_UQ_DEPTH=8.            | tb requirements now live in the |
|    | No RTL risk.                          | implementing task file. Verify  |
|    |                                       | UQ_DEPTH there at tb_bp_cluster.|
| 42 | Pipeline diagram shows ITTAGE at s3,  | Revisit after SC definition.    |
|    | should be s2 (alongside FTB, TAGE).   | Update diagram and discussions. |
|    |                                       | #65 is CLOSED, BP-054           |
| 43 | Reduce ITTAGE CTR width 3b -> 2b.     | Impacts bp_defines_pkg.sv,      |
|    |                                       | ittage_table_interfaces.md, RTL |
|    |                                       | and testbenches.                |
| 49 | Arb queue status pin renaming.         | pq_not_full/upd_rdy ->          |
|    |                                        | tage_pq_not_full/tage_uq_not_   |
|    |                                        | full and ittage_ equivalents.   |
|    |                                        | Scope: RTL, tb, bp_arb_spec.md, |
|    |                                        | tage_interfaces.md,             |
|    |                                        | ittage_interfaces.md.           |
|    |                                        | Session-063: bp_cluster ALREADY |
|    |                                        | prefixes these at its boundary  |
|    |                                        | (two modules cannot both export |
|    |                                        | an unprefixed pq_not_full), so  |
|    |                                        | the rename inside tage.sv and   |
|    |                                        | ittage.sv is now cosmetic       |
|    |                                        | alignment, not a blocker.       |
| 52 | Move arb logic into submodule out of   | Top modules should be           |
|    | top in tage and ittage.                | structural only. New arb module |
|    | (Refactor; pairs with #73 test.)       | for tage and ittage. Co-        |
|    |                                        | sequence with arb test #73.     |
| 67 | tage sram_init non-fast path.          | All tests used +FAST_INIT,      |
|    | Untested here; confirm not elsewhere.  | bypassing real sram_init        |
|    |                                        | cycling. Confirm the COMP tests |
|    |                                        | cover the non-fast path; do not |
|    |                                        | assume.                         |
| 68 | ittage sram_init non-fast path.        | Same as #67.                    |
| 69 | tage rollback / history recompute.     | G20/G21/G22 RESOLVED            |
|    | Dark; tracks arch TBDs.                | session-054. Fold recompute     |
|    |                                        | proven in-sim BP-072. Rollback  |
|    |                                        | STIMULUS is now available: the  |
|    |                                        | cluster drives bp_history        |
|    |                                        | rollback from a derived redirect|
|    |                                        | (session-063). Exercise it in   |
|    |                                        | tb_bp_cluster. See TD #7.       |
| 70 | ittage rollback / history recompute.   | Same as #69 for ittage.         |
| 73 | Arbitration layer behavioral test.     | The SC credit arbiter is now    |
|    | Pairs with refactor #52.               | IMPLEMENTED in bp_cluster       |
|    |                                        | (session-063, bp_arb_spec 4.5   |
|    |                                        | grant rules, credits and starve |
|    |                                        | counter). It is UNTESTED. Fold  |
|    |                                        | the grant-rule tests into       |
|    |                                        | tb_bp_cluster. Folds in #37,    |
|    |                                        | #39, #40. Concurrent pred+upd   |
|    |                                        | remains the interaction of      |
|    |                                        | interest.                       |
| 74 | Dual-slot (NUM_PRED_SLOTS=2) test.     | bp_history part CLOSED          |
|    | bp_history dual-slot fold equivalence  | (BP-072), externally anchored   |
|    | proven; broader cluster dual-slot      | BP-073. Broader cluster         |
|    | still deferred.                        | dual-slot (slot 1 update path   |
|    |                                        | across TAGE/ITTAGE, both slots  |
|    |                                        | together) is now reachable in   |
|    |                                        | tb_bp_cluster. Reduction work   |
|    |                                        | in #1.                          |
| 75 | ittage has no fast versions of the     | The equivalent TAGE target is   |
|    | ittage sim targets.                    | sim_tage_fast. Create           |
|    |                                        | sim_ittage_fast.                |
| 77 | scrub prompts and redact any absolute  | Not a design TD; tools and infra|
|    | path not using the RVA_ROOT env var    | task, possibly manual.          |
| 78 | RAS p3 undo-pop does not reverse a   | LEAVE AS-IS. BP-064 pins the   |
|    | recursion pop.                       | current non-reversing behavior. |
|    |                                      | Revisit at bp_cluster           |
|    |                                      | integration if an s2/s3 repair  |
|    |                                      | over a recursion pop is ever    |
|    |                                      | required. Related: #79.         |
| 79 | RAS commit-stack recursion depth not | DEFER. The field is write-only  |
|    | preserved.                           | and never read by any output    |
|    |                                      | path, so a wrong value degrades |
|    |                                      | the fallback prediction only.   |
|    |                                      | Real fix needs a recursion-count|
|    |                                      | source on the commit interface. |
|    |                                      | Decide at FTQ integration.      |
| 80 | FTB confidence hysteresis tuning.    | FTB_CONF_WIDTH is the knob.     |
|    |                                      | Revisit at bp_cluster SPEC      |
|    |                                      | numbers.                        |
| 81 | tb_ftb coverage skews to br0.        | Optional symmetric br1 augment. |
|    |                                      | Not a blocker; sim_ftb 99/0.    |
| 82 | bp_history if/else-if slot cleanup.  | decisions.md 3.5. Fold into the |
|    |                                      | next bp_history RTL touch. No   |
|    |                                      | behavior change.                |
| 83 | bp_history decisions.md s6.6 origin  | Fill the Xiangshan commit sha / |
|    | citation placeholders.               | date. Manual, low priority.     |
| 84 | Producer/consumer end-to-end fold    | BP-073 proved the fold VALUE    |
|    | check.                               | against the canonical           |
|    |                                      | definition; it did NOT run that |
|    |                                      | fold through the TAGE/ITTAGE    |
|    |                                      | table index hash. Cluster       |
|    |                                      | stimulus now exists -- do this  |
|    |                                      | in tb_bp_cluster. SC ST1-ST3    |
|    |                                      | are additional consumers.       |
| 85 | bp_structs_pkg.sv                    | Review BPU structures for       |
|    |                                      | field sharing and storage/flop  |
|    |                                      | opportunities.                  |
| 86 | sc_cntrl 8x-weighted TAGE term.      | The current sum includes        |
|    |                                      | tage_extd_ctr at weight 1. The  |
|    |                                      | 8x variant is deferred to PD /  |
|    |                                      | perf. Related: #93.             |
| 87 | tage strong/medium/weak decode       | CLOSED BP-081 (session-060).    |
| 88 | tage_extd_ctr generation             | CLOSED BP-081 (session-060).    |
| 89 | ftb       | Change the FTB definition to store 20 additional bits.   |
|    |           | These are PC bits [15:6] of branch location              |
|    |           | These will be supplied to sc_upd_inp.branch_range        |
| 90 | ftb       | Change the FTB to store 2 additional bits. The signs of  |
|    |           | the branch targets for conditional branch 0/1 should be  |
|    |           | stored as backwards_branch0/1.                           |
|    |           | These will be supplied to sc_upd_inp.backwards_branch.   |
|    |           | Two bits, one per prediction slot.                       |
| 91 | bpc       | CLOSED session-063. bp_cluster stages the request PC     |
|    |           | p0 -> p2 and drives sc.inp_pc_p2[VA_WIDTH-1:1] per slot  |
|    |           | from the p2 copy. TAGE does not return the PC --         |
|    |           | tage_pred_meta_t has no pc field -- so the cluster keeps |
|    |           | its own staged copy. ras_pc_p2 is driven from the same   |
|    |           | staged value.                                            |
| 92 | bpc/sc    | CLOSED session-063. bp_cluster captures                  |
|    |           | bp_folded_hist.tage_phr[9:0] at p0 and stages it to p2   |
|    |           | as sc_phr_p2.                                            |
|    |           | RELATED, STILL OPEN: the three SC index folds            |
|    |           | (sc_t1/t2/t3_idx_fh_p2) are now staged the same way      |
|    |           | (BP-090), because bp_history advances whenever a branch  |
|    |           | is predicted and the live folds at p2 belonged to a      |
|    |           | later block. bp_arb_spec.md 6.1 lists only the PC and    |
|    |           | phr as staged inputs and should be updated to name the   |
|    |           | folds.                                                   |
| 93 | sc        | SC efficacy and threshold/band tuning -- deferred        |
|    |           | investigation. Open questions at PD/perf: does SC earn   |
|    |           | its area/power; the SC_THRSH_MID=10 / SC_THRSH_MAX=512   |
|    |           | seeds vs achievable |sum|~322; the vlo/vvlo band split   |
|    |           | (local, not O-GEHL); the 8x TAGE term (#86) interaction. |
|    |           | Refs: O-GEHL ISCA 2005; Storage-Free Confidence HPCA     |
|    |           | 2011; TAGE-LSC MICRO 2011. Gate any SC die-area          |
|    |           | commitment on this.                                      |
| 94 | bp_arb_spec | CLOSED BP-081 (session-060). Residual doc item:        |
|    |           | sections 9/10 are stubs and section 6.1 should now name  |
|    |           | the SC index folds as staged inputs (see #92).           |
| 95 | tage      | CLOSED BP-081 (session-060).                             |
| 96 | bpc       | Flush operation has scattered mention across documents.  |
|    |           | Define flush behavior, implement it, and update all      |
|    |           | references. bp_cluster now exists and passes             |
|    |           | ftb_flush_px and the RAS flush group straight through    |
|    |           | with no flush behaviour of its own. G24 is the FTB half. |
| 97 | bp_arb    | To determine whether a shared upstream PQ broadcasting   |
|    |           | to all predictor PQs is implemented. Deferred. The       |
|    |           | per-predictor PQ interfaces are compatible with either.  |
| 98 | sc_cntrl  | sc_cntrl shared scalar state under dual-slot update.     |
|    |           | TEMPORARY (BP-077): lowest-indexed valid update slot     |
|    |           | drives the shared threshold/TC/chooser/BrIMLI            |
|    |           | adaptation. Evaluate at PD/perf: duplicate per slot,     |
|    |           | share with a defined merge, or keep the current rule.    |
|    |           | Related: #93, #86.                                       |
| 99 | bpu       | Create a PR/CI/CD process. Motivating evidence           |
|    |           | (session-060): `make all` silently omits sim_ittage,     |
|    |           | sim_tage_manual and the cov_* targets. The CI process    |
|    |           | must run the complete target set -- 45 targets as of     |
|    |           | session-063 -- not `make all`.                           |
| 100 | tage     | tage line coverage below the previously-stated >90%.     |
|     |          | cov_tage 73.7% (6242/8468), cov_tage_table 79.5%         |
|     |          | (399/502), unchanged session-063. UNRESOLVED whether     |
|     |          | this is genuine under-coverage of the TD#87/#88 logic or |
|     |          | an accounting artifact. cov_bpu is 78.6% (8605/10942).   |
| 101 | ras.sv   | Declares input ras_pc_p2, unread in the module.          |
|     |          | Session-063: bp_cluster drives it from the correctly     |
|     |          | staged p2 PC, so the port is no longer dangling at the   |
|     |          | cluster level, but ras.sv still does not read it.        |
|     |          | Confirm needed or remove from ras.sv and tb_ras.sv.      |
| 102 | bp_history.sv | Does not generate IT5 folds. ittage.sv wires        |
|     |          | it_t5_idx_fh/tag_fh1/tag_fh2 to bp_history outputs that  |
|     |          | are never driven -- permanently 0. IT5 has real history  |
|     |          | (IT_TBL_HIST[5]=32, FH=9, FH1=9, FH2=8). Consequence:    |
|     |          | IT5 indexes on PC alone, so the longest-history ITTAGE   |
|     |          | table contributes no history and duplicates a short-     |
|     |          | history table. Prediction accuracy loss, not a           |
|     |          | correctness break. Add IT5 fold generation (same pattern |
|     |          | as IT1-IT4).                                             |
| 103 | tage     | tage initializes T0 to 00 (strongly not taken). Intended |
|     |          | is weakly taken, b10. Impacts TAGE_SRAM_INIT_VALUE use   |
|     |          | with sram_init. When this closes, update                 |
|     |          | tage_cntrl_decisions.md's T0 init line again (see the    |
|     |          | conflict note at the top of this file).                  |
| 104 | ftb      | Two stale RTL header comments (INFRA-008). Comment-only: |
|     |          |   - ftb_cntrl.sv: "107 bits/way", actual 105.            |
|     |          |   - ftb.sv: ftb_fastpath_en "beyond the interface draft",|
|     |          |     it is a documented top input.                        |
|     |          | Fold into the first FTB-touching RTL task.               |
| 105 | loop_pred| CLOSED BP-091                                            |
|     |          | loop_pred dual-slot retrofit. loop_pred.sv is single     |
|     |          | slot; no port carries a slot dimension. fe_decisions.md  |
|     |          | 2.1 and ftq_bpu_interfaces.md section 4 describe both LP |
|     |          | and uBTB presenting NUM_PRED_SLOTS predictions per       |
|     |          | cycle. Retrofit to dual prediction: slot dimension on    |
|     |          | pred_pc_p0, pred_valid_p0, pred_p0, upd_p0,              |
|     |          | upd_valid_p0, and the internal tables per TI6. Fold in   |
|     |          | the pred_p0 -> pred_p1 rename while the testbenches are  |
|     |          | already being touched. Touches loop_pred.sv,             |
|     |          | tb_loop_pred.sv, loop_pred_interfaces.md.                |
|     |          | CONSEQUENCE TODAY: bp_cluster gives slot 1 the uBTB      |
|     |          | prediction unconditionally, and the p2 loop metadata for |
|     |          | slots above 0 is driven to zero rather than a real       |
|     |          | per-slot snapshot. Found INFRA-011 / session-063.        |
| 106 | bp_structs_pkg | lp_pred_t and bp_loop_meta_t carry the SAME        |
|     |          | thirteen fields in DIFFERENT declaration order, and two  |
|     |          | are spelled differently (lp_past_itr / lp_pst_itr,       |
|     |          | lp_curr_itr / lp_cur_itr). bp_cluster maps between them  |
|     |          | field by field in lp_to_meta(); a bit-level recast would |
|     |          | compile and scramble every field. Retire one of the two  |
|     |          | types. Found session-063.                                |
| 107 | bp_cluster | Two stale comments in bp_cluster.sv, comment-only:     |
|     |          |   - the port-list comment reads "section 7: update       |
|     |          |     channel"; ftq_bpu_interfaces.md numbers the update   |
|     |          |     channel as section 8, and 7 is the prediction        |
|     |          |     metadata added session-063.                          |
|     |          |   - the w_slot_pc_p1 comment still says ubtb.sv derives  |
|     |          |     its slot 1 lookup from pred_pc_p0 + FTB_BLOCK_BYTES. |
|     |          |     BP-086 retired that model.                           |
|     |          | Fold into the next bp_cluster touch. Found BP-090.       |
| 108 | bp_cluster | No p1 output carries the block successor or the       |
|     |          | fall-through. ftq_bpu_interfaces.md section 4 lists      |
|     |          | bpu_pred_val_p1, bpu_pred_idx_p1, bpu_pred_slot_p1 and   |
|     |          | bpu_pred_ras_p1. The FTQ derives the successor from the  |
|     |          | slot array (fe_decisions.md 2.4), but on a not-taken     |
|     |          | block it needs the block end, and blk_p1.pft_addr stays  |
|     |          | inside the cluster. DECIDE whether a fall-through        |
|     |          | belongs on the p1 output group. Raised session-063,      |
|     |          | not decided.                                             |

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
| 8        | Investigate mutation testing            | IN PRACTICE. BP-083,|
|          |                                         | BP-086 and BP-090   |
|          |                                         | each mutation-tested|
|          |                                         | their testbenches   |
|          |                                         | against injected    |
|          |                                         | defects on scratch  |
|          |                                         | copies outside the  |
|          |                                         | tree. Every         |
|          |                                         | mutation fired.     |
|          |                                         | Consider making it  |
|          |                                         | a standing testbench|
|          |                                         | requirement.        |
| 9        | Research verible-verilog-format for SV  | Planned             |
|          | formatting.                             |                     |
| 10       | README update: document tools/bin       | Pending             |
|          | layout and build instructions for       |                     |
|          | Verilator and Spike.                    |                     |
| 11       | tb_bp_cluster and its tests             | NEXT SESSION (064). |
|          |                                         | See handoff-064.    |

---

## BP Cluster Open TBDs

| ID  | Item                                  | Status                 |
|-----|---------------------------------------|------------------------|
| G5  | RAS commit stack entry count          | RESOLVED session-050.  |
|     |                                       | 16 spec + 32 commit,   |
|     |                                       | static partition.      |
| G6  | RAS recursion counter width           | RESOLVED session-050.  |
|     |                                       | 4b per entry.          |
| G7  | SC threshold value                    | REFRAMED session-056,  |
|     |                                       | values corrected 057.  |
|     |                                       | Threshold is DYNAMIC   |
|     |                                       | (O-GEHL). Tuning       |
|     |                                       | deferred TD#93.        |
| G8  | Dual pred bundle split point          | RESOLVED session-050,  |
|     |                                       | STALE session-062,     |
|     |                                       | SUPERSEDED session-063.|
|     |                                       | The "slot 0 pred_pc+   |
|     |                                       | 0:31 / slot 1 pred_pc+ |
|     |                                       | 32:63" split is the    |
|     |                                       | TAGE/ITTAGE bundle     |
|     |                                       | convention and does    |
|     |                                       | NOT govern block       |
|     |                                       | prediction. The two    |
|     |                                       | slots are the two      |
|     |                                       | conditional fields of  |
|     |                                       | ONE 32-byte block from |
|     |                                       | ONE lookup             |
|     |                                       | (ftb_decisions.md 2.1/ |
|     |                                       | 2.3, fe_decisions.md   |
|     |                                       | 10). ubtb.sv was       |
|     |                                       | rewritten to match     |
|     |                                       | (BP-086); the +32      |
|     |                                       | lookup is gone from    |
|     |                                       | the RTL.               |
| G9  | Update channel arbitration            | PARTIAL. The SC credit |
|     |                                       | arbiter is implemented |
|     |                                       | in bp_cluster          |
|     |                                       | (session-063) and      |
|     |                                       | untested. The FTB      |
|     |                                       | single update port     |
|     |                                       | (FTB-3 / IC-FTB-09)    |
|     |                                       | still has no FTQ-side  |
|     |                                       | scheduler. TD#73.      |
| G10 | TAGE/ITTAGE meta overload scheme      | TBD at implementation. |
|     |                                       | FTB-2 folds in here.   |
|     |                                       | Session-063: the       |
|     |                                       | metadata now has a     |
|     |                                       | real write path        |
|     |                                       | (ftq_bpu_interfaces 7),|
|     |                                       | so the overload scheme |
|     |                                       | is the remaining half. |
|     |                                       | See TD-FE-2.           |
| G14 | Confidence counter purpose            | Reserved, 4b.          |
|     |                                       | bp_ftq_slot_t          |
|     |                                       | .confidence is driven  |
|     |                                       | to zero by the cluster;|
|     |                                       | nothing reads it       |
|     |                                       | (FE-U3).               |
| G15 | Fold recompute timing concern         | REFRAMED session-054.  |
|     |                                       | Perf measurement, not  |
|     |                                       | a correctness gate.    |
| G16 | ignored labeling gap                  |                        |
| G17 | Slot 1 PC derivation (pred_pc+32)     | RESOLVED session-050,  |
|     |                                       | SUPERSEDED session-063.|
|     |                                       | Same as G8: this is    |
|     |                                       | the TAGE/ITTAGE bundle |
|     |                                       | convention only. There |
|     |                                       | is no slot-1 PC in the |
|     |                                       | uBTB or the FTB.       |
| G18 | carry field consumer in cluster       | STILL TBD. ubtb_pred_t |
|     |                                       | .carry has no consumer |
|     |                                       | in bp_cluster. Its     |
|     |                                       | meaning changed        |
|     |                                       | session-063: it is the |
|     |                                       | entry fall-through     |
|     |                                       | carry, not a property  |
|     |                                       | of the slot target.    |
|     |                                       | (= UI2)                |
| G19 | NO_BRANCH target on hit:              | RESOLVED session-063.  |
|     | fall-through PC or zero?              | A uBTB hit with no     |
|     |                                       | valid slot IS the      |
|     |                                       | no-branch state; the   |
|     |                                       | successor is           |
|     |                                       | blk_p1.pft_addr. No    |
|     |                                       | sentinel target value  |
|     |                                       | is needed and          |
|     |                                       | NO_BRANCH is no longer |
|     |                                       | producible on pred_p1. |
|     |                                       | (= UI4)                |
| G20 | bp_history dual slot update path      | RESOLVED session-054.  |
|     |                                       | Proven in-sim BP-072.  |
| G21 | rollback_en + pred_valid same-cycle   | RESOLVED session-054.  |
|     | priority undefined                    | Rollback wins.         |
| G22 | One-cycle folded output invalid       | RESOLVED session-054.  |
|     | window after rollback                 | Folds STALE not        |
|     |                                       | invalid.               |
| G23 | Checkpoint slot reclaim protocol      | TBD at FTQ impl.       |
|     |                                       | (= bp_history HI5)     |
| G24 | FTB flush protocol (ftb_flush_px)     | TBD at bp_cluster.     |
|     |                                       | Session-063: the port  |
|     |                                       | is a cluster input and |
|     |                                       | passes straight to     |
|     |                                       | ftb.sv. No flush       |
|     |                                       | behaviour exists at    |
|     |                                       | the cluster. TD#96.    |
| G25 | FTB fast-path enable source           | TBD. Session-063:      |
|     | (ftb_fastpath_en: CSR / tie /         | ftb_fastpath_en is a   |
|     | runtime)                              | bp_cluster input port  |
|     |                                       | and passes through to  |
|     |                                       | ftb.sv. The SOURCE is  |
|     |                                       | still undecided.       |
|     |                                       | ftb_fastpath_p2 has no |
|     |                                       | consumer in the        |
|     |                                       | cluster -- the         |
|     |                                       | fast-path bypass is    |
|     |                                       | not built.             |

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

Full detail: planning/arch/bp_cluster.md (LOCKED),
planning/arch/fe_decisions.md (theory of operation),
planning/interfaces/ftq_bpu_interfaces.md (port specification).

Key decisions for quick reference:
- Seven predictors: uBTB, Loop, FTB, TAGE, SC, ITTAGE, RAS
- Pipeline: p0 index, p1 uBTB+Loop, p2 FTB+TAGE+ITTAGE+RAS,
  p3 SC
- ITTAGE overrides FTB target at p2 for indirect branches
  (including indirect CALL). RAS overrides FTB target at p2
  for returns and separately pushes the return address on
  indirect/direct CALL.
- Loop overrides uBTB at p1 when trusted
- Update policy: post-execute, not retire
- RAS: dual-stack, static partition, 16 speculative +
  32 commit entries. Pointer-only snapshot recovery.
- FTB: single set-associative array (4-way / 2048 / 512
  sets), 26-bit full tag, tree-PLRU, 2 conditional + 1 jump
  per entry. Storage split ftb_array / ftb_plru / ftb_cntrl.
  conf is a bimodal DIRECTION counter; saturated-endpoint
  fast-path (ftb_fastpath_en). FTB target is the ITTAGE-miss
  / RAS-empty fallback.
- uBTB: ONE lookup per cycle. The entry mirrors the FTB
  entry -- two conditional fields, one jump field, partial
  fall-through with carry, displacement targets with a
  fit/overflow/underflow status. One entry describes one
  32-byte block and supplies both prediction slots. The
  pred_pc+32 slot-1 lookup is retired (session-063, BP-086).
  Entry hit is reported once per lookup on blk_p1.hit; a slot
  valid bit means only that the slot carries a branch.
- BPU is decoupled frontend, self-generates next PC
- FTQ depth 64, split fast/slow SRAMs
- History: GHR 256b, PHR 32b, folds recomputed on rollback.
  Pointer module-owned. Fold geometry canonical in
  bp_history_decisions.md s6. ITTAGE IT5 has real folded
  history but bp_history does not generate it -- TD#102 open,
  so IT5 currently indexes on PC alone.
- TAGE entry: T0 2b CTR only, T1-T4 valid+tag+CTR+useful.
  T0 init value under review, TD#103 open.
- ITTAGE entry: IT1-IT5 valid+tag+EPC+USE+CTR(3b)+TGT(38b).
  No IT0 base table.
- SC index: uniform 5-entry arrays. No tag bits. ST4 is
  BrIMLI, SC only. Dynamic threshold (O-GEHL), two-corner
  chooser. br_imli_mode is a compile-time parameter.
- SC arbitration: the section 4.5 credit arbiter is now
  IMPLEMENTED IN bp_cluster (session-063), not stubbed. SC
  has no independent prediction FIFO; the cluster presents no
  update FIFO either, since the producer holds valid until
  accepted and the FTQ is the holding element. CSR sc_enable
  gates SC participation and the cluster does not wait on SC
  when it is disabled.
- NUM_PRED_SLOTS=2 is the default. Reduction to 1 deferred
  (debt #1).
- Port naming convention: <signal>_<pipestage>. The eight
  modules do NOT all follow it; the actual variance is
  recorded in bpu_port_inventory.md and ftq_bpu_interfaces.md
  section 2. Ports are used as declared; no renaming was done.
- TI6: banks are per-slot RAMs. TAGE/ITTAGE/SC convention;
  does NOT apply to FTB or, since session-063, to the uBTB.

### bp_cluster boundary decisions (session-063)

- Predictors declare NO redirect ports -- confirmed across all
  140 ports. The cluster derives the redirect by comparing a
  predictor's stage output against the prediction it formed at
  p1 and carried in its own stage registers. bp_cluster does
  not read the FTQ. The groups are named by STAGE:
  bpu_redir_p2 and bpu_redir_p3, each a bp_redirect_t array
  with a scalar index alongside.
- The redirect comparison reduces both views to ONE quantity,
  the address fetched after that slot. Two not-taken views
  compare equal. The p1 operand is formed at p1 from the p1
  view only: the slot target when taken, the uBTB
  fall-through on a hit, the block-aligned PC plus
  FTB_BLOCK_BYTES on a miss. Consequence: a stale uBTB block
  boundary now redirects at p2 instead of the front end
  fetching past a boundary the FTB had already contradicted.
- The p3 comparison is against the p2-corrected value, not the
  raw p1 prediction, so a p3 redirect fires only when SC
  changes what the cluster published at p2.
- Every p2 and p3 comparison is qualified by branch_id equal
  to the FTQ index in the matching stage register, so a queued
  or back-pressured response cannot be compared against the
  wrong entry. The redirect logic assumes no fixed predictor
  latency.
- The FTQ slow path is written by TWO groups with disjoint
  members so the FTQ never merges: p2 writes tage, ittage, lp
  and ftb; p3 writes sc. The loop predictor finalizes at p1
  and its result is registered forward into the p2 group.
- The uBTB update branch type is REDERIVED from the payload's
  own is_br / is_jmp / is_call / is_ret / is_jalr bits, never
  restored as a field. Verilator resolves a missing br_type
  read to zero, which decodes as COND; restoring the field
  instead would silently classify every update as conditional
  and stop ITTAGE ever being updated.
- The jump field is reported in the lowest prediction slot
  carrying no valid conditional field. The jump is the
  block-terminating branch, so lowest-free-slot placement is
  program order.
- RAS p2 operations are gated by reachability across slots: a
  taken branch ends the block, so a later slot must not push
  or pop (FE-11).
- The SC prediction PC, phr[9:0] and the three SC index folds
  are all staged p0 to p2 by the cluster. TAGE and ITTAGE take
  bp_folded_hist_t whole at their own p0 request.

### Shared planning documents
    - planning/arch/bp_arb_spec.md                    In progress
        - RECONCILED session-057 to the standalone-SC model.
          TD#94 CLOSED BP-081. Session-063: section 6.1 should
          name the SC index folds as staged inputs (TD#92).
    - planning/arch/bp_cluster.md                     In progress
        - Branch prediction cluster summary data.
    - planning/arch/fe_decisions.md                   Draft
        - Front-end FTQ<->BPU theory of operation (session-062).
          Two corrections outstanding: RAS top of stack is p0
          not p1 (2.2, 9); section 3.1 names per-predictor
          redirect ports that do not exist.
    - planning/interfaces/ftq_bpu_interfaces.md       Draft
        - FTQ/BPU port specification (session-063). Section 10
          lists the corrections other files still need.
    - planning/interfaces/bpu_port_inventory.md       Working
        - 140-port inventory of the eight top-level modules
          (INFRA-011).
    - planning/arch/ras_decisions.md                  Draft
    - planning/arch/sram_init.md                      Complete
    - planning/testbenches/manual_tb_decisions.md     Complete

### bp_cluster decomposition (session-063)

- RTL COMPLETE, NOT SIMULATED.
    - rtl/core/frontend/bpu/rtl/bp_cluster.sv
    - lint_bp_cluster clean, zero warnings, zero errors.
    - No tb_bp_cluster, no sim_bp_cluster, no cov_bp_cluster.
- Built in three tasks:
    - BP-084 structural: eight instances, p0-p3 wiring,
      tie-offs, elaborate-only. Reported every tie-off and
      every unconsumed output with its reason; that table was
      the work definition for BP-085.
    - BP-085 behavioural: stage registers, p1 selection mux,
      RAS branch-type decode, redirect derivation at p2 and
      p3, update fan-out by resolved branch type, SC credit
      arbiter. -Wno-UNDRIVEN removed from lint_bp_cluster.
    - BP-090: uBTB rewire (blk_p1, entry hit, slot pos,
      update fan-out rebuild), the p2 and p3 metadata write
      groups, the p1 fall-through consumer, SC index fold
      staging, tb_bp_pkg width and stimulus fixes, package
      comment corrections, header refresh.
- Ports: the request group, the p1 prediction group, the two
  redirect groups, the two metadata groups, the seven
  predictors' update channels, the RAS restore/commit/flush
  groups, the history outputs, the configuration sidebands
  and the queue-status sidebands.
- Known state at the boundary:
    - Every boundary output has a producer.
    - The nine metadata outputs have no consumer in this
      repository: the FTQ is not built. Their specified
      consumer is ftq_bpu_interfaces.md 7.1 and 7.2.
    - ftb_fastpath_p2 has no consumer; the fast-path bypass
      is not built (G25).
    - ubtb_pred_t.carry and .conf have no consumer (G18,
      FE-U3).
- Deferred to tb_bp_cluster (session-064): everything. See
  session_handoff-064.md for the test list.

### TAGE decomposition
- Session-060 (BP-081): tage RECONCILED and GREEN.
- Session-061: planning docs reconciled to TD#87/#88 and the
  T0 index/init corrections. TD#103 open on T0 init value.
- RTL available; unit and manual testbenches written.
    - Line coverage: cov_tage 73.7% / cov_tage_table 79.5%.
      TD#100 tracks whether this is under-coverage or drift.
    - Directed validation complete.
    - Remaining deferred: #69 rollback (stimulus now available
      in the cluster), #67 sram_init non-fast, #74 dual-slot,
      #100 coverage review, #103 T0 init value.
    - Formal validation not started.
- BP-006 through BP-032, BP-041, BP-056 through BP-061,
  BP-081: complete.
- Tage planning documents: alloc / ctr / decisions / uaon /
  use rules, table hash rules, table entry formats, and the
  two interface documents. All Complete.

### ITTAGE decomposition
- RTL available; unit testbenches written; directed validation
  complete; formal validation not started.
- Remaining deferred: #69/#70 rollback, #43 CTR width, #75
  sim_ittage_fast, #68 sram_init non-fast, #102 IT5 fold
  generation.
- BP-034 through BP-042 complete (BP-033 abandoned).
- Session-061 (INFRA-010) corrections applied across the
  ITTAGE planning set.
- ITTAGE planning documents: alloc / ctr / decisions / uaon /
  use rules, table entry formats, table hash rules, and the
  two interface documents. All Complete.

### RAS decomposition
- planning/arch/ras_decisions.md            Draft
- planning/interfaces/ras_interfaces.md     Draft
- RTL: rtl/ras.sv complete (BP-062), tb/tb_ras.sv complete
  (BP-063), sim_ras 87/0.
- TD #78 pinned, TD #79 deferred, TD #101 open.
- Key decisions session-050: G5, G6, G8, G17; simple circular
  buffer internal structure.
- Session-063: the cluster drives the p2 classification and
  the p3 repair pair from the registered p2 values, gates p2
  operations by reachability across slots, and drives
  ras_pc_p2 from the staged p2 PC.

### FTB decomposition
- RTL available and verified (session-053). sim_ftb 99/0.
- Structure: ftb_array (1R1W data RAM), ftb_plru (valid +
  tree-PLRU flops), ftb_cntrl (all logic), ftb (structural
  top).
- Key decisions session-053: storage split, conf as a bimodal
  direction counter, saturated-endpoint fast-path, position
  sourced and sunk, final widths logical 106/424 and RAM
  105/420.
- Deferred to bp_cluster: flush (IC-FTB-07 / G24), conf x TAGE
  meta (FTB-2 / G10), update arbitration (FTB-3 / IC-FTB-09 /
  G9), FTQ round-trip (IC-FTB-10), ftb_fastpath_en source
  (G25).
- SC-facing additions deferred: TD#89 branch PC[15:6], TD#90
  per-slot backwards-branch sign.
- Session-063: the cluster consumes the FTB p2 outputs for
  branch classification, the redirect target sources and the
  fall-through, and carries ftb_hit_p2 / ftb_way_p2 /
  ftb_jmp_pos_p2 into the p2 metadata group -- closing the
  IC-FTB-10 carried-writeWay path at the cluster boundary.
  ftb_br0/br1_conf_p2 and ftb_fastpath_p2 remain unconsumed.
- FTB planning documents: ftb_decisions.md,
  ftb_interfaces.md, ftb_confidence_override_rules.md. All
  Complete.

### SC decomposition
- Planning COMPLETE and RTL COMPLETE at unit level
  (session-058/059). Remaining unit item:
  sc_coverage_plan.md.
- RTL: sc_table.sv, sc_brimli.sv, sc_cntrl.sv, sc.sv, with
  tb_sc_table / tb_sc_brimli / tb_sc_cntrl / tb_sc. All green.
- Package changes session-056/057/058/060 as recorded above.
- Prerequisites for cluster integration:
    - #87 / #88 CLOSED BP-081.
    - #91 / #92 CLOSED session-063 (PC and phr staged p0->p2
      by bp_cluster).
    - #89 / #90 still open (FTB stores branch PC[15:6] and the
      per-slot backwards sign).
    - #84 end-to-end fold check extends to SC ST1-ST3; the
      cluster stimulus for it now exists.
- Session-063: the SC credit arbiter moved from stubbed to
  implemented, in bp_cluster. The three SC index folds are
  staged p0 to p2 with the PC and phr.

### bp_history decomposition
- COMPLETE at unit level (session-055).
- Session-061 (INFRA-010): the "IT5 is BrIMLI, no folds" claim
  was removed from bp_history_decisions.md and bp_cluster.md.
  RTL gap opened as TD#102.
- Planning: bp_history_decisions.md (Draft, s6 canonical fold
  definition, s7 post-advance checkpoint),
  bp_history_interfaces.md (Draft).
- RTL: bp_history.sv complete. Lint clean, no bpu regression.
  TD#102 open.
- Verification: BP-072 dual-slot fold equivalence (19224
  golden comparisons), BP-073 external anchor, BP-074 doc-RTL
  consistency audit.
- Key decisions session-054: G20, G21, G22, module-owned
  pointer with mispredict-only restore.
- Key decisions session-055: fold geometry captured natively;
  checkpoint timing ratified post-advance.
- Open / deferred: HI2, HI5 (= G23), #82, #83, #84, #69/#70,
  #102.
- Session-063: the cluster drives pred_taken, pred_pc and
  num_branches from the formed p1 prediction, compacted by
  branch number rather than slot number, writes the checkpoint
  at allocation, and drives rollback from the derived
  redirect with the p3 index winning.

### Shared components track
- components/rtl  components/tb

