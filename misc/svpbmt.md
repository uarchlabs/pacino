The PA search for other implementations of svpbmt.

What the specification says.

Where the field is. In Sv39, bits 62-61 of a leaf PTE select a page-based memory type that overrides the PMAs for that page. Implementations may also override PMAs beyond the ones the table lists. (privileged spec, Svpbmt)

The three values (Linux patch description):

  - PMA: no change to the region's type.
  - NC: non-cacheable, idempotent, weakly-ordered main memory.
  - IO: non-cacheable, non-idempotent, strongly-ordered I/O.

Precedence under the hypervisor, which is MMU-U6's core question. Types apply in two stages. First, a non-zero G-stage PBMT overrides the PMA to give an intermediate set of attributes. Then a non-zero VS-stage PBMT overrides that intermediate set to give the final attributes. (Svpbmt)

Mismatched cases have defined ordering.
  - IO on a main-memory page: accesses obey strong channel-0 I/O ordering, but count as both I/O and main memory for FENCE, .aq and .rl. (Svpbmt)
  - NC on an I/O region: accesses obey RVWMO. (Priv 1.12)


XiangShan Kunminghu

PMA attributes that Svpbmt doesn't cover keep the physical region's value; for the attributes it does cover, PBMT wins (XiangShan memory model). Its LSU treats NC loads as side-effect free and so executes them speculatively (XiangShan LSU). That covers the data side; I found nothing on fetch.

CVA6:

in the CV64A6 MMU configuration Svpbmt isn't implemented, so PBMTE is always 0 (CVA6 docs). It isn't a reference for this.


Xiangshan upstream:

Here is how XiangShan implements Svpbmt.

  Storage. The TLB entry carries the field, it is not folded into anything else.
  PteBundle.pbmt is 2 bits (MMUConst.scala:161, ptePbmtLen = 2), and
  TlbSectorEntry and the L2 TLB entries each keep their own pbmt plus a separate
  g_pbmt for the G-stage (TLBStorage.scala:132-133, 141-142, 156-157). Both
  travel out on the TLB response.

  Encoding (MMUBundle.scala:381-390): pma = 00, nc = 01 non-cacheable,
  idempotent, weakly ordered, main memory; io = 10 non-cacheable,
  non-idempotent, strongly ordered; rsvd = 11. The only helper is isUncache(a) =
  a === nc || a === io.

  Two-stage precedence (TLB.scala:430-441): the VS-stage value wins when
  nonzero, otherwise the G-stage value.
  allStage -> Mux(pbmtRes =/= 0.U, pbmtRes, gpbmtRes)
  with onlyStage1 -> pbmt, onlyStage2 -> g_pbmt, and 0 when translation is off.
  Worth noting: the older local snapshot has the cruder rule Mux(onlyS1, pbmt, 
  g_pbmt) (TLB.scala:236-243), so the G-stage always won under two-stage. That
  was tightened upstream.

  Precedence against the static region attributes. The consumer merges, it does
  not choose:
  - Load: s2_actually_mmio = s2_pmp.mmio || Pbmt.isUncache(s2_pbmt)
    (LoadUnit.scala:1084).
  - Store: s2_mmio = (s2_in.mmio || s2_pmp.mmio || Pbmt.isUncache(s2_pbmt)) && 
    ... (StoreUnit.scala:363).
  - I-side, main pipe: s2_mmio = pmp_mmio || Pbmt.isUncache(pbmt)
    (ICacheMainPipe.scala:399-401), and the same merge in the prefetch pipe
    (IPrefetch.scala:336-338).

  So a region the PMA calls I/O stays I/O whatever the PTE says, and a PTE
  saying nc or io forces an otherwise cacheable region onto the uncached path.
  ICacheMainPipe.scala:267 is explicit that the two are deliberately kept
  separate up to that point: "DO NOT merge pmp mmio and itlb pbmt here, we need
  them to be passed to IFU separately".

  The I-side carries it end to end. The ITLB result is captured in the prefetch
  pipe (IPrefetch.scala:199-200), stored in the WayLookup queue alongside the
  translation (WayLookup.scala:37), read by the main pipe
  (ICacheMainPipe.scala:177, 222, 311) and forwarded to the IFU (:458, :464).
  When there is no valid translation the field is driven to Pbmt.pma
  (IPrefetch.scala:299, ICacheMainPipe.scala:464), so "no PTE opinion" is the
  default.

  Faults and the enable bit. PteBundle.isPf (MMUBundle.scala:805-812) raises a
  page fault when pbmt === 3 (reserved), when pbmt =/= 0 while the PBMTE enable
  is clear, and when a non-leaf PTE has a nonzero pbmt. The enable comes from
  the CSR file as io.csr.mPBMTE and is passed into the G-stage check in the
  walker (PageTableWalker.scala:1390, 1458), which is menvcfg.PBMTE with the H
  counterpart for the VS-stage.

  What this maps onto in pacino:
  - MMU-U6, precedence: XiangShan's answer is the OR above. The PTE type is a
    second source only in the restrictive direction; the region table still
    decides what the memory is.
  - IL-8 and IL-9: XiangShan returns the PBMT field to the L1 TLB and stores it
    per entry, and separately keeps a g_pbmt. Under pacino's IL-9 the L2 TLB
    returns no memory type at all, so there would be nothing to OR.
  - MMU-14, the speculation gate: XiangShan drives the uncached path from
    pmp_mmio || isUncache(pbmt), so a PTE marked io makes the access
    non-idempotent even where the region table does not. Pacino's IT-10
    idempotent bit comes from the region table alone.
  - The reserved encoding and the PBMTE enable are walker obligations pacino has
    not written down, the same shape as the Svnapot N-bit rule.



Pacino:

What this maps onto in pacino:

	- MMU-U6: the PTE type never overrides the region attributes; it is ORed with
	  them, and it can only make an access less cacheable, never more.
    precedence: The PTE type is a second source only in the restrictive 
    direction; the region table still decides what the memory is.

  - IL-8 and IL-9: XiangShan returns the PBMT field to the L1 TLB and stores it
    per entry, and separately keeps a g_pbmt. Under pacino's IL-9 the L2 TLB
    returns no memory type at all, so there would be nothing to OR.

  - MMU-14, the speculation gate: XiangShan drives the uncached path from
    pmp_mmio || isUncache(pbmt), so a PTE marked io makes the access
    non-idempotent even where the region table does not. Pacino's IT-10
    idempotent bit comes from the region table alone.

  - The reserved encoding and the PBMTE enable are walker obligations pacino has
    not written down, the same shape as the Svnapot N-bit rule.


Assessment from IA:

  One observation on the Svpbmt ruling, not an audit item. MMU-U6 takes the most
  restrictive of the two stages, and records that this is a strict
  implementation rather than the specification's override. XiangShan's
  pbmt_check instead takes the VS-stage value when nonzero and the G-stage value
  otherwise, which is the specification's rule; its restriction comes later,
  where isUncache(pbmt) is ORed with the region's MMIO bit. Pacino's choice is
  legal and simpler, and the document says why.


