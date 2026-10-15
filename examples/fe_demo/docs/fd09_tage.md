<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd09_tage: TAGE Provider, Allocation and use_alt_on_na
```
 FILE:    fd09_tage.md
 SOURCE:  DOC-001, DOC-002
 STATUS:  WORKING
 UPDATED: 2026-10-15
 CONTACT: Jeff Nye
```

`fd09_tage` is the FD-9 demonstration scenario. It is a demo, not a
verification test. It runs a loop around one conditional branch that the
predictors cannot learn. That branch causes TAGE to allocate entries, and
the allocated entries train the `uaon` counter until use_alt_on_na hands
the prediction to T0. The run passes if both events happen at least once.

A recorded run (DOC-002, after the monitor fix):

```
DEMO PASS fd09_tage: tagged-provider predictions 216; allocations 65;
T0 by use_alt_on_na 37 (cycles 1277)
```

---

## 1. The program

Source: `programs/fd09_tage.svh`, task `prog_fd09`.

```
RESET_VECTOR+0   mixed(3)           c.addi, addi, c.addi        8 bytes
top = +8         mixed(2)           c.addi, addi                6 bytes
top+6    B:      bne x6,x0,top+12   taken when tk               (cskip)
top+10           c.addi             skipped when B is taken
top+12           bne x6,x0,top      back edge: taken on passes 0..254
top+16           mixed(3)
top+24           jal x0,0           halt (demo_go -> W.halt)
```

- Fixed code. Each pass resets `W.wp = top` and writes the same bytes
  again, so the code never changes between passes. Only the expected
  stream does.
  - When B is taken, `cskip` still writes the skipped `c.addi`, but in
    dry mode, so it is not added to the expected stream.
  - B's encoded target is `top+12` either way.
- Outcomes come from the writer, not x6. `bcc` emits `bne x6, x0` with
  direction `tk` already decided. The backend retires against the
  writer's expected stream, so the value in x6 does not matter.
- B is random. Its direction is the AND of three LFSR bits
  (`tk = W.lfsr_bit() & W.lfsr_bit() & W.lfsr_bit()`), a 16-bit Galois
  LFSR with taps 0xB400 and seed 0xACE1. Taken probability is 1/8.
  Simulating this seed outside the testbench gives 33 taken out of 256;
  the first taken passes are 9, 16, 19, 22, 30, 31.
- Back edge. It is a second conditional that history can predict: taken
  255 times, not taken once at the exit.

---

## 2. Why a random branch produces both events

1. Allocation. B is mostly not taken, so T0 learns not taken. Each taken
   B is a conditional mispredict.
   - `alc_upd_comb` (`rtl/core/frontend/bpu/rtl/tage_cntrl.sv:853`)
     fires on a mispredict when `prm_comp < TAGE_MAX_TBL` and a
     candidate exists (`alc_comp != 0`).
   - It writes the new entry at CTR `3'b100`, which is weak taken.
2. Training `uaon`. History is random, so new entries keep being hit
   under histories they did not learn from.
   - The new entries are weak, so they meet the trigger condition (CTR
     `3'b011` or `3'b100`).
   - They predict taken on a branch that is 7/8 not taken, so the
     primary is usually wrong while the alternate is right.
   - Each such update increments `uaon` (`uaon_upd_ff`, line 380).
3. T0 through use_alt_on_na. Once `uaon[3]` is set (count of 8 or more),
   a weak tagged primary hands the prediction to the alternate (line
   539). When no tagged alternate exists (`alt_comp == 0`), that
   alternate is T0.

`uaon` only updates when both the primary and the alternate are tagged
(`u_prm_tagged && u_alt_tagged`, line 383). Step 2 therefore depends on
cases where B hits in two tagged tables, while step 3 counts cases where
the alternate is T0. The counter that lets T0 win is never trained on
cases where T0 was the alternate. That matches the comment at line 699,
so it looks intended.

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:401-425`, sampled every cycle
on each slot. Each is a count of slot events: the loop sums the slots of
a cycle into a local (`a`, `n_prov`, `n_uaon`) and the counter adds the
sum once.

```
n_tage_alc    trx_type && tage_upd_val_u0[s] && u_alc_wr[s]
              an allocation write that the arbiter granted
n_tage_prov   p2 ready, tage_using_primary && tage_prm_comp != 0
              the provider is a tagged table
n_t0_uaon     p2 ready, !tage_using_primary && tage_prm_comp != 0
              && tage_alt_comp == 0
              primary tagged, prediction from T0
```

The proof (`tb/fe_demo_proofs.svh:74`) is
`n_tage_alc > 0 && n_t0_uaon > 0`. `n_tage_prov` is only reported.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

---

## 4. Reading the numbers

- The three figures are counts of slot events. DOC-001's monitor
  counted `n_tage_prov` and `n_t0_uaon` with `<= x + 1` inside the slot
  loop, so a cycle where both slots qualified counted once. DOC-002
  sums the slots first, as `n_tage_alc` always did.
- The fix does not change this scenario's figures. A count of every
  slot event, made independently in a scratch copy of the testbench,
  found no cycle in this run where both slots qualify for either
  counter. The same check found the undercount in fd05_p3_override
  (`n_tage_prov` 60 before the fix, 85 after), where that figure is
  not reported.
- `tagged-provider predictions` counts p2 predictions (each
  `tage_pred_rdy_p2` slot), not retired branches.
- The program is FD-9's as `planning/showcase/fe_demo_scenarios.md`
  now gives it: the t0_uaon program of tb_fe_top, a branch taken 1 in
  8 from the writer's LFSR.

---

## 5. Waveform

The saved view is `waves/fd09_tage.gtkw`. Look at:

- `tage_pred_meta_p2`: `tage_prm_comp` non-zero with
  `tage_using_primary` set is a tagged provider; `tage_using_primary`
  low with `tage_alt_comp` 0 is T0 by use_alt_on_na.
- `uaon`: rises as weak tagged primaries are wrong and tagged alternates
  are right.
- `trx_type` with `u_alc_wr` set: an allocation.
