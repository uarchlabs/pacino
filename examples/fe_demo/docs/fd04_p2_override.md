<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd04_p2_override: p2 Override
```
 FILE:    fd04_p2_override.md
 SOURCE:  DOC-002, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

`fd04_p2_override` is the FD-4 demonstration scenario. It is a demo, not
a verification test. It runs a chain of eight blocks that all index one
uBTB set, which has four ways, while each has its own FTB set. The uBTB
cannot hold the chain, so at p1 most blocks miss and are predicted to
fall through; at p2 the FTB knows the taken branch, the successors
differ, and the cluster raises a p2 redirect. The run passes if the FTQ
accepts at least one p2 redirect.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd04_p2_override: PASS, p2 redirects 77, cyc 527
```

---

## 1. The program

Source: `programs/fd04_p2_override.svh`, task `prog_fd04` (tb_fe_top's
ftbonly). `b[k] = RESET_VECTOR + 0x1000 + k * 0x800`, k = 0..7, so b[0]
is 0x80001000 and b[7] is 0x80004800.

```
RESET_VECTOR+0   mixed(3)                                  8 bytes
RESET_VECTOR+8   jal x0,b[0]

b[k], k < 7      c.addi, addi                              6 bytes
b[k]+6           bne x6,x0,b[k+1]     always taken        pos 3

b[7]             c.addi
b[7]+2           bne x6,x0,b[7]+10    taken on the last pass only
b[7]+6           jal x0,b[0]          passes 0..14 (written dry on
                                      the last pass)
b[7]+10          mixed(3)
b[7]+18          jal x0,0             halt (demo_go -> W.halt)
```

- 16 passes over the chain. The code is the same every pass; on the
  last, b[7]'s conditional exits and `d_jal_fill`
  (`fe_tb_writer.svh:530-541`) writes the back-edge JAL in dry mode so
  the bytes stay the same but it is not in the expected stream.
- Outcomes come from the writer (`bcc`, `fe_tb_writer.svh:412-421`).

---

## 2. Why the program produces p2 redirects

1. One uBTB set. The uBTB index is `pc[10:5]`
   (`rtl/core/frontend/bpu/rtl/ubtb.sv:110-114`, `UBTB_IDX_BITS = 6`,
   `UBTB_OFFSET_BITS = 5`, `bp_defines_pkg.sv:305, 315`). Every b[k] is
   a multiple of 0x800, so all eight map to set 0, which has
   `UBTB_WAYS = 4` (`bp_defines_pkg.sv:298`). An update that misses
   takes the way named by the set's round-robin `wr_ptr`
   (`ubtb.sv:460-462`), so at most four of the eight blocks are held
   at a time.
2. Eight FTB sets. The FTB set index is `pc[13:5]`
   (`ftb_cntrl.sv:574`, `FTB_IDX_BITS = 9`, `bp_defines_pkg.sv:174`).
   The eight blocks fall in sets 0x080, 0x0C0, 0x100, 0x140, 0x180,
   0x1C0, 0x000 and 0x040 (derived from the addresses), so the FTB
   holds all of them.
3. p1 on a uBTB miss predicts fall-through: `w_pft_p1` is the lookup PC
   plus 32 (`bp_cluster.sv:868-870`).
4. p2 comparison. `bp_cluster.sv:1185-1187`: a reachable slot s
   redirects when the FTB answered (`w_ftb_valid_p2`) and its p2
   successor `w_succ_p2[s]` differs from the p1 successor carried in
   `r_succ_p1_p2[s]`. For b[k] the FTB successor is b[k+1] and the p1
   successor is b[k] + 0x20.
5. FTQ acceptance and the new request. `ok_redir_p2`
   (`ftq_shadow.sv:211-212`) requires the stage-2 shadow valid and
   pointer match; `ftq_npc.sv:349-355` (arm 4) then takes the p2
   redirect PC as the next p0 request.

From the FST, the 77 accepted p2 redirects, by block and target:

```
block        target       count   uBTB at p1
0x80001000   0x80001800   16      miss
0x80001800   0x80002000   15      miss
0x80002000   0x80002800   15      miss
0x80002800   0x80003000   14      miss
0x80004800   0x80004806   12      hit
0x80004800   0x8000480A    1      hit
0x80004806   0x80001000    1      hit
0x8000480A   0x8000482A    3      hit
```

60 follow a uBTB miss; 17 follow a uBTB hit whose successor the FTB
answer differs from (b[7] and the blocks after it). "uBTB at p1" is
`r_ubtb_blk_p1.hit` the cycle before, for the same lookup PC. b[4] to
b[6] raise no p2 redirect in this run.

The 12 redirects from b[7] to 0x8000_4806 are the cut of
`fe_decisions.md` 10 (BP-138). b[7] holds a conditional at position 1
and the jal at position 3; with one slot, the slot holds the
conditional and the jump is in no slot. The FTB answer then ends the
block at the jump's PC, `bpu_blk_pft_p2` 0x8000_4806 with
`w_jmp_cut_p2` set (`bp_cluster.sv` lines 1044 to 1047 and 1107 to
1108). The uBTB's p1 answer for b[7] has the conditional not taken and
the fall-through 0x8000_480A, past the jump, so the two successors
differ and p2 redirects to the jump's PC. The next block starts at the
jump and predicts it in slot 0.

---

## 3. What the monitor counts

The count comes from `tb/fe_demo_mon.svh:420-431`, taken inside the
`meas` window.

```
n_redir_p2   u_ftq.w_ok_redir_p2 && (bpu_redir_p2[0].valid
             || bpu_redir_p2[1].valid)
             a cycle in which the FTQ accepted a p2 redirect
```

The proof (`tb/fe_demo_proofs.svh:60-63`) is `n_redir_p2 > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

---

## 4. Reading the numbers

- `p2 redirects 77` counts cycles in which the FTQ accepted a p2
  redirect. On the two-slot model a cycle with both slots redirecting
  counts once; on this model a cycle has one slot.
- The miss counts are uneven across the chain (16, 15, 15, 14 for b[0]
  to b[3], none for b[4] to b[6]): which four blocks the set holds at a
  given time depends on the round-robin pointer and the order of
  updates. The figures are from this run.
- Departure from `planning/showcase/fe_demo_scenarios.md` FD-4: its
  program is "a branch whose uBTB entry is stale while its FTB entry is
  current". As built, the mechanism is uBTB capacity: eight blocks in
  one four-way set, so most redirects follow a uBTB miss, not a stale
  hit. 17 of the 77 do follow a hit, 12 of them the cut at b[7]. The
  proof is FD-4's.

---

## 5. Waveform

The saved view is `waves/fd04_p2_override.sucl`, which `make view
S=fd04_p2_override` opens in Surfer. Look at:

- group `bp_cluster_p1_ubtb`: a p1 block with `r_ubtb_blk_p1.hit` low
  and `bpu_pred_pft_p1` the lookup PC + 0x20.
- group `bp_cluster_p2_ftb`: one cycle later `r_val_p2` and
  `w_ftb_valid_p2`, slot 0 a taken conditional at `pos` 3, and
  `bpu_redir_p2.[0].valid` with `target_pc` the next b[k].
- group `ftq`: `w_ok_redir_p2` accepting it, `w_redir_val` and
  `w_redir_idx`.
- group `bp_cluster_p0`: the next `ftq_pred_pc_p0` is the redirect
  target.
