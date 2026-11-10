<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Pacino Features
```
 FILE:    pacino_features.md
 SOURCE:  session-084
 STATUS:  DRAFT
 UPDATED: 2026-11-10
 CONTACT: Jeff Nye
```

What pacino is, as built: the RVA23S64 options it adds to the
mandatory set, and its salient features, sizes and assumptions.

This file summarizes; it decides nothing. Each entry names its
source, a parameter or declaration in the RTL or a decision ID, and
the decision files and the RTL govern where this file disagrees with
them. It describes one configuration, named as perf_decisions.md PF-5
names configurations:

```
  Configuration:  fe-1.0.0
  Extracted at:   79df3ad (uncommitted), by DOC-016
```

A variant of pacino (a <tag>/<name> configuration) gets its own
section listing only what differs from the configuration above.

---

## 1. RVA23S64 compliance

Pacino implements the mandatory set of the RVA23S64 profile. The
profile is the umbrella: the mandatory extensions are those the
profile lists, and are not repeated here. This section lists only the
profile's optional extensions (its expansion options) that pacino
also implements.

| Extension | What it adds                                   | Source          |
|-----------|------------------------------------------------|-----------------|
| Svadu     | hardware A/D bit update; menvcfg.ADUE selects Svade or Svadu at runtime | mmu_decisions.md MMU-6, MMU-7 |

Pacino is the front end and the MMU today; the units not yet built
implement nothing.

---

## 2. Features

From DOC-016's report, at the default parameters (NUM_PRED_SLOTS 2),
tree 79df3ad (uncommitted). Abbreviations in Source: bdp =
rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv, bsp =
rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv; other files by basename,
each unique under rtl/. LITERAL in Notes marks a value written in a
module rather than taken from a package parameter. KB is 1024 bytes.

### 2.1 Global

| Feature | Value | Source | Notes |
|---|---|---|---|
| XLEN | 64 | csr_pkg.sv:57 CSR_XLEN | LITERAL in package |
| VA_WIDTH | 41 | bdp:25 | rationale comment bdp:21-24 (Sv39x4 GPA, zero-extended) |
| GPA_WIDTH | 41 | bdp:592 | independent literal, not derived from VA_WIDTH |
| PA_WIDTH | 36 | bdp:573 | |
| PPN_WIDTH | 24 = PA_WIDTH - 12 | bdp:600 | |
| FAULT_GPA_WIDTH | 56 (44-bit PPN + 12) | bdp:597 | literal |
| VPN_WIDTH / GVPN_WIDTH | 27 / 29 | bdp:599, 598 | literals; neither is used by any listed module. VPN ports are [VA_WIDTH-13:0] (29 bits) |
| ASID / VMID widths | 16 / 14 | bdp:601, 602 | |
| NUM_PRED_SLOTS | 2 (default of macro BP_NUM_PRED_SLOTS; legal 1 or 2) | bdp:62-65, 75-88 | branches predicted per fetch block |
| Prediction (fetch) block | 32 bytes, FTB_BLOCK_BYTES | bdp:173 | used by IFU (ifu_fetch.sv:186) and BPU |
| FETCH_BLOCK_BYTES | 64 | bdp:41 | declared, referenced by no listed module |
| Positions per block | 16 halfwords, FTQ_PD_WIDTH = 32/2 | bdp:237 | |
| Decode width | 8, SLOTS | decode_pkg.sv:21 | |
| ibuf read width | 8, IBUF_RD_WIDTH | ibuf.sv:58 | matches decode |
| GHR_WIDTH / PHR_WIDTH | 256 / 32 | bdp:26, 27 | circular buffers, pointers 8 / 5 bits (bdp:28, 29) |
| FTQ_DEPTH | 64 | bdp:30 | |
| Reset vector | 0x8000_0000, [VA_WIDTH-1:0] | bdp:40 RESET_VECTOR | value is LITERAL; consumed at ftq_npc.sv:478 |
| PC_HASH_SHIFT | 2 | bdp:53 | TAGE and ITTAGE index drop PC[1:0]; bdp:50-52 notes PC bit 1 under C as an open question |

### 2.2 Branch prediction unit

Stage map (bp_cluster.sv:55-61): p0 RAM indices and RAS TOS read; p1
uBTB and loop; p2 FTB, TAGE, ITTAGE, RAS, loop re-read; p3 SC.

Override order:

| Feature | Value | Source | Notes |
|---|---|---|---|
| p1 per slot | loop (trusted, and uBTB slot valid) supplies direction with the uBTB target; else uBTB; a uBTB RETURN/RETURN_CALL with a valid RAS TOS takes the RAS target; else none | bp_cluster.sv:789-849 | pred_src LOOP / RAS / UBTB / NONE |
| p2 conditional direction | loop p2 re-read (trusted) > TAGE (branch_id match) > FTB counter MSB | bp_cluster.sv:1016-1036, 1161-1162 | |
| p2 targets | RETURN/RETURN_CALL: RAS pop if valid, else FTB; INDIRECT_*: ITTAGE if hit, else FTB; DIRECT_*: FTB | bp_cluster.sv:1164-1178 | |
| p2 needs an FTB hit | on an FTB miss TAGE, ITTAGE and RAS do not change the p1 prediction | bp_cluster.sv:991, 1214, 1261 | |
| p3 | SC replaces a COND direction when SC hits and sc_enable, unless the loop supplied it | bp_cluster.sv:1296-1304, 1344-1349 | pred_src = SC only when SC changed the direction |
| Full order, direction | loop > SC > TAGE > FTB (p2/p3); loop > uBTB (p1) | as above | |
| Full order, target | RAS (returns), ITTAGE (indirect), FTB (others) at p2; uBTB or RAS TOS at p1 | as above | |
| Redirect | p2/p3 redirect when the successor of a reachable slot differs from the earlier view | bp_cluster.sv:1213-1217, 1317-1325 | |
| Squash | from ftq_rollback_val only; rollback priority FTQ > p3 > p2 | bp_cluster.sv:1385-1404 | |
| bp_pred_src_e | 3 bits: UBTB 0, LOOP 1, FTB 2, TAGE 3, SC 4, ITTAGE 5, RAS 6, NONE 7 | bsp:100-109 | |
| Training time | at resolve (post-execute), from the FTQ; RAS commit stack at retire | ftq_resolve.sv:9-13; ftq_entry.sv:269-286; ras.sv:18-21 | |

