Pacino front end: what is still missing before IFU RTL can be written

  The IFU can't be written correctly yet. Four blockers are already on record,
  and I confirmed each one in the RTL. A full read of the three IFU boundary
  documents found about six more gaps that change the IFU's structure or ports.
  The IFU also has no neighbours to test against: there is no ITLB, no ibuf, and
  no L1I with the ports the documents describe.

  I read ifu_decisions.md, ftq_ifu_interfaces.md, ifu_ibuf_interfaces.md and
  itlb_ifu_interfaces.md end to end. A subagent read l1i_ifu_interfaces.md and
  icache_decisions.md end to end, and I spot-checked what it reported. I did not
  run any test suites, because make writes object directories into the tree and
  I have no write access. Pass/fail status below comes from the documents, not
  from a run in this session.

  What exists

  ┌─────────────────────────┬───────────────────────────────────────────────┐
  │          Unit           │                     State                     │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │ BPU                     │ Built, 22 modules                             │
  │ (rtl/core/frontend/bpu) │                                               │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │ FTQ                     │ Built, including ftq_ifu.sv                   │
  │ (rtl/core/frontend/ftq) │                                               │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │ Decode                  │ Built: rvc_expander, predecode, instr_decoder │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │ IFU, ibuf, icache       │ Empty                                         │
  │ directories             │                                               │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │ ITLB                    │ No directory. cachegen cannot generate one    │
  │                         │ (itlb_decisions.md)                           │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │                         │ tools/cachegen/output/l1i/ matches the        │
  │ L1I                     │ documents: 36-bit PA, 512-bit line, 16 IDs,   │
  │                         │ out-of-order return. import/l1i/ is an older  │
  │                         │ 32-bit copy; don't use it                     │
  ├─────────────────────────┼───────────────────────────────────────────────┤
  │ Front-end top (FE-16)   │ Not started                                   │
  └─────────────────────────┴───────────────────────────────────────────────┘

  1. Hard blockers already recorded, all confirmed in RTL

  1. TD#122, missing package parameters. bp_defines_pkg.sv:21 still has VA_WIDTH
     = 40. None of the widths the ITLB ports need exist (GPA, VPN, PPN, ASID,
     VMID, PERM, CAUSE, PMA). The L1I port widths are also missing: PA_WIDTH,
     REQ_ID_BITS, L1I_LINE_BITS, L1I_OFFSET_BITS, MAX_OUTSTANDING,
     L1I_LINE_BYTES, MAINT_*. Nothing ties cachegen's l1i_pkg to bp_defines_pkg
     (TD-IF-1).
  2. The package-change waiver. This is your decision. CLAUDE.md forbids
     changing an existing declaration, and TD#122 changes one.
  3. TD#127, translation port not built. There is no xlate_ptr in ftq_ptr.sv,
     and no ftq_ifu_xlate_* port on ftq_ifu.sv or ftq.sv. The whole translation
     request group (4.1) is missing on the FTQ side, not just the pointer.
  4. TD#126, flush index. ftq_ifu.sv sets the flush index to redir_idx + 1'b1
     whenever _self is clear, for every cause. IB-13 and W3 require K for
     predecode, p2 and p3 redirects.

  2. Also missing on the FTQ side

  - TD-IFU-4. ftq_ifu_commit_ptr is not a port on ftq_ifu.sv or ftq.sv. The
    uncached fetch rule (IFU-22) needs it.

  3. Structural gaps in the IFU specification

  Each of these changes the IFU's state or ports, not just a size.

  - One or two prediction blocks per cycle (ftq_ifu_interfaces.md 8 item 2). It
    is marked "decided with the IFU design", so it has to be decided now. One
    32-byte block per cycle gives at most 8 full-size instructions, and fewer
    when a block ends early at a taken branch. That puts the CLAUDE.md "sustain
    8 per cycle" target in question. Choosing two reopens the FTQ request and
    writeback ports.
  - TD-IFU-9 / TD-IF-5, reorder buffer. The L1I returns responses out of order,
    and writeback to the FTQ is once per block in order. Nothing sets the
    buffer's size or what holds a block whose line came back early.
  - TD-IFU-7 / L1I-U5, line buffer. Its depth (anywhere from 1 to 16 slots under
    IF-7) is unset, and so is its behaviour on a redirect.
  - Wrong-path requests after a redirect. The L1I has no cancel port, and a
    request ID is freed only when its response arrives. How the IFU marks those
    requests and drops their data is not written down.
  - TD-IFU-8, issue policy. Not stated whether the IFU issues for a later block
    before an earlier response lands. This also affects the L1I's 4-target merge
    sizing.
  - Translation queue entry for a block that crosses a page. This gap is not in
    ifu_notes.md. IFU-25 gives the entry one physical address, one PMA result
    and one fault cause. IT-2 allows two translations per block, so either the
    entry holds two of each or the rule needs a sentence explaining why not.
  - IFU-U5, translation queue depth. Unruled. IT-14's "a slot for each of the
    two outstanding requests" suggests one block at a time at the ITLB. Say so
    explicitly if that is intended.
  - Uncached fetch. IFU-U4 (bus width) is unruled, and the uncached bus has no
    port document at all.
  - TD-IFU-10, fence.i / cbo.inval path. The producer on the commit side is
    unspecified. The cachegen L1I has no invalidate port (TD-IF-4, TD#119), so
    Zifencei and Zicbom have no hardware path. That is an RVA23 compliance gap.

  4. The package edit spreads into decode

    unspecified. The cachegen L1I has no invalidate port (TD-IF-4, TD#119), so
    Zifencei and Zicbom have no hardware path. That is an RVA23 compliance gap.

  4. The package edit spreads into decode

  DCD-16 redefines predecode_pkt_t and removes vtype_hazard and may_be_branch.
  Those fields are used by instr_decoder.sv, predecode.sv and both of their
  testbenches. So this edit breaks the decode unit, not just two packages. It
  needs to be sequenced with decode rework, or given a new struct name.

  rvc_expander.sv takes 8 slots and a start mask. IFU-4 needs 17 halfword
  positions expanded independently, so it is not reusable as it stands.

  5. Missing for an IFU unit test

  - ITLB: a behavioural model built from itlb_ifu_interfaces.md, covering hit,
    miss, three fault causes, GPA and PMA, and out-of-order tags.
  - L1I: a hand-written responder. It needs to force out-of-order returns, rerr
    and ready stalls, and to cover the invalidate path. The cachegen L1I can
    serve as a smoke-test partner only.
  - ibuf: a simple model with the "all 16 slots free" ready rule (IB-6).
  - FTQ: the real ftq.sv, once TD#126, TD#127 and TD-IFU-4 are fixed.

  6. Conflicts between documents

  - cbo.inval: icache_decisions.md (TD-L1I-2) says undecided;
    l1i_ifu_interfaces.md IF-41 says it was ruled "routed" in session 068.
  - TD-IF-1: l1i_ifu section 3.1 treats it as open and carrying PA_WIDTH and the
    rest; section 17 says it was reopened as TD#122, about VA_WIDTH only.
  - Port prefixes: l1i_ifu section 2 says the prefix names the driver, but
    ifu_l1i_req_rdy and ifu_l1i_inv_rdy are driven by the L1I, and
    cmt_ifu_maint_rdy by the IFU.

  7. One place I'd rate lower than ifu_notes.md

  TD#125 O-1 to O-3 are about how the FTB and uBTB store positions internally.
  Every port the IFU sees carries positions measured from the block start
  (ftq_ifu_interfaces.md 3). So they affect prediction accuracy, not IFU
  correctness, and don't block the IFU prompt.

  Suggested order

  1. Decide the waiver, then do TD#122 together with the DCD-16 edit and the
     decode rework.
  2. Rule one vs two blocks per cycle.
  3. On the FTQ side: TD#126, TD#127 and TD-IFU-4, in one task.
  4. Rule TD-IFU-7, TD-IFU-8 and TD-IFU-9, the wrong-path handling, the
     translation queue entry for page-crossing blocks, and IFU-U5.
  5. Decide whether uncached fetch and fence.i are in the first IFU task. If
     not, stub them with a TD number.
  6. Specify the ITLB, L1I and ibuf test models, then write the IFU prompt.

  The last item in ifu_notes.md ("complete read of the three IFU boundary
  documents") is covered by this review.

