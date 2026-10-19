Mostly, yes. Who owns each entry and the rule for a full entry now match
  XiangShan. The main difference is when training happens: XiangShan trains once
  per fetch block at commit, in order, and we train per branch at resolution. A
  few storage and indexing details also differ.

  I checked against FTB.scala, FauFTB.scala, FTBEntryGen in NewFtq.scala, and
  TableAddr in FrontendBundle.scala. During BP-140 I read none of these.
  FrontendBundle.scala was also not in that task's file list; I read it now to
  answer this.

  Same as XiangShan

  ┌──────────────┬─────────────────────────────────┬────────────────────────┐
  │              │            XiangShan            │         BP-140         │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ Who owns an  │ The block start PC at 2-byte    │ The start PC at 2-byte │
  │ entry        │ granularity: TableAddr index    │  granularity           │
  │              │ starts at VA[1]                 │                        │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ Branches per │ 2 (numBr)                       │ NUM_PRED_SLOTS (2 or   │
  │  entry       │                                 │ 1)                     │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ Block length │ 16 slots (PredictWidth), stored │ 16 positions, 5-bit    │
  │  from start  │  in pftAddr plus carry          │ start-relative pft     │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ End on a     │                                 │                        │
  │ miss with no │ Start + 32 bytes                │ PFT_NAT = 16 positions │
  │  jump        │                                 │                        │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ New branch,  │ Inserted in offset order; the   │ Same; a conditional's  │
  │ entry not    │ end is not changed              │ update end is not      │
  │ full         │                                 │ written                │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │              │ Keeps the lowest two, sets the  │ Same rule: end = PC of │
  │ New branch,  │ end to the offset of the one    │  the first branch not  │
  │ entry full   │ dropped, and clears the jump    │ kept, jump not kept    │
  │              │ flags (pft_need_to_change)      │ clears the jump field  │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ Small        │ The FauFTB stores the same      │ The uBTB applies the   │
  │ predictor    │ entry built by FTBEntryGen      │ same rule itself       │
  │ entry        │                                 │ (apply_upd)            │
  ├──────────────┼─────────────────────────────────┼────────────────────────┤
  │ FTB          │ An invalid way first, else PLRU │ Tree-PLRU              │
  │ replacement  │                                 │                        │
  └──────────────┴─────────────────────────────────┴────────────────────────┘

  Different from XiangShan

  1. When and what trains.
     - XiangShan builds one new entry per fetch block at FTQ commit, in program
       order. It uses the block's predecode (pd, which supplies the jump) and
       the taken branch (cfiIndex).
     - A conditional enters the entry only once it has been taken. A branch that
       is never taken never takes a slot.
     - Our update port takes one branch per resolution, possibly out of order,
       and stores a resolved conditional whether taken or not (tb group S
       allocates not-taken ones).
     - That is why BP-140 needed the end to only move down and the
       order-independence tests. XiangShan never has that problem. It also means
       our entries fill and split more often for the same code.
  2. Entry layout. XiangShan has one conditional slot plus a tail slot that
     holds either a conditional or the jump (sharing). Ours is 2+1: two
     conditional fields plus a dedicated jump field. The split caps both at two
     branches. XiangShan's shared tail is the "shared last field" I noted as an
     area-only option: it avoids the 47,104 unused FTB bits at two slots.
  3. FTB index and tag.
     - XiangShan: index = VA[9:1], plain bits with no fold. The tag is VA[29:10]
       truncated to 20 bits, so it is partial and can alias.
     - Ours: index = VA[13:5] XOR (VA[4:1] << 5), and a full 30-bit tag
       {VA[39:14], VA[4:1]}.
     - Both spread the starts of one 32-byte region across sets. XiangShan does
       it by indexing on low PC bits; ours folds the offset into the region
       index.
  4. uBTB and FauFTB organisation. FauFTB is fully associative: 32 ways, a
     16-bit tag pc[16:1], PLRU. Our uBTB has 256 entries, 64 sets of 4 ways, a
     24-bit partial tag with the offset fold, and round-robin replacement. So we
     can see set conflicts that FauFTB cannot; across the tb_fe_top programs,
     uBTB evictions went 133 to 129.
  5. Hit on update. XiangShan uses the hit from prediction time and, when that
     was a miss, reads the FTB again before writing (update_need_read) to avoid
     a duplicate. Ours uses the carried hit and way (TD#163) with no second
     read.
  6. Target storage. XiangShan stores the low target bits plus a 2-bit
     higher/same/lower status (tarStat). I did not compare our target fields
     during BP-140, so I can't say yet how ours differ.

  The two differences that matter for the BP-140 rulings are the first two:
  per-resolution, out-of-order training of every conditional, and the 2+1
  layout. Both are already listed as open under TD#179 in the PA instructions
  ("training at resolve or commit", "the entry shape").