uBTB:

| Feature | Value | Source | Notes |
|---|---|---|---|
| Entries / ways / sets | 256 / 4 / 64 | bdp:314-315, 321 | one array, not per slot (ubtb.sv:99) |
| Entry | 107 bits: valid 1, tag 24, br0 23, br1 23, jmp 31, pft 5 | bdp:362-369; bsp:628-663 | |
| Tag | 24 = {pc[30:11], pc[4:1]} | bdp:336-337 UBTB_RTAG_BITS 20 (LITERAL); ubtb.sv:142-147 | |
| Cond slot | valid 1, pos 4, tgt 13 (displacement from block start), stat 2, conf 3 | bsp:628-635 | conf is a 3-bit bimodal counter; MSB = direction |
| Jump slot | valid 1, pos 4, tgt 21, stat 2, is_call, is_ret, is_jalr | bsp:639-647 | no is_rvc bit (FTB has one) |
| Useful bit | none | | |
| Index | pc[10:5] ^ (pc[4:1] << 2), 6 bits; no history | ubtb.sv:135-140; bdp:338 | |
| Stage | combinational lookup of pred_pc_p0, registered into p1; predicts p1 every cycle | ubtb.sv:62-70; bp_cluster.sv:687-701, 1839 | |
| Training | upd_u0, one per slot (2 write ports), post-execute | ubtb.sv:92, 550-557; bsp:689-690 | |
| Replacement | per-set round-robin wr_ptr (2 bits), advanced on miss-allocate; no invalid-way preference | ubtb.sv:103-104, 481, 553-555 | |
| Storage | flops; async reset clears valid and wr_ptr only | ubtb.sv:541-548 | |

FTB:

| Feature | Value | Source | Notes |
|---|---|---|---|
| Entries / ways / sets | 2048 / 4 / 512 | bdp:171-172, 175 | one array |
| Logical entry | 114 bits: valid 1, tag 30, br0 23, br1 23, jmp 32, pft 5 | bdp:267-274 FTB_ENTRY_WIDTH | |
| RAM entry | 113 bits (valid bit lives in ftb_plru) | bdp:288; ftb_cntrl.sv:226-232, 932 | |
| Tag | 30 = {pc[39:14], pc[4:1]} | bdp:193 FTB_RTAG_BITS = 26 (LITERAL, pinned), :199; ftb_cntrl.sv:333-337 | VA bit 40 aliases (bdp:187-192) |
| Cond slot | valid 1, pos 4, tgt 13 (displacement from branch PC), stat 2, conf 3 | ftb_cntrl.sv:205-211 | conf allocated 100 or 011 |
| Jump slot | valid 1, pos 4, tgt 21, stat 2, is_call, is_ret, is_jalr, is_rvc | ftb_cntrl.sv:213-224 | |
| Index | pc[13:5] ^ (pc[4:1] << 5), 9 bits; no history | ftb_cntrl.sv:322-331; bdp:207 | |
| Stage | p0 PC registered, array read at p1, outputs registered to p2; predicts p2 | ftb_cntrl.sv:404-415, 667-806 | |
| Port sharing | an update takes the single read port and the same-cycle prediction is dropped; the FTQ holds p0 one cycle per FTB update (H3) | ftb_cntrl.sv:69-82, 628-631; ftq_ftb_sched.sv:91-95, 327; ftq_npc.sv:306-309 | |
| Training | one update port u0, post-execute | ftb.sv:86; ftb_cntrl.sv:146-161 | ftb_upd_hit_u0 and ftb_upd_br_idx_u0 are not read |
| Replacement | tree-PLRU, 3 bits per set; victim chosen at predict and carried in FTQ meta; updated on predict hit or update | bdp:179; ftb_cntrl.sv:374-399, 682-689, 894-916 | no invalid-way preference |
| Flush | stub, clears p2 valids only | ftb_cntrl.sv:89-91, 814-841 | |

TAGE (T0 = tage_bim, T1-T4 = tage_table):

