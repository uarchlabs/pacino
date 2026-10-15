<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd08_indirect: Indirect Jump
```
 FILE:    fd08_indirect.md
 SOURCE:  DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd08_indirect` is the FD-8 demonstration scenario. It is a demo, not a
verification test. Each of 40 passes runs an indirect jump and an
indirect call whose targets alternate between two addresses from pass
to pass. Each is preceded by a conditional whose direction alternates
with it, so global history tells the two cases apart. The FTB holds one
target per jump; ITTAGE learns both targets under their histories and
supplies the right one at p2. The run passes if at least one retired
indirect took its correct target from ITTAGE.

A recorded run:

```
DEMO PASS fd08_indirect: indirect targets predicted by ITTAGE 67
(cycles 1121)
```

---

## 1. The program

Source: `programs/fd08_indirect.svh`, task `prog_fd08` (line 19).
Addresses derived from the source (`RESET_VECTOR` 0x8000_0000); `odd` is
pass number mod 2:

```
top = 0x8000_0008   c.addi
top+2       A:      bne x6,x0,top+8    taken when odd; skips one c.addi
top+8       J:      jalr x0,0(x7)      to ta (odd) or tb (even)
ta = 0x8000_0400    mixed(2); jal x0,jn
tb = 0x8000_0480    mixed(1); jal x0,jn
jn = 0x8000_0500    c.addi
jn+2        C:      bne x6,x0,jn+8     taken when even
jn+8        K:      jalr x1,0(x28)     call fa (odd) or fb (even)
fa = 0x8000_0600    mixed(2); ret
fb = 0x8000_0680    mixed(1); ret
jn+12               c.addi
jn+14               bne x6,x0,jn+22    taken on the last pass (exit)
jn+18               jal x0,top         back to top on passes 0..38
```

- The writer decides every outcome and target (`bcc`, `jalr_to`,
  `rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh:412` and
  `:389`). `jalr_to` writes `jalr rd, 0(rs1)`, the same encoding every
  pass (`enc_jalr`, line 345); the backend retires against the expected
  stream, so x7 and x28 are never read.
- J is `INDIRECT_NONRET` (neither register a link) and K is
  `INDIRECT_CALL` (rd x1), by the type rule of `jalr_to`
  (`fe_tb_writer.svh:396-401`). The `ret` in fa and fb is a RETURN,
  predicted by the RAS.
- `exit_or_jal` (`fe_tb_writer.svh:615`) writes the loop exit.
- 40 passes give 80 retired indirects: J and K retire 40 times each,
  20 times to each of their two targets (derived from the source).

---

## 2. Why the program produces the behaviour

1. The FTB jump slot holds one target per jump (`jmp.tgt`, written from
   `ftb_upd_jmp_target_u0`,
   `rtl/core/frontend/bpu/rtl/ftb_cntrl.sv:552`). A target that changes
   every pass is wrong at p2 whenever the FTB target is the one used.
2. ITTAGE takes the folded global history (`folded_hist`,
   `rtl/core/frontend/bpu/rtl/ittage.sv:53-54`). A and C alternate
   in step with the targets, so the history at J and at K differs
   between odd and even passes and the two targets fall in different
   entries.
3. Allocation. A target mispredict allocates when the provider is not
   the last table and a candidate exists (`alc_upd`,
   `rtl/core/frontend/bpu/rtl/ittage_cntrl.sv:832-850`); the new entry
   holds the resolved target.
4. Selection at p2. For an `INDIRECT_NONRET` or `INDIRECT_CALL` slot the
   cluster takes the ITTAGE target when ITTAGE answered for this entry
   with a tagged hit (`it_hit`,
   `rtl/core/frontend/bpu/rtl/bp_cluster.sv:1087-1089`), primary or
   alternate target by `ittage_using_primary` (lines 1090-1092), and
   records `pred_src = PRED_ITTAGE`; otherwise the FTB jump target and
   `PRED_FTB` (lines 1110-1113). `ittage_hit` is the primary-table hit
   (`ittage_cntrl.sv:557`).

---

## 3. What the monitor counts

At retirement (`tb/fe_demo_mon.svh:273-278`):

```
n_itt_ok   a retired INDIRECT_NONRET or INDIRECT_CALL whose FTQ entry's
           final slot at its position is valid, has
           pred_src == PRED_ITTAGE, is taken, and has the expected
           target
```

The final slot is the last group the FTQ accepted for the entry, p1 then
p2 then p3 (`fin_log`, `tb/fe_demo_mon.svh:232-241`).

The proof (`tb/fe_demo_proofs.svh:70`) is `n_itt_ok > 0`.
`tb_fe_demo.sv:144` also requires the whole stream to retire with no
errors.

---

## 4. Reading the numbers

- 67 of the 80 retired indirects had their right target from ITTAGE.
  The other 13 include the first executions of each, before ITTAGE has
  allocated; their sources were not traced one by one.
- A target from ITTAGE that is wrong is not counted, and neither is one
  that reached the entry's final slot from another predictor.
- Departure from FD-8 in `planning/showcase/fe_demo_scenarios.md`: the
  spec's program is "an indirect jump through a table with a repeating
  target pattern". The build has no table: an indirect jump and an
  indirect call whose targets alternate, each after a conditional that
  alternates with it (tb_fe_top `indir`). The proof matches the spec.

---

## 5. Waveform

The saved views are `waves/fd08_indirect.gtkw` (`make view
S=fd08_indirect`) and `waves/fd08_indirect.sucl` (`make sview
S=fd08_indirect`). Look at:

- `w_ittage_pred_rdy_p2` with `w_ittage_pred_meta_p2.[s].ittage_hit`
  set and `ittage_prm_tgt` (VA[40:1]) alternating between the two
  targets of the slot.
- `bpu_slot_p2.[s]`: on the jump's slot, `pred_src` 5 (`PRED_ITTAGE`)
  and `target` 0x8000_0400 / 0x8000_0480 for J, 0x8000_0600 /
  0x8000_0680 for K.
- `bpu_redir_p2.[s]` with `w_ok_redir_p2`: a p2 redirect, the p2
  target differing from the block's p1 prediction.
