<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# fd13_l1i: L1I Hit, Miss and MSHR Merge
```
 FILE:    fd13_l1i.md
 SOURCE:  DOC-002, DOC-006
 STATUS:  WORKING
 UPDATED: 2026-10-17
 CONTACT: Jeff Nye
```

`fd13_l1i` is the FD-13 demonstration scenario. It is a demo, not a
verification test. A loop inside one 64-byte line shows L1I hits; cold
lines show misses and MSHR fills; and a call into the upper half of a
cold line, run after a FENCE.I, makes the IFU request one line twice
while its fill is outstanding, so the second request merges onto the
MSHR register already fetching it. The run passes if a hit, a miss and
a merge each happen at least once.

The scenario runs on the one-slot model (Makefile `SCEN_2S`, DOC-006).
A recorded run:

```
-I: fd13_l1i: PASS, L1I hits 43, L1I misses 29, merges 1, cyc 209
```

---

## 1. The program

Source: `programs/fd13_l1i.svh`, task `prog_fd13`. Bare M-mode, code at
RESET_VECTOR 0x8000_0000 (`bp_defines_pkg.sv:40`); X = 0x8000_0800.
Addresses are derived from the writer's emitters.

```
0x8000_0000  mixed(2)                                     6 bytes
top = +0x06  mixed(6)                     16 bytes, within line 0
       +0x16 bne x6,x0,top                8 passes
then four times (it = 0..3; before it = 3 a FENCE.I):
             jal x1, X+0x30               call
X+0x30       c.addi
X+0x32       jal x0, X                    back into line X
X+0x00       mixed(2)
X+0x06       jalr x0,0(ra)                return
             mixed(1)
then mixed(3), jal x0,0                   halt
```

- The loop of 8 passes is 20 bytes from +0x06 to +0x1A and stays in
  the line 0x8000_0000: after its first fill every fetch of it hits.
- X is a cold line. The block at X+0x30 starts in the upper half of
  line X (offset 0x30 of 64), so it needs lines X and X+1 (IFU-7).
- The first three calls train the predictors on the path main ->
  X+0x30 -> X -> main. `fence_i` (`fe_tb_writer.svh:673`) then makes
  every L1I line invalid; the predictors keep what they learned.

---

## 2. Why the program produces the behaviour

1. Hits. `L1iReadLatency` is 2
   (`rtl/core/frontend/icache/rtl/l1i_pkg.sv:122`). A hit leaves the
   bank's compare stage as `rsp_valid = c_hit`
   (`rtl/core/frontend/icache/rtl/l1i_ctrl.sv:229`, `:255`). In the run
   a request at cyc 136 (id 1) is answered with id 1 at cyc 138.
2. Misses. A miss is reported in the same stage, `mis_valid = c_miss`
   (`l1i_ctrl.sv:230`, `:238`), for the MSHR register allocated when
   the request was accepted; the fill comes from the memory port
   (`l1i_mem_a_valid`, `l1i_mem_d_valid`).
3. The merge. On the fourth pass, after the FENCE.I, the run shows
   (cyc is `tb.cyc`, `fe_tb_dut.svh:129`):
   - cyc 175: request id 2, line X (0x8000_0800), block at X+0x30
   - cyc 176: request id 3, line X+1 (0x8000_0840), the same block
   - cyc 177: request id 4, line X again, the predicted block at X,
     with `u_mshr.mrg_hit` set
   - responses: id 2 at cyc 188, id 4 at 190, id 3 at 192.
   The IFU compares a block's first line only with the previous
   request's line (TD-IFU-8,
   `rtl/core/frontend/ifu/rtl/ifu_fetch.sv:290`); the previous request
   was X+1, so the block at X issues its own request. The MSHR finds a
   valid register for line X whose data has not arrived
   (`e_val && !e_got`,
   `rtl/core/frontend/icache/rtl/l1i_mshr.sv:232-233`) and sets
   `mrg_hit` (`:256`, a cacheable request). A merged
   request does not look up the arrays (`l1i_mshr.sv:309-310`:
   `b_req_valid` excludes `mrg_hit`).

---

## 3. What the monitor counts

The counts come from `tb/fe_demo_mon.svh:511-522`, sampled every cycle
while the stream is being measured (`meas`).

```
n_l1i_hit    per bank: u_l1i.b_rsp_valid[b], summed over the 2 banks
n_l1i_miss   per bank: u_l1i.b_mis_valid[b], summed over the 2 banks
n_l1i_merge  u_l1i.u_mshr.accept && u_l1i.u_mshr.mrg_hit
```

The proof (`tb/fe_demo_proofs.svh:115`) is
`n_l1i_hit > 0 && n_l1i_miss > 0 && n_l1i_merge > 0`.
`tb_fe_demo.sv` also requires the whole stream to retire with no errors
before it accepts the proof.

---

## 4. Reading the numbers

- Hits and misses are bank lookups, not instructions or blocks. A
  block needing two lines counts two lookups; a merged request counts
  no lookup. Wrong-path requests inside the measured window are
  counted too.
- DOC-002 changed `n_l1i_hit` and `n_l1i_miss` to sum the two banks in
  a cycle; before, a cycle with both banks answering counted once. A
  DOC-002 scratch check against an independent per-bank count found no
  cycle with both banks answering in this run, so the figures are
  unchanged.
- The merge figure is 1: the event of section 2, step 3.
- The program is FD-13's as `planning/showcase/fe_demo_scenarios.md`
  gives it; no departure.

---

## 5. Waveform

The saved view is `waves/fd13_l1i.sucl`, which `make view S=fd13_l1i`
opens in Surfer. Groups: clock, ftq_ifu, ifu_l1i, l1i. Look at:

- `ifu_l1i_req_val` with `ifu_l1i_req_paddr` and `ifu_l1i_req_id`, and
  `l1i_ifu_rsp_val` with `l1i_ifu_rsp_id` two cycles later: a hit.
- `b_mis_valid`, an MSHR `e_val`, `l1i_mem_a_valid` with
  `l1i_mem_a_address`, the `l1i_mem_d_valid` beats, `e_got` and
  `b_fil_valid`: a miss and its fill.
- cyc 175 to 177: requests for X, X+1, X; `mrg_hit` set on the third.
  `mrg_hit` is the MSHR's match of the presented request, so it is also
  set in cycles with no request taken; the monitor counts it only with
  `u_mshr.accept`.