| Feature | Value | Source | Notes |
|---|---|---|---|
| Tables | 5 (T0 + T1-T4) | bdp:375 | |
| Entries | 2048 per table, per slot | bdp:378; tage_table.sv:113 RAM_DEPTH = 1 << THIS_INDEX_BITS | depth from TAGE_TBL_IDX = 11 |
| Ways | direct-mapped | tage_table.sv:337-338 | |
| Banks | 2 (index bit 10), LITERAL | tage_table.sv:114; tage_bim.sv:73 | bdp TAGE_TBL_BANKS unused |
| Per-slot copies | 2, one RAM per slot per table | tage_table.sv:203; tage_bim.sv:90 | both indexed by the block PC (bp_cluster.sv:1666); copy s trained by update channel s |
| T0 entry | 2-bit counter only | tage_bim.sv:38-39; bdp:384 | init 2 (weakly taken), bdp:418 |
| T1-T4 entry | 16 bits: VAL[0], CTR[3:1], USE[5:4], EPC[7:6], TAG[15:8] | tage_table.sv:52-58, 103-111 | localparams, no struct |
| Tag / ctr / useful / EPC | 8 / 3 (T0 2) / 2 / 2 | bdp:383-386 | |
| History lengths | T1 8, T2 13, T3 32, T4 119 | bdp:382 TAGE_TBL_HIST | |
| Fold widths | index T1 8, T2-T4 11; fh1 8; fh2 7 | bdp:379-381; bp_history.sv:210-245 | |
| T0 index | PC[12:2] | tage_bim.sv:139, 174 | |
| T1-T4 index | PC[12:2] XOR GHR fold | tage_table.sv:220-223 | GHR only, no PHR |
| T1-T4 tag | PC[18:11] ^ fh1 ^ (fh2 << 1) | tage_table.sv:227-229 | PC[12:11] are in both index and tag |
| Stage | RAM read p0 -> p1; result at p2 | tage_cntrl.sv:344, 364-369; bp_cluster.sv:58 | |
| Provider / alternate | longest hit / next-longest hit, T0 default | tage_cntrl.sv:497-523 | |
| USE_ALT_ON_NA | 4-bit counter per slot, LITERAL [3:0]; alt used when provider CTR is 011 or 100 and counter >= 8 | tage_cntrl.sv:193, 380-395, 529-549 | bdp TAGE_UAON_* unused |
| Useful update / aging | +/-1 when provider and alternate differ; 2-bit epoch per slot, 32-bit interval counter; effective U = U (age 0), U>>1 (age 1), 0 (age >= 2) | tage_cntrl.sv:196-199, 400-446, 797-842 | tage_enable_aging and tage_aging_interval values: not found in listed files |
| Allocation | on mispredict, one entry, shortest table above provider with effective U 0, chosen at p1; written {tag, epoch, U 00, CTR 100, VAL 1} | tage_cntrl.sv:577-585, 853-873 | no U decrement on failed allocation |
| Training | at resolve, from the FTQ, conditional only | bp_cluster.sv:214-216, 1798-1800 | |
| Arbitration | PQ 8, UQ 8, response 2; prediction beats update; starvation threshold 8 | bdp:426-432; tage_arb.sv:200-219 | single RAM port shared |

SC (ST0-ST3 = sc_table, ST4 = sc_brimli):

| Feature | Value | Source | Notes |
|---|---|---|---|
| Tables / entries | 5: ST0-ST3 512, ST4 1024 | bdp:445, 448 | |
| Ways / banks | direct-mapped; 2 banks LITERAL | sc_table.sv:87; sc_brimli.sv:95 | bdp SC_TBL_BANKS unused |
| Per-slot copies | 2 | sc_table.sv:143; sc_brimli.sv:149 | same PC r_pc_p2 both slots |
| Entry | 6-bit signed counter; no tag, useful, EPC or valid | sc_table.sv:16-19, 57-62 | init 0 (bdp:467) |
| History lengths | ST0 0, ST1 4, ST2 16, ST3 64; ST4 BrIMLI | bdp:450 | |
| ST0-ST3 index | PC[9:1] XOR fold[8:0] | sc_table.sv:111-114, 128-129 | ST2 and ST3 both see history offsets 1-9 only (fold width = H, 9-bit truncation) |
| ST4 index | 10'(bpc ^ f ^ (bpc >> 4)), bpc = PC[15:6], f = br_imli or phr10 | sc_brimli.sv:125-135; sc.sv:60 | phr10 is always 0: folded.tage_phr is never assigned (bp_cluster.sv:699 reads it; no write in bp_history.sv) |
| Stage | index p2, counters p3 | sc_cntrl.sv:19-29 | |
| Sum / chooser | sum of (2c+1) over 5 tables + tage_extd_ctr, 10 bits; 6-bit choosers | sc_cntrl.sv:303-347 | |
| Update / threshold | if SC wrong or abs(sum) < threshold, all 5 step; threshold reset 10, 1..512, 7-bit adaptation | sc_cntrl.sv:377-402, 465-482 | no allocation or replacement |
| Training | at resolve, cond, sc_enable; UQ 8 | bp_cluster.sv:222-224, 1804-1807; bdp:491 | |

Loop predictor (loop_pred):

| Feature | Value | Source | Notes |
|---|---|---|---|
| Entries / ways / sets | 256 / 4 / 64 per slot | loop_pred.sv:74-82 | module parameters shadow bdp:135-145 (same values), LITERAL defaults |
| Per-slot copies | 2 | loop_pred.sv:161-165 | |
| Entry | lp_entry_t 68: curs_v 1, curs 14, tag 14, past_itr 14, curr_itr 14, age 8, cnf 2, v 1 | bsp:719-728 | |
| Checkpoint | lp_ck_t 39 bits x FTQ_DEPTH per slot | loop_pred.sv:108-116, 168 | |
| Index | bit i = pc[i]^pc[i+1]^pc[i+4], 6 bits, PC[9:0] | loop_pred.sv:126-131 | |
| Tag | (pc ^ pc>>6 ^ pc>>12)[13:0], PC[25:0] | loop_pred.sv:133-138 | no history |
| Stage | p1 (registered), re-read at p2 (authoritative) | loop_pred.sv:288-318, 501-515 | |
| Trust | v, tag hit, curs_v, cnf == 3 | loop_pred.sv:269-273 | |
| Training | at resolve, cond only | bp_cluster.sv:190-192, 1678-1679 | |
| Allocation / replacement | miss, taken, backward; victim: lowest invalid, else lowest with age 0, else first of ways 1-3 with age < way 0, else way 0 | loop_pred.sv:234-258, 370-436 | ways 1-3 LITERAL; age is never decremented, so a full set always evicts way 0 |
| Storage | flops, async reset to 0 | loop_pred.sv:165, 445-477 | |

