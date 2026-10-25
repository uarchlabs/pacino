<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd07_calls_returns: Calls and Returns
```
 FILE:    fd07_calls_returns.md
 SOURCE:  DOC-002, DOC-006, DOC-007
 STATUS:  WORKING
 UPDATED: 2026-10-19
 CONTACT: Jeff Nye
```

`fd07_calls_returns` is the FD-7 demonstration scenario. It is a demo,
not a verification test. Each of 8 passes makes nested calls, a
recursion four calls deep from one call site, and a coroutine switch by
two return-calls. The return address stack (RAS) pushes and pops at p2,
compresses the recursion into a count on one entry, and supplies return
targets. The run passes if a retired return took its correct target
from the RAS, a recursion count above 1 was seen, and a p2 RETURN_CALL
operation occurred.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd07_calls_returns: PASS, returns predicted by the RAS 64, p2 pushes 85,
    p2 pops 125, p2 return-calls 16, highest recursion count 4, cyc 694
```

---

## 1. The program

Source: `programs/fd07_calls_returns.svh`, task `prog_fd07` (line 23).
Function addresses from the source (`RESET_VECTOR` 0x8000_0000):
f1 0x8000_0500, f2 0x8000_0600, f 0x8000_0800, B 0x8000_0A00. The
loop top is 0x8000_0008. One pass:

```
main   mixed(2); jal x1,f1              call
f1     mixed(2); jal x1,f2              call (nested)
f2     mixed(2); ret                    return to f1
f1     mixed(1); ret                    return to main
main   mixed(1); jal x1,f               call from main
f+0    mixed(2)                         6 bytes
f+6    bne x6,x0,f+16                   taken only at the bottom (n == 0)
f+10   jal x1,f                         recursive call, link f+14
f+14   c.addi                           after each recursive return
f+16   ret                              5 returns per pass
main   mixed(1)
L      jal x5,B                         call through x5, link L+4
B      mixed(2)
B1     jalr x1,0(x5)                    RETURN_CALL: to L+4, link B1+4
L+4    mixed(2)                         "A"
A1     jalr x5,0(x1)                    RETURN_CALL: to B1+4, link A1+4
B1+4   mixed(2)
B2     jalr x0,0(x5)                    RETURN: to A1+4
A1+4   mixed(1); bne x6,x0,top          back edge, taken on passes 0..6
```

- Branch types are the writer's
  (`rtl/core/frontend/fe_top/tb/models/fe_tb_writer.svh`): `jal` with
  rd x1 or x5 is `DIRECT_CALL` (lines 273 and 274); `jalr_to` (line 389) types a
  jalr by the RAS hint rule: rd and rs1 both link and unequal is
  `RETURN_CALL`, rd link a call, rs1 link a return.
- Per pass the program retires 8 direct calls (f1, f2, f, f four times,
  B), 8 returns (f2, f1, f five times, B2) and 2 return-calls (derived
  from the source). Eight passes give 80 retired calls plus
  return-calls, and 80 retired returns plus return-calls.
- `emit_rec` (`fe_tb_writer.svh:556`) writes the recursion; `emit_nest`
  (line 543) the nesting.

---

## 2. Why the program produces the behavior

The RAS is `rtl/core/frontend/bpu/rtl/ras.sv`.

1. Push and pop at p2. A slot of the p2 group is presented to the RAS
   when it holds a branch of a valid block and no earlier slot of the
   block is taken (`w_ras_pred_val_p2` in
   `rtl/core/frontend/bpu/rtl/bp_cluster.sv:1090`). The RAS pushes
   the fall-through on a call and pops on a return; a RETURN_CALL pops
   and then pushes (`ras.sv:24-27`, `ras.sv:253-255`).
2. Recursion compression. The p2 push is made with recursion allowed
   (`st_push(..., 1'b1)`, `ras.sv:705`). When the pushed address equals
   the current top, the top entry's count `spec_rctr` is incremented and
   TOSR does not move (`ras.sv:413-421`); a pop of an entry with a
   non-zero count decrements the count and leaves TOSR (`st_retract`,
   `ras.sv:334-343`). The recursive call at f+10 always pushes f+14, so
   every recursive call after the first matches the top.
3. Return targets. At p1 a uBTB slot of type RETURN or RETURN_CALL with
   a valid top of stack takes the RAS address and `pred_src = PRED_RAS`
   (`bp_cluster.sv:839-844`). At p2 a return slot takes
   `w_ras_pop_addr_p2` and `PRED_RAS` when the pop is valid
   (`bp_cluster.sv:1164-1169`).
4. The commit stack. Retired calls and returns update a separate commit
   stack (`csp`, `commit_top_addr`; `ras.sv` header, lines 18-21), the
   fallback for a pop of an empty speculative stack.

From the run (out/fd07_calls_returns/fd07_calls_returns.fst,
`u_ras.spec_rctr`): the count of entry 1 reads 1 from cyc 131, 2 from
133, 3 from 135 and 4 from 137, one step every two cycles, and holds 4
until cyc 374; entry 4 does the same from cyc 267 (4 at 273) and holds
4 until cyc 405. Four later episodes reach 3: entry 3 at cyc 392 to
400, entry 2 at 525 to 533, entry 9 at 581 to 589 and entry 0 at 637 to
645. In four short ones (entries 11, 12, 10 and 11, from cyc 325 to
477) the count reaches 1 and returns to 0 within six cycles.

---

## 3. What the monitor counts

At retirement (`tb/fe_demo_mon.svh:306-310`):

```
n_ras_ret_ok   a retired RETURN or RETURN_CALL whose FTQ entry's final
               slot at its position is valid, has pred_src == PRED_RAS,
               is taken, and has the expected target
```

Every cycle at p2 (`tb/fe_demo_mon.svh:464-487`), summed over the slots:

```
n_ras_push     w_ras_pred_val_p2[s] with w_br_type_p2[s] a call
               (DIRECT_CALL, INDIRECT_CALL, RETURN_CALL)
n_ras_pop      w_ras_pred_val_p2[s] with RETURN or RETURN_CALL
n_rc_p2        w_ras_pred_val_p2[s] with RETURN_CALL
max_rctr       the highest u_ras.spec_rctr[i] over all entries
```

The proof (`tb/fe_demo_proofs.svh:79`) is
`n_ras_ret_ok > 0 && max_rctr > 1 && n_rc_p2 > 0`. `tb_fe_demo.sv:160`
also requires the whole stream to retire with no errors.

---

## 4. Reading the numbers

- `returns predicted by the RAS` counts retired returns, at most 80 here
  (section 1). 64 had their target from the RAS in the entry's final
  slot.
- `p2 pushes`, `pops` and `return-calls` count p2 operations presented
  to the RAS, not retired instructions. `w_ras_pred_val_p2` is not gated
  by the squash (`ras_p2_keep`, `bp_cluster.sv:1394-1395` and line
  2027), so
  operations of blocks squashed in the same cycle and of predicted paths
  later redirected are included, and an operation is missing for a
  call or return the p2 group did not hold (before the FTB learned it).
  Pops (125) exceed the 80 retired returns plus return-calls; pushes
  (85) exceed the 80 retired calls plus return-calls.
- The sums are per slot (DOC-002). On the one-slot model a cycle holds
  at most one RAS operation.
- `highest recursion count 4`. On the correct path the program's
  recursion gives 3: four recursive calls give one allocation and three
  increments. 4 is reached in the first two episodes of section 2; the
  four later episodes reach 3. The source of
  the extra increment was not traced. On the two-slot model the same
  program reaches 10 (DOC-007 run).
- Departures from FD-7 in `planning/showcase/fe_demo_scenarios.md`: the
  spec's "a tail return-call" is built as a coroutine switch by two
  RETURN_CALLs (jalr x1,0(x5) and jalr x5,0(x1)), not a tail call. The
  proof adds `n_rc_p2 > 0` to the spec's two conditions.

---

## 5. Waveform

The saved view is `waves/fd07_calls_returns.sucl`, which `make view
S=fd07_calls_returns` opens in Surfer. Look at:

- `u_ras.tosr`, `tosw`, `bos`: TOSR and TOSW step on each push, TOSR
  follows the link on a pop.
- `u_ras.spec_rctr.[i]` and `spec_ret_addr.[i]` (entries 0-3 in the
  command file): the count of entry 1 rising to 4 at cyc 131 to 137.
- `w_br_type_p2.[0]` `RETURN_CALL` with `w_ras_pred_val_p2.[0]`: the
  coroutine switches.
- `bpu_slot_p2.[0].pred_src` `PRED_RAS` on return slots.
- ras_commit group: `ras_commit_val`, `csp`, `commit_top_addr` change
  as calls and returns retire.
