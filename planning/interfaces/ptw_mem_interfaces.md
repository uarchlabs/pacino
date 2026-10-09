<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# Page Table Walker to Memory Interface
```
 FILE:    ptw_mem_interfaces.md
 SOURCE:  session-077 rulings; mmu_decisions.md MMU-2, MMU-8
 STATUS:  DRAFT
 UPDATED: 2026-10-09
 CONTACT: Jeff Nye
```

Owns the WM-N registry.

---

## 1. Scope

The page table walker's port to memory (`mmu_decisions.md` MMU-2).
The walker reads PTEs on it and performs the Svadu update of MMU-8
on it. Nothing else uses it.

TODAY A TESTBENCH ANSWERS IT. There is no L2 (Jeff, session-076),
so tb_fe_top's memory model answers this port, from the same memory
image as the model that answers the L1I's memory port
(`fe_decisions.md` FE-21). The port is still real RTL on the
walker, specified as the permanent boundary: when an L2 exists the
walker's traffic goes on a master edge into it (MMU-2), and how the
compare-and-swap of WM-5 is carried there is `mmu_decisions.md`
MMU-U3.

The client side of the walker is `itlb_l2tlb_interfaces.md`. The
walk itself is `mmu_decisions.md`.

---

## 2. Naming

```
  ptw_mem_<signal>    walker -> memory
  mem_ptw_<signal>    memory -> walker
```

No stage suffixes, as for `l1i_ifu_interfaces.md` 2.

---

## 3. Ports

```
  ptw_mem_req_val                              walker -> memory
  ptw_mem_req_rdy                              memory -> walker
  ptw_mem_req_op                               walker -> memory
  ptw_mem_req_paddr  [PA_WIDTH-1:0]            walker -> memory
  ptw_mem_req_cmp    [63:0]                    walker -> memory
  ptw_mem_req_swap   [63:0]                    walker -> memory

  mem_ptw_rsp_val                              memory -> walker
  mem_ptw_rsp_data   [63:0]                    memory -> walker
  mem_ptw_rsp_err                              memory -> walker
```

```
  ptw_mem_req_op   0  READ   read the 8 bytes at paddr
                   1  CAS    compare and swap the 8 bytes at paddr
```

There is no response ready, no identifier and no byte enable.

---

## 4. Rules

```
  WM-1  EVERY ACCESS IS ONE PTE: 8 bytes, naturally aligned, and
        atomic. ptw_mem_req_paddr[2:0] is zero. The privileged
        specification performs every implicit access to the
        translation structures at PTESIZE, which is 8 for Sv39 and
        Sv39x4, and an A/D update rewrites the whole PTE, not one
        bit of it. The memory side asserts the alignment.

  WM-2  A request is accepted in a cycle where ptw_mem_req_val and
        ptw_mem_req_rdy are both high. The walker holds every
        request field stable from the cycle val rises until
        acceptance. ptw_mem_req_rdy does not depend combinationally
        on ptw_mem_req_val.

  WM-3  AT MOST ONE REQUEST IS OUTSTANDING, from acceptance until
        its response. The walker performs one walk at a time
        (mmu_decisions.md MMU-U2) and each step of a walk needs the
        previous PTE, so a second request would have nothing to
        carry.

  WM-4  The response is presented when mem_ptw_rsp_val is high, no
        earlier than the cycle after acceptance. The walker accepts
        it unconditionally in that cycle. WM-3 makes an identifier
        unnecessary.

  WM-5  CAS COMPARES AND STORES AS ONE ATOMIC OPERATION. The memory
        compares the 8 bytes at paddr with ptw_mem_req_cmp; if they
        are equal it stores ptw_mem_req_swap there. In either case
        mem_ptw_rsp_data returns the value the memory held BEFORE
        the operation, so the walker knows the store happened
        exactly when mem_ptw_rsp_data equals ptw_mem_req_cmp. No
        other access to those bytes may fall between the compare
        and the store. This is the privileged translation
        algorithm's step 9 (mmu_decisions.md MMU-8): on a mismatch
        the walker restarts the walk.

  WM-6  A CAS RESPONSE IS NOT PRESENTED BEFORE THE STORE IS VISIBLE
        to every later access by any agent. The walker returns the
        translation only after this response (MMU-8), so the update
        precedes the fetch that needed it in the global order, as
        the specification requires.

  WM-7  mem_ptw_rsp_err high with mem_ptw_rsp_val means the memory
        side returned an error. mem_ptw_rsp_data is then undefined,
        and for a CAS nothing was stored. The walker reports an
        access fault, cause 1, for the translation it was
        performing. The memory side's error has the same standing
        as l1i_ifu_interfaces.md IF-15.

  WM-8  A REQUEST THAT FAILS A CHECK IS NEVER PRESENTED. The walker
        makes the PMP and PMA checks of mmu_decisions.md MMU-10d,
        MMU-12 and MMU-12a, and refuses an address it cannot form
        (MMU-28), before it presents the request, so no checked
        failure reaches this port. The same division as
        l1i_ifu_interfaces.md IF-22.

  WM-9  While rstn is low the walker holds ptw_mem_req_val low and
        the memory side holds mem_ptw_rsp_val and ptw_mem_req_rdy
        low. Nothing is outstanding across reset.
```

---

## 5. The testbench memory model

What tb_fe_top's model must do on this port, because the
programs BP-123 writes depend on it:

```
  WM-10 ONE MEMORY IMAGE. The model answering this port and the
        model answering the L1I's memory port read and write one
        store, so a page table written by the program's set-up and
        a later instruction fetch see the same bytes, and an A bit
        set by the walker is visible to a later walk.

  WM-11 IT CAN CHANGE A PTE BETWEEN A WALK'S READ AND ITS CAS, on
        the stimulus's instruction, so the mismatch path of WM-5
        and the restart of MMU-8 are exercised. An agent writing
        memory between the two is exactly the case the compare
        exists for.

  WM-12 IT CAN RETURN mem_ptw_rsp_err on a chosen access, read or
        CAS, so WM-7 is exercised.

  WM-13 IT CAN HOLD ptw_mem_req_rdy LOW and vary the response
        latency, so the walker is not tested against one fixed
        timing.
```

---

## 6. Open

None. The L2 half of the compare-and-swap is mmu_decisions.md
MMU-U3, moved to the L2 work.

---

## 7. Bindings

```
  MMU-2     The port this document specifies.
  MMU-8     The CAS of WM-5 and the ordering of WM-6.
  MMU-10d   The checks of WM-8, at privilege S.
  MMU-12a   Page tables only in cacheable coherent memory, WM-8.
  MMU-28    Addresses the walker cannot form, WM-8.
  MMU-U2    One walk at a time, the basis of WM-3.
  MMU-U3    The L2 realisation of WM-5.
  FE-21     The L1I memory port whose model shares WM-10's image.
  IL-*      The walker's client side, itlb_l2tlb_interfaces.md.
```

---

## 8. Document History

```
  2026-10-09  Created, session-077, from the rulings that reversed
              MMU-1 and confirmed full Svadu (Jeff). The walker has
              its own memory port, answered by a testbench model
              until an L2 exists. One request outstanding, 8-byte
              READ and CAS, a CAS response only once the store is
              visible, checks made before the request.
```