ITTAGE:

| Feature | Value | Source | Notes |
|---|---|---|---|
| Tables | IT1-IT5 tagged, no base table | bdp:501; ittage.sv:132-139 | |
| Entries | 256, 256, 512, 512, 512 per slot | bdp:513 IT_TBL_IDX; ittage_table.sv:119 | |
| Banks | 2, LITERAL | ittage_table.sv:120 | |
| Per-slot copies | 2 | ittage_table.sv:204, 340 | same PC and folds both slots |
| Entry | VAL[0], CTR[3:1], USE[5:4], EPC[7:6], TGT[47:8], TAG; 56 / 56 / 57 / 57 / 59 bits | ittage_table.sv:15-21, 107-117 | fields sized by IT_MAX_* |
| Tag / ctr / useful / EPC | 8, 8, 9, 9, 11 / 3 / 2 / 2 | bdp:509, 518-520 | CTR is confidence |
| Target | absolute VA[40:1], 40 bits, rebuilt {tgt, 1'b0} | bdp:522-527; bp_cluster.sv:1152-1153 | IT_MAX_TGT_WIDTH LITERAL |
| History lengths | 4, 8, 13, 16, 32 | bdp:508 | |
| Fold widths idx/fh1/fh2 | IT1 4/4/4, IT2 8/8/8, IT3-5 9/9/8 | bdp:505-507 | GHR only |
| Index | PC[9:2] (IT1-2), PC[10:2] (IT3-5) XOR fold | ittage_table.sv:220-221 | |
| Tag | PC[15:8] (IT1-2), PC[17:9] (IT3-4), PC[19:9] (IT5) ^ fh1 ^ (fh2 << 1) | ittage_table.sv:225-227 | block start PC |
| Stage | p0 address, p1 read, p2 result | ittage_cntrl.sv:534-571 | p2 result masked in a cycle an update is granted (:570) |
| Provider / alt | longest / next-longest; alt when prm ctr == 0 and UAON >= 8 | ittage_cntrl.sv:164-276, 451-523 | |
| Allocation | on mispredict, one table above provider with u_eff 0, shortest first; written {tag, tgt, epoch, 0, 0, 1} | ittage_cntrl.sv:380-444, 832-854 | target replaced only when provider ctr == 0 (:798-824) |
| Training | at resolve; INDIRECT_NONRET and INDIRECT_CALL only | bp_cluster.sv:1742-1746, 1801-1803 | RETURN_CALL does not train |
| Queues | PQ 4, UQ 2; prediction wins; starvation 2 | bdp:540-546; ittage_arb.sv:88-202 | |

RAS:

| Feature | Value | Source | Notes |
|---|---|---|---|
| Speculative stack | 16 x 50: ret_addr 41, rctr 4, nos 4, bot 1 | bdp:555; ras.sv:115-125 | circular, flops |
| Commit stack | 32 x 41 (ret_addr only) | bdp:556; ras.sv:127-130 | |
| Recursion counter | 4 bits, saturates at 15, speculative stack only | ras.sv:89-90, 116, 413-421 | |
| Pointers | tosr, tosw, bos 4 each; csp 5; c_cnt 6 | ras.sv:132-140 | FTQ snapshot 12 bits (bsp:149-153) |
| Stage | p0 TOS read (used p1), p2 push/pop with same-cycle forwarding, p3 repair | ras.sv:23-31 | |
| Overflow / underflow (spec) | wrap with sentinel skip over BOS; pop of empty returns the commit top | ras.sv:423-451, 672-677 | |
| Overflow / underflow (commit) | call on full overwrites oldest; return on empty does nothing | ras.sv:731-764 | |
| Repair | pointer restore from FTQ snapshot; p3 undo/apply pass | ras.sv:531-651, 777-866 | ras_flush_* ports unused (RAS-3 OPEN) |

Global history (bp_history):

| Feature | Value | Source | Notes |
|---|---|---|---|
| GHR | 256-bit circular, 8-bit pointer | bdp:26, 28; bp_history.sv:79, 85 | |
| PHR | 32-bit circular, 5-bit pointer; path bit pc[2]^pc[3] | bp_history.sv:311 | exported as phr_buf; no fold built from it |
| Checkpoints | 64 x 15 bits | bp_history.sv:88-94 | |
| Folds | TAGE T1-T4, ITTAGE IT1-IT5, SC ST1-ST3; 458-bit bp_folded_hist_t | bp_history.sv:201-303; bsp:27-71 | tage_phr (32) never written |
| Update | at p1, one bit per predicted-path branch, up to 2 per cycle, every type | bp_cluster.sv:907-939 | |

### 2.3 Fetch target queue

| Feature | Value | Source | Notes |
|---|---|---|---|
| Depth | 64, all usable | bdp:30; ftq_ptr.sv:196, 247 | |
| Index / pointer | 6 / 7 bits (bit 6 wrap) | bdp:113, 118 | |
| Fast path entry bp_ftq_entry_t | 228: pc 41, pft_addr 41, branch_id 6, ras 12, ghist_ptr 8, phist_ptr 5, valid 1, 2 x bp_ftq_slot_t 57 | bsp:409-443 | slot: valid 1, target 41, br_type 3, taken 1, pos 4, pred_src 3, confidence 4 |
| Slow path bp_ftq_meta_t | 425 per slot (tage 79, sc 112, lp 80, ittage 147, ftb 7); 850 per entry | bsp:201-469; ftq_meta.sv:69 | union deferred (ftq_meta.sv:15-20, 85-92) |
| Status | 3 bits per entry: wb_rcvd, fault, gen | ftq_status.sv:104-106 | flops |
| Entry total | 1081 bits | derived 228 + 850 + 3 | |
| Fast path ports | 7 write (p1 alloc, p2 block, p2 slots, p3 slots, predecode, 2 resolve), 7 read (xlate, fetch, redirect, pdwb, commit, 2 resolve); combinational | ftq_entry.sv:212-222, 304-368 | same-index priority rsv > pd > p3 > p2 > alloc |
| Slow path ports | 2 write groups (p2, p3), 2 read (NUM_RESOLVE_PORTS) | ftq_meta.sv:74-112 | |
| Pointers | alloc, xlate, fetch (7 each); commit 7; ordering commit <= fetch <= xlate <= alloc | ftq_ptr.sv:29, 112-114; ftq_commit.sv:90 | |
| Shadow | 4 stages (1 comb + 3 reg); drops BPU responses for squashed or reallocated entries (6-bit index has no wrap bit) | ftq_shadow.sv:8-22, 183-221 | |
| Training | at resolve, 2 channels; commit drives only the RAS commit | ftq_resolve.sv:9-13; ftq_entry.sv:269-286 | |
| Update vs prediction | predictor readies ANDed across slots; younger channel on the same slot held; FTB scheduler issues 1/cycle with 1-deep skid; each FTB update withholds the p0 request 1 cycle (H3) | ftq_upd_conv.sv:114-138; ftq_resolve.sv:460-491; ftq_ftb_sched.sv:14-25, 178-327; ftq_npc.sv:306-309 | TAGE/ITTAGE/SC internal arbitration is in the cluster (see 2.2) |
| Prediction holds | queue full, FTQ full, live fault, FTB update next cycle, RAM init not ready | ftq_npc.sv:306-309 | |
| Redirect priority | reset > backend > predecode > p3 > p2 > p1 successor > hold | ftq_npc.sv:22-30, 303-364 | |
| Commit | 1 entry per cycle | ftq_commit.sv:227-240 | |
| Dropped: LOW FTB update over capacity | dropped at S5; HIGH (miss or mispredict) never dropped | ftq_ftb_sched.sv:152, 194-202, 270-279 | |
| Dropped: resolve outside live window | silently, ready = 1 | ftq_resolve.sv:366-370, 490 | |
| Not detected: resolve to a reallocated index | trains the new use; no generation bit | ftq_resolve.sv:123-132 | |
| Dropped: type mismatch (R2) / occupied-slot placement | TAGE, SC, LP, ITTAGE suppressed; uBTB, FTB still update (R2) | ftq_resolve.sv:436-454, 557 | |
| Dropped: stale BPU response, wrong-gen writeback, second writeback, RC_UNSPEC RAS commits | | ftq_shadow.sv:203-221; ftq_ifu.sv:368-369, 548-552; ftq_commit.sv:144, 215-216 | |
| Storage model | behavioral arrays, combinational read, no bw_ram | ftq_entry.sv:206; ftq_meta.sv:69 | |

### 2.4 Instruction fetch unit and instruction buffer

| Feature | Value | Source | Notes |
|---|---|---|---|
| Block per cycle | 1 prediction block (32 B, 16 halfwords) into F3 and the ibuf | ifu_f3.sv:380-382; bdp:173, 237 | window is 17 halfwords (34 B) so a 32-bit instruction at position 15 completes (ifu_fetch.sv:181, 445-456) |
| L1I request | 1/cycle, 64-B line; 2 lines when start_pc[5] = 1 | ifu_fetch.sv:281, 289-290, 310-322 | |
| Stages | translation ahead; F0 accept/L1I issue; F1 block queue; F2 halfword select; F3 expand, predecode, check, ibuf write; WB to FTQ | ifu.sv:11-25; ifu_fetch.sv:15-52 | |
| Block queue | 32 x 226 | ifu_fetch.sv:178, 188-211 | |
| Line buffer ifu_lbuf | 16 x 512 b (1 KB), L1I response landing and reorder store | ifu.sv:59; ifu_lbuf.sv:144 | not a loop buffer |
| Translation queue | 4 x 218; vpn = pc[VA_WIDTH-1:12]; page cross when pc[11:0] >= 12'hFE0 | ifu.sv:61; ifu_xlate.sv:76, 95, 144, 281 | LITERAL 12'hFE0 |
| Indexing order | translation completes before the L1I access; line PA = {ppn, start_pc[11:6]} | ifu_fetch.sv:282-284 | |
| Predecode | 16 positions, combinational in F3; Kogge-Stone start mask; br_type, is_rvc, is_call, is_ret, target (pc + imm for branch/JAL) | ifu_predecode.sv:63-122, 154-173 | runs on expanded encodings |
| RVC expander | 17 positions, in F3, before the ibuf; C, Zcd, Zcb, Zcmop; ibuf stores 32-bit words | ifu.sv:395-399; ifu_rvc_exp.sv:50, 294, 302-309; ifu_f3.sv:387 | |
| Hit path to ibuf | about 5 cycles (FTQ accept to ibuf read, hit, empty ibuf bypass) | derived by the sub-agent from ifu_fetch.sv, l1i_ctrl.sv, l1i_mshr.sv:398, ifu_lbuf.sv:194, ibuf.sv:140 | not stated in the RTL |
| ibuf depth | 64 | ibuf.sv:57 | |
| ibuf entry | ifu_pd_pkt_t, 190 bits | bsp:590-611 | instr 32, start_pc 41, pos 4, ftq_idx 6, fault fields, is_rvc, br_type, is_call, is_ret |
| ibuf write width | 16 slots with enable mask, compacted; whole block or nothing; ready when count <= 48 | ibuf.sv:65-66, 114, 127-137 | |
| ibuf read width | 8 per cycle; bypass when empty | ibuf.sv:58, 140, 156 | |
| ibuf clear | backend redirect only | ibuf.sv:41-47, 168 | the FTQ IFU flush does not reach it |

### 2.5 L1 instruction cache

| Feature | Value | Source | Notes |
|---|---|---|---|
| Size | 64 KB | l1i_pkg.sv:33 | LITERAL generator value |
| Line | 64 B | l1i_pkg.sv:34-35 | |
| Ways / banks / sets | 8 / 2 (by PA[6]) / 128 (64 per bank) | l1i_pkg.sv:36-39, 60-69 | |
| Index / tag | PIPT; offset [5:0], index [12:6] (bank [6], set [12:7]), tag [35:13] 23 bits | l1i_pkg.sv:46-69; ifu_fetch.sv:282, 312-314 | LITERALs |
| pa_bits | 36 | l1i_pkg.sv:32 | checked against PA_WIDTH only by lint target l1i_param_chk (l1i_param_chk.sv:34, 68) |
| Replacement | tree-PLRU 7 bits per set; lowest invalid way first | l1i_pkg.sv:189-201; l1i_ctrl.sv:226, 268-271 | |
| MSHRs | 16, 4 targets each; prefetch reserve 2 | l1i_pkg.sv:104-113 | entry 578 bits (l1i_mshr.sv:164-177) |
| Hit latency | 2 cycles | l1i_pkg.sv:122 L1iReadLatency; l1i_ctrl.sv:17-23 | |
| Throughput | 1 request and 1 response per cycle; one slave port | l1i.sv:94; l1i_mshr.sv:372-399 | |
| Refill path | TileLink TL-UH Get, a_size 6 (LITERAL), source = MSHR index | l1i_mem_mst.sv:16, 81, 95; cgen_tl_pkg.sv:15 | |
| Refill width | 256-bit beat, 2 beats per line; 16 x 512 refill buffers | l1i_pkg.sv:92-94; l1i_mem_mst.sv:18-20, 117-119 | denied/corrupt line not installed |
| Uncached path | forced miss, no PLRU update, not installed; issued only at commit_ptr; full 64-B Get; F3 delivers the first instruction only | l1i_ctrl.sv:40-47, 228-230; l1i_mshr.sv:44-62; ifu_fetch.sv:278; ifu_f3.sv:94-114 | |
| Maintenance | FENCE.I clears all valids and PLRU in one cycle; cbo.inval clears every way of the set; drain first | ifu_maint.sv:58-99; l1i_maint.sv:57-103 | |

### 2.6 MMU: ITLB, page table walker, PMP

| Feature | Value | Source | Notes |
|---|---|---|---|
| ITLB entries | 64 | itlb.sv:160 ITLB_ENTRIES | LITERAL module parameter |
| Associativity | fully associative, first hit wins | itlb.sv:400-411 | |
| Page sizes | 4 KiB, 64 KiB (Svnapot), 2 MiB, 1 GiB in one array | itlb.sv:247-250, 321-329 | |
| Entry | 99 bits: val, v, g, asid 16, vmid 14, vpn 29, size 3, ppn 24, perm 8, pbmt 2 | itlb.sv:292-303 | entry holds final PA of a two-stage translation |
| Replacement | lowest invalid; else rotating victim skipping MRU | itlb.sv:608-621, 669-676 | |
| Lookup latency | 1 cycle (registered request, combinational compare) | itlb.sv:47-49, 387, 644 | |
| Flush | SFENCE/SINVAL.VMA, HFENCE/HINVAL.VVMA, HFENCE/HINVAL.GVMA (by VMID), all | itlb.sv:129-150, 623-641 | |
| L2 TLB / PWC | none | ptw.sv:10-13 | |
| satp / vsatp modes | Bare, Sv39 | csr_pkg.sv:103-104; ptw.sv:750-751, 768 | any non-zero MODE walked as Sv39 |
| hgatp modes | Bare, Sv39x4 | csr_pkg.sv:106-107; ptw.sv:622-627 | |
| Two-stage | VS+G, G only, VS only | ptw.sv:21-42 | |
| Walks in flight | 1; a request during a walk gets RETRY | ptw.sv:17-19, 645, 733-736 | |
| Memory port | valid/ready request: op READ or CAS, paddr [PA_WIDTH-1:0], cmp/swap 64; response val, data 64, err; one outstanding | ptw.sv:190-199, 847-857 | what it connects to: not found in listed files |
| A/D update | ADUE = 1: Svadu, one CAS, restart on mismatch; ADUE = 0: Svade page fault; menvcfg/henvcfg.ADUE by stage | ptw.sv:535-538, 600-603, 754-756, 879-896 | reset ADUE 0 (csr_pkg.sv:209-210) |
| Svnapot | 64 KiB only | ptw.sv:284, 527-529 | |
| PMP entries | 16 | pmp_pma_chk.sv:79; csr_pkg.sv:59 | |
| PMP modes | OFF, TOR, NAPOT; NA4 matched as NAPOT | pmp_pma_chk.sv:131-133, 196-202 | Smepmp not implemented (:45) |
| PMP grain | 4 KiB, G = 10 | pmp_pma_chk.sv:80, 117; csr_pkg.sv:60 CSR_PMP_G (LITERAL) | |
| PMA | 1 region 0x0_8000_0000 to 0xF_FFFF_FFFF, attr 1111; default 0000 | pmp_pma_chk.sv:81-87; itlb.sv:164-170; ptw.sv:158-164 | LITERAL 36-bit constants in 3 files |

### 2.7 Decode

| Feature | Value | Source | Notes |
|---|---|---|---|
| Width | 8 | decode_pkg.sv:21 SLOTS | one combinational module, for-loop over SLOTS calling decode_one and decode_vec_one (instr_decoder.sv:2061-2096) |
| Compressed | expanded in the IFU; decoder sees 32-bit words | instr_decoder.sv:30-35 | |
| Extensions | RV64I, M, A, F, D, Zfhmin, Zfa, Zicsr, Zifencei, Zicbom, Zicboz, Zicbop (as ORI), Zba, Zbb, Zbs, Zicond, Zimop, Zawrs, Zihintpause (as FENCE), Svinval, H, V, Zvbb, Zvfhmin | instr_decoder.sv (lines per sub-agent: 224-962, 987-1252, 1277-1300, 1344-1433, 1455-1527, 1579-2010) | illegal by design: Zfh, Q, Zacas, Zabha, Zicfiss, Zvfbfmin |
| Scalar output | decode_pkt_t, 133 bits (valid, instr, opcode, rd/rs1/rs2/rs3, funct3/7, imm 32, fmt, alu_op 8, flags, fp fields, is_hlsv, is_hlvx) | decode_pkg.sv:279-311 | |
| Vector output | vec_decode_pkt_t, 46 bits incl. is_vsetvl, needs_vtype | decode_pkg.sv:640-678 | |
| Other per slot | is_vector, vtype_hazard, pd_out (ifu_pd_pkt_t 190, passed through) | instr_decoder.sv:109-115, 2093-2094 | vtype_hazard = prefix OR of earlier is_vsetvl AND needs_vtype |

### 2.8 SRAM arrays and storage

bw_ram (bw_ram.sv:45-90): one address port (1RW), 1-cycle read
(registered address, combinational dout), active-low bit write enable,
no reset. sram_init (sram_init.sv:47-86): PENDING 1 cycle, DELAY
START_DELAY cycles, INIT one write per cycle; ready after
1 + START_DELAY + NUM_ENTRIES cycles from reset release. START_DELAY is
0 in every instance.

| Array | Module | Count | Depth x width | Ports | Read latency | Write enable | Reset / init | Model |
|---|---|---|---|---|---|---|---|---|
| T0 | tage_bim | 2 (per slot) | 2048 x 2 (2 banks x 1024) | 1RW | 1 | bit | sram_init walk value 2, shared with T1-T4: 2049 cycles | bw_ram |
| T1-T4 | tage_table | 8 | 2048 x 16 | 1RW | 1 | bit (per field) | walk value 0, 2049 cycles; +TAGE_FAST_INIT | bw_ram |
| ST0-ST3 | sc_table | 8 | 512 x 6 | 1RW | 1 | bit (whole word used) | walk 1024 entries, 1025 cycles (each 512-row RAM written twice); +SC_FAST_INIT | bw_ram |
| ST4 | sc_brimli | 2 | 1024 x 6 | 1RW | 1 | bit | same walk, 1025 cycles | bw_ram |
| IT1-IT2 | ittage_table | 4 | 256 x 56 | 1RW | 1 | bit | walk 512 entries, 513 cycles (IT1-2 written twice); +ITTAGE_FAST_INIT | bw_ram |
| IT3-IT4 | ittage_table | 4 | 512 x 57 | 1RW | 1 | bit | 513 cycles | bw_ram |
| IT5 | ittage_table | 2 | 512 x 59 | 1RW | 1 | bit | 513 cycles | bw_ram |
| FTB data | ftb_array | 1 | 512 x 452 (4 x 113) | 1R1W | 0 (comb) | way slice | none, not initialized | inline behavioral array |
| FTB valid / PLRU | ftb_plru | 1 | 512 x 4 / 512 x 3 | 1R + 2W | 0 | bit / set | sync reset | flops |
| uBTB | ubtb | 1 | 64 x 4 x 107 | comb R + 2W | 0 | entry | async reset of valid and wr_ptr | flops |
| Loop | loop_pred | 2 | 64 x 4 x 68 | up to 4R 4W | 0 | entry | async reset | flops |
| RAS spec / commit | ras | 1 | 16 x 50 / 32 x 41 | comb R + 8W / 1W | 0 | entry | sync reset | flops |
| FTQ fast | ftq_entry | 1 | 64 x 228 | 7W 7R | 0 | field | valid reset only | behavioral array |
| FTQ slow | ftq_meta | 1 | 64 x 850 | 2W 2R | 0 | member | none | behavioral array |
| FTQ status | ftq_status | 1 | 64 x 3 | masked | 0 | bit | reset 0 | flops |
| Line buffer | ifu_lbuf | 1 | 16 x 512 | 1W 2R | 0 | slot | none | flops |
| Block queue | ifu_fetch | 1 | 32 x 226 | 1W 1R | 0 | entry | pointers only | flops |
| Translation queue | ifu_xlate | 1 | 4 x 218 | 1W 1R | 0 | entry | pointers only | flops |
| ibuf | ibuf | 1 | 64 x 190 | 16W 8R | 0 + bypass | entry | none | flops |
| L1I data | l1i_data_array | 2 (bank) | 8 x 64 x 512 | 1R (8 ways) 1W | 1, registered | whole line | none | inline behavioral array |
| L1I tag | l1i_meta_array | 2 | 8 x 64 x 23 | 1R 1W | 1 | way | none | inline behavioral array |
| L1I valid | l1i_meta_array | 2 | 8 x 64 x 1 | 1R 1W + clear | 1 | bit | async reset clear, no walk | flops |
| L1I PLRU | l1i_meta_array | 2 | 64 x 7 | 1R 2W | 1 | set | async reset 0 | flops |
| MSHR data | l1i_mshr | 1 | 16 x 512 | | 0 | | reset 0 | flops |
| Refill buffer | l1i_mem_mst | 1 | 16 x 512 | | 0 | | reset 0 | flops |
| ITLB entries | itlb | 1 | 64 x 99 | 1W + valid clear; parallel compare | 0 from registered request | entry | async reset | flops |
| ITLB tracker | itlb | 1 | 4 x 128 (1 used, WALK_DEPTH 1) | | | | reset 0 | flops |

Only the TAGE, SC and ITTAGE tables use bw_ram and sram_init. No byte
write enable exists anywhere; bw_ram is bit-enable.

### 2.9 Storage totals

Entries times stored entry width, as built: TAGE, SC, ITTAGE and the
loop predictor are built once per prediction slot, so twice at the
default NUM_PRED_SLOTS 2, and copy s is trained only by slot s's
update channel. Per slot, TAGE + SC + loop is 20.88 KB. History, the
FTB PLRU, queues and control registers are not counted. The PERF-001
column is that task's figure, which counted one copy.

| Unit | Counts | Bits | KB | PERF-001 | Differs |
|---|---|---|---|---|---|
| TAGE | 2 slots x (T0 2048 x 2 + T1-T4 4 x 2048 x 16) | 270336 | 33.00 | 135168, 16.50 | yes: x2 slots |
| SC | 2 x (4 x 512 x 6 + 1024 x 6) | 36864 | 4.50 | 18432, 2.25 | yes: x2 |
| ITTAGE | 2 x (2 x 256 x 56 + 2 x 512 x 57 + 512 x 59) | 234496 | 28.63 | 117248, 14.31 | yes: x2 |
| Loop | 2 x 256 x 68 | 34816 | 4.25 | 17408, 2.13 | yes: x2 |
| FTB | 2048 x 114 (incl. valid) | 233472 | 28.50 | 233472, 28.50 | no |
| uBTB | 256 x 107 | 27392 | 3.34 | 27392, 3.34 | no |
| RAS | 16 x 50 + 32 x 41 | 2112 | 0.26 | 2160, 0.26 | bits differ: no rctr in commit stack (-128), nos + bot in spec (+80) |
| All predictors | sum of the above | 839488 | 102.48 | 551280, 67.29 | yes |
| TAGE + SC + loop | | 342016 | 41.75 | 171008, 20.88 | yes |

Settled widths: TAGE/ITTAGE EPC 2 bits (tage_table.sv:106-110,
ittage_table.sv:15-21); valid 1 bit per tagged entry (tage_table.sv:48,
103; ittage_table.sv:16); RAS rctr 4 bits, speculative stack only
(ras.sv:115-130).

Not in the predictor totals: FTB PLRU 1536; uBTB wr_ptr 128; loop
checkpoints 2 x 64 x 39 = 4992; RAS pointers 23; bp_history GHR + PHR
288, checkpoints 960, folds 458; TAGE UAON/aging/epoch 38 per slot; SC
control 60; arbitration queues.

Other units:

| Unit | Counts | Bits | KB |
|---|---|---|---|
| FTQ | 64 x (228 fast + 850 slow + 3 status) | 69184 | 8.45 |
| ibuf | 64 x 190 (r_arr, valid included; excludes 19 pointer bits) | 12160 | 1.48 |
| L1I data | 2 x 8 x 64 x 512, line data only | 524288 | 64.00 |
| L1I tag | 2 x 8 x 64 x 23 | 23552 | 2.88 |
| L1I tag + valid + PLRU | 23552 + 1024 + 896 | 25472 | 3.11 |
| ITLB | 64 x 99, r_ent only | 6336 | 0.77 |
| ITLB with tracker and control | 6336 + 512 + 43 (6507 live at WALK_DEPTH 1) | 6891 | 0.84 |

Also present: IFU line buffer 8192 (1.00 KB), block queue
7232, translation queue 872; L1I MSHR 9248, refill buffers 8192.

---

## 3. Variants

None yet. An extended-address variant (Sv57) is the first planned.

---

## 4. Document History

```
  2026-11-10  session-084. Created (Jeff): section 1 with Svadu;
              section 2 to be filled from DOC-016.
  2026-11-10  session-084, after DOC-016. Section 2 filled from
              DOC-016's report.
```
