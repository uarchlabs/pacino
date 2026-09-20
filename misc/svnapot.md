PA search returned these finding on svnapot:


CVA6:

supported, with a G-stage bug filed three days ago. With the hypervisor and Svnapot enabled, a G-stage 64 KiB NAPOT mapping translates a load to the wrong physical subpage. cva6_tlb.sv replaces the low four PPN bits on the first-stage output but not on the G-stage output, which keeps the encoded PPN[3:0]. (cva6 #3569)

Rocket:

(published implementation, 2024). A research team added Svnapot to Rocket's L2 TLB:

They store 4 KiB and 64 KiB pages in the same structure, with an N bit in each entry marking a 64 KiB page.
A set-associative array has an indexing problem with mixed sizes. They solved it by ignoring the low 4 bits of the VPN when forming the index.
On a lookup with N=1, the physical page is formed from the stored PPN shifted right by 4, plus the NAPOT offset. (arXiv 2406.17802)



Upstream Xiangshan:

One entry, matched across the 64 KiB range. XiangShan does not split a NAPOT
  page into 4 KiB entries.

  In the L1 TLB (MMUBundle.scala, current kunminghu-v3):
  - TlbSectorEntry (line 181) carries its own n field (line 194).
  - The hit test masks the low pteNapotBits = 4 VPN bits when n is set (lines
    227 and 265):
    tag_matchs(0) := Mux(n === 0.U, tag(...) === vpn(...),
    tag(vpnnLen-sectortlbwidth-1, pteNapotBits-sectortlbwidth) ===
    vpn(vpnnLen-1, pteNapotBits))
    So one stored tag answers all 16 pages of the range.
  - The translation splices the request's low VPN bits into the stored PPN
    instead of using the stored low bits (line 418):
    Mux(n === 0.U, Cat(ppn(...), ppn_low(...)),
    Cat(ppn(vpnnLen-sectortlbwidth-1, pteNapotBits-sectortlbwidth),
    vpn(pteNapotBits-1, 0)))

  In the L2 TLB and the walker:
  - PtwEntry takes a hasNapot parameter and adds n when set (lines 908-912). The
    super-page array sp is built with hasNapot = true
    (PageTableCache.scala:338), so a NAPOT entry lands in the super-page
    structure rather than the 4 KiB L0 array: l0Refill excludes it
    (PageTableCache.scala:977) and the sp refill includes it (line 1029).
  - The generic PtwEntry.hit masks the same 4 bits when n is set (lines
    960-963), with the comment "512GB, 1GB, 2MB or 4KB(including SVNapot)".
  - The walker reconstructs the PPN the same way, Cat(ppn(ptePPNLen-1,
    pteNapotBits), vpn(pteNapotBits-1, 0)) (PageTableWalker.scala:917 and
    :1117).

  Encoding and faults: only the 64 KiB case is supported. isNapot requires n ===
  1, ppn(3,0) === 4'b1000 and level 0 (MMUBundle.scala:861-863), and isPf
  raises a page fault when n =/= 0 with any other ppn(3,0) or at a super-page
  level, and also when a non-leaf PTE has n set (lines 805-820). That matches
  what pacino's MMU-U7 says the walker owes.

  Two-stage: the merge logic handles NAPOT at either stage or both, with the
  comment listing the three cases, "s1 is napot(64KB) and s2 is superpage", the
  reverse, and both NAPOT (lines 375-377), and PtwMergeEntry/the G-stage entry
  at lines 1207 and 1266 are built with hasNapot = true.

  For contrast, the local ./xiangshan snapshot has none of this: PteBundle
  declares n (MMUBundle.scala:662) and pteNLen = 1 (MMUConst.scala:109), and no
  other file reads the bit. The only "napot" strings in that tree are PMP
  address matching, which is unrelated.

  So for pacino's MMU-U7, the question "hold a 64 KiB entry once and match it
  across the range, or split it into 4 KiB entries" has a worked precedent for
  the first option: store n in the entry, mask the low four VPN bits in the tag
  compare, splice the request's low VPN bits into the PPN at read, keep NAPOT
  entries in the super-page array rather than the 4 KiB array, and fault every
  other n = 1 encoding in the walker.

Pacino:

This will be the target:

held once, fully-associative match masked on VPN[3:0], PPN[3:0] replaced by VPN[3:0] on every output at both stages, and reserved N encodings page-fault in the walker
