# prop1: ITTAGE target upper bits from the branch PC

From:    IA, after BP-109 (TD#122)
Review:  PA, session-073. Changes marked [PA].
To:      Jeff
Status:  NOT ADOPTED. Ruled session-073 (Jeff): the two missing
         bits are STORED instead (alternative D, section 4), so
         IT_MAX_TGT_WIDTH goes 38 -> 40 and no reconstruction rule
         remains. Section 1 stands as the statement of the defect.
         Sections 2, 5 and 6 are the rejected design and are kept
         for the record. TD#132 carries the ruling; the homes are
         ftq_bpu_interfaces.md 5.2 and
         ittage_table_entry_formats.md.
         Was: PROPOSAL, revision 2, needs a ruling.
         Changes ftq_bpu_interfaces.md 5.2 and, for section 5,
         ftq_bpu_interfaces.md 8.
Date:    2026-09-22
Tracked: TD#132. This file is the home; the TD points here.

---

## 1. Problem

The ITTAGE target field holds VA[38:1] (IT_MAX_TGT_WIDTH 38, pinned
session-070). The cluster rebuilds a VA_WIDTH (41) target from it.
BP-109 built what ftq_bpu_interfaces.md 5.2 specifies: append a zero
bit 0 and ZERO extend. bp_cluster.sv, p2_succ_comb:

```
  it_tgt = VA_WIDTH'({stored_tgt, 1'b0});      // bits 40:39 = 00
```

That is right for V=1: the fetch PC is a zero-extended 41-bit GPA,
and sign extension corrupts any GPA with bit 38 set (TD#122).

It is wrong for V=0 upper-half targets. A Sv39 kernel address has
VA bits 63:38 all set. However the 41-bit fetch PC ends up holding
that address, the zero-extended target has bits 40:39 = 00, and the
kernel PC does not. Every kernel indirect target that ITTAGE supplies
is wrong.

This does not wear off. After the mispredict, the update writes
resolved VA[38:1] back to the provider entry. Those are the same bits
that entry already holds, so no update can make it correct. For as
long as it hits, ITTAGE overrides the FTB jump target (5.2: the FTB
target stands only when ittage_hit is clear), and resolve redirects
every time. In effect ITTAGE stops predicting kernel indirect
branches: function pointers, switch tables, vtables.

This is a performance loss, not a correctness loss. FE-19 allows a
predictor to be wrong.

## 2. Proposal

Take the bits the field does not store from the PC the prediction is
made against:

```
  it_tgt = { r_pc_p2[VA_WIDTH-1 : IT_MAX_TGT_WIDTH+1],   // 40:39
             stored_tgt,                                  // 38:1
             1'b0 };                                      // 0
```

[PA] `r_pc_p2` is the BLOCK BASE, not the branch instruction's own
PC. The two share bits 40:39 unless a 32-byte prediction block
straddles a 512 GB boundary, which it cannot. State it as the block
base in 5.2: "the branch's PC" and "the block base" are the same
thing here only by that argument, and a later reader will not
reconstruct the argument.

The reason: an indirect branch almost never leaves the address region
it sits in. Moving between the user and kernel halves goes through
traps, ecall and sret. Those are not predicted indirect branches.

- V=0: a kernel PC carries the upper-half bits, so its kernel targets
  get them. A user PC carries zeros, so its targets get zeros.
- V=1: the target gets GPA bits 40:39 from the PC. It is wrong only
  when an indirect jump crosses a 512 GB region of guest physical
  space.
- It needs no ruling on how a V=0 Sv39 address is held in the 41-bit
  PC. Whatever the form, PC and target share it. The zero-extend rule
  does depend on that ruling.

It matches how the FTB already works: the FTB rebuilds targets
relative to the block base (recon_br, recon_jmp), not from zero.

## 3. Cost

- Storage: none. IT_MAX_TGT_WIDTH stays 38, and the session-070 pin
  stands.
- Logic: a 2-bit splice from r_pc_p2, a register already in p2 and
  already read by p2_succ_comb. There is no new path.
- Update path: unchanged. ITTAGE still stores VA[38:1].

## 4. Alternatives considered

A. Widen IT_MAX_TGT_WIDTH to 41.
   - Cost: 3 bits per entry, 2048 entries across IT1-IT5, and each
     table holds two RAMs, one per prediction slot. That is about
     12 Kbit.
   - It reverses the session-070 pin.
   - It is exact, but pays storage for a case the PC already covers.

B. Choose sign or zero extension from the translation mode (V, satp
   and vsatp mode) at predict time.
   - The predictor would need mode state that changes on every trap
     and xRET, and that state would have to be checkpointed with the
     FTQ entry.
   - It still needs the V=0 representation ruling.
   - It gives the same answer as the proposal for everything except
     cross-region jumps, at far more cost.

C. Keep zero extension. Kernel indirect prediction is lost, as
   described in section 1.

D. [PA] Store only the two bits the field is missing: widen the
   entry by 2 rather than 3, about 8 Kbit.
   - Exact, like A, and cheaper than A.
   - Still storage, still against the session-070 pin, and still
     paying for what the PC supplies free.
   - Recorded so the record shows it was weighed, not missed.

## 5. Companion: do not train what cannot be stored

[PA] This was written as optional. It is not, and the reason is
section 1's own argument. Under the proposal a resolved target whose
bits 40:39 differ from the PC's cannot be represented, so the entry
is wrong by construction, and the update writes back the same VA[38:1]
it already holds. That is the sticky entry of section 1 in a rarer
place. Adopt section 5 with section 2. It stays separable in the RTL,
because it lands in the FTQ rather than the cluster.

Some resolved targets cannot be represented: target bits 40:39 differ
from PC bits 40:39. For those, the FTQ sets a flag that stops ITTAGE
from allocating the entry or writing its target. The FTB jump target
and the resolve redirect then handle the rare cross-region jump, and
ITTAGE never holds an entry that is wrong by construction.

The FTQ holds the full PC and target at resolve, so this is one 2-bit
compare. It changes the ITTAGE update interface (ftq_bpu_interfaces.md
8).

[PA] The ruling must name each field the flag suppresses.
CONFIRMED against ittage_cntrl_decisions.md, revision 2:

```
  allocation                 SUPPRESSED. The alloc path of
                             ittage_cntrl_alloc_rules.md; the
                             entry is never written.
  target write               SUPPRESSED. The two declared
                             strobes prm_tgt_wr_u0 and
                             alt_tgt_wr_u0 (ittage_interfaces.md
                             Target Write Gating, II6).
  CTR update                 NOT suppressed. DEC on a mispredict
                             as the CTR update rules already
                             specify.
  useful counter and aging   NOT suppressed
                             (ittage_cntrl_use_update_rules.md,
                             which the PA has not read).
```

The CTR is the one that matters, and the existing rules already do
the right thing once the target write is gated. On a mispredict the
provider CTR decrements; at 3'b000 the entry is null, which is the
replacement candidate and the UAON trigger point, so it falls out of
the way by itself. Suppressing the update whole would leave an entry
that cannot be represented holding the confidence it earned, hitting,
and overriding the FTB target for as long as it lives.

[PA] Note what the existing target rule means for section 1. Under
"Concurrent CTR and TGT Writes" the target field is rewritten on a
mispredict only when CTR is 0. For the section 1 defect that rewrite
puts back the same VA[38:1] the entry already holds, so the entry
cycles: decay to null, rewrite the same bits, climb again. That is
the sticky entry, in the RTL's own terms.

## 6. [PA] Side effect: the reconstruction is lookup-PC dependent

Under section 2 one stored entry yields different targets under
different lookup PCs. The entry no longer has a single meaning; it
means "these 38 bits, under whatever PC reads them".

This is the shape of TD#125 and of the FTB shared-entry problem, in
the ITTAGE. It is harmless here, because the resolve redirect
corrects a wrong target and the entry is a prediction, not an
architectural value.

It does change verification. Any test that seeds an ITTAGE entry and
checks the reconstructed target must state the lookup PC it expects
the target under. BP-109's C1f2 already does this. A test that seeds
an entry and checks a target without naming the PC is testing
nothing after this change.

## 7. What changes if ruled

- ftq_bpu_interfaces.md 5.2: replace "reconstructs by appending the
  zero bit" and the zero-extension rationale with:
  - the reconstruction above, stated against the BLOCK BASE;
  - V=1 correctness (a GPA takes its high bits from the PC, which is
    itself zero-extended);
  - V=0 behavior;
  - the cross-region mispredict, allowed under FE-19;
  - [PA] the lookup-PC dependency of section 6.
  The statement that sign extension is wrong stays.
- ftq_bpu_interfaces.md 8: the section 5 flag and the fields it
  suppresses.
- fe_decisions.md FE-19: nothing, if it only states the storage and
  architectural rule. The PA to confirm.
- RTL, one task:
  - bp_cluster.sv p2_succ_comb: both the prm and alt arms.
  - tb_bp_cluster.sv G2: its reconstruction model, currently
    VA_WIDTH'({tgt, 1'b0}).
  - bp_structs_pkg.sv 283: the comment.
  - bp_defines_pkg.sv IT_MAX_TGT_WIDTH: the comment.
  - the FTQ side of section 5, if ruled with it.
- Checks for that task:
  - C1f2 (bit-38 GPA, PC bits 40:39 = 00) still passes as written.
  - Add an upper-half case: PC and target both with bits 40:39 = 11.
    It must fail under zero extension and pass under the proposal.
  - Add a cross-region case: PC bits 40:39 differ from the target's.
    It pins the documented mispredict, so a later change cannot
    silently alter it.
  - [PA] If section 5 is ruled, add a case that a cross-region
    resolution allocates nothing and leaves the entry's confidence
    falling, not held.

## 8. Open for Jeff

- Rule section 2, and section 5 with it. Section 5 is separable in
  the RTL but not in the argument; see the note at its head.
- [PA] The V=0 representation question from BP-109 stays open and is
  NOT only a prediction-quality matter. A canonical Sv39 kernel VA
  has bits 63:38 set, which is the pattern FE-19 and TD#122 have the
  redirect PC check REJECT as an out-of-range GPA. FE-19, FE-U11 and
  how the 41-bit fetch PC holds a V=0 address have to be settled
  together, and the IFU needs the answer before it can form a
  redirect PC. This proposal only stops ITTAGE from depending on it.
