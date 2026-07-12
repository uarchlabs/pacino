```
 FILE:    fe_qaa.md
 SOURCE:  various
 STATUS:  DRAFT
 UPDATED: 2026-07-08
 CONTACT: Jeff Nye
```

# INTRO

this is a snapshot of a question and answer interactive session on the
behavior of the frontend.


# Details

thank you, going back to the ftq-bpu structures. I want your help             
  understanding these structures. I would guess there is a structure from ftq   
  to bpu that initiates prediction by the bpu. Is this correct ? If yes which   
  structure ? If no what tells the bpu that prediction(s) are requested ?       
  
● Good question — and the answer is counterintuitive, so let me verify it
  against the RTL rather than assert it from memory.

● Let me look at how the BPU generates its own next-PC (the npcGen priority mux)
  and how the FTQ's redirect/update feed into it.

  Read 1 file (ctrl+o to expand)

● Good instinct to question it — and the answer is no, which is the single most
  important architectural fact about this front end. There is no FTQ→BPU
  structure that requests a prediction. Let me explain what actually happens,
  with the RTL to back it.

  The BPU is free-running, not request-driven

  The BPU is self-steering. It holds its own next-PC register and launches a new
  prediction essentially every cycle on its own initiative. The FTQ does not
  "ask" for predictions — it only throttles and corrects the BPU.

  Look at the four FtqToBpuIO members again — none of them is a prediction
  request:

  ┌────────────────┬───────────┬────────────────────────────────────────┐
  │     Signal     │ Direction │                Purpose                 │
  ├────────────────┼───────────┼────────────────────────────────────────┤
  │ enq_ptr        │ FTQ→BPU   │ FTQ occupancy bookkeeping              │
  ├────────────────┼───────────┼────────────────────────────────────────┤
  │ redirect       │ FTQ→BPU   │ Correction (mispredict/flush recovery) │
  ├────────────────┼───────────┼────────────────────────────────────────┤
  │ update         │ FTQ→BPU   │ Training (commit-time)                 │
  ├────────────────┼───────────┼────────────────────────────────────────┤
  │ redirctFromIFU │ FTQ→BPU   │ Flags redirect source                  │
  └────────────────┴───────────┴────────────────────────────────────────┘
```
  What actually initiates a prediction: s0_pc + s0_fire

  The BPU keeps its own PC (BPU.scala:290, s0_pc_dup / s0_pc_reg_dup). Every
  cycle it can fire a fresh lookup at that PC:

  predictors.io.in.valid   := s0_fire_dup(0)   // launch a prediction
  predictors.io.in.bits.s0_pc := s0_pc_dup     // ...at the BPU's own PC
  (BPU.scala:362-363)

  The next PC is chosen by a priority mux, npcGen (BPU.scala:323, 913), whose
  inputs are — in effect — all internal:

  - stallPC — hold current PC when stalled (:487)
  - s1_target — the BPU's own stage-1 predicted target (:544)
  - s2_target / s3_target — the BPU's own later-stage self-redirects (:647,
  :733)
  - redirect_target — the FTQ redirect's cfiUpdate.target (:892)
  - reset vector — at startup (:293)

  So in the steady state the BPU feeds its own predicted target back into its
  own PC and walks forward autonomously, emitting a stream of predicted fetch
  blocks into the FTQ. This is the "decoupled front end": the BPU runs ahead of
  the IFU, and the FTQ is the elastic buffer between them.

  What the FTQ actually sends back is backpressure, not a request

  The thing that most resembles a "request" is the resp.ready bit of the BPU→FTQ
  Decoupled channel — and it flows FTQ→BPU. The BPU only advances when the FTQ
  can accept the result:

  s1_fire := s1_valid && s2_components_ready && s2_ready &&
  io.bpu_to_ftq.resp.ready
  (BPU.scala:401)

  When the FTQ fills (its bpuPtr catches the commit pointer), it deasserts
  io.fromBpu.resp.ready, s0_fire/s1_fire drop, and the BPU stalls by
  re-selecting stallPC. So the control model is credit/ready backpressure, not
  request/grant. The FTQ says "I have room" (ready), never "predict address X."

  The only time the FTQ steers the BPU

  Two events, both corrections rather than requests:

  1. redirect (BPU.scala:376, do_redirect): on a mispredict/flush, the FTQ hands
  the BPU the corrected cfiUpdate.target, which wins the npcGen mux
  (priority 2) because the redirect also asserts s1_flush/s2_flush/s3_flush
  (:383) to invalidate the in-flight speculative stages. This resets the BPU's
  free-running PC onto the correct path.
  2. update: commit-time training of FTB/TAGE/SC/ITTAGE/RAS — no effect on when
  predictions happen.

  Why this matters for Pacino

  If you were expecting a valid/address "predict-request" bundle (the natural
  shape for an in-order, IFU-leads-BPU design), you won't find one here, by
  design. Kunminghu inverts that: BPU leads, FTQ buffers, IFU follows. For your
  8-wide OoO front end that's the model you want — the predictor generates
  fetch-block targets at its own rate and the queue decouples it from
  fetch/decode. If you instead build a request-driven BPU, you serialize
  prediction behind fetch and lose the run-ahead.

  Want me to add a short "Control model / who initiates" section to fe.md
  capturing this (the s0_pc/s0_fire/resp.ready loop and the npcGen priority
  list)? It's the kind of thing that's easy to forget when reading the bundle
  tables in isolation.

---
ok dumb question how does the bpu know the pc of branches ?                   

● Not dumb at all — it's the crux of how a predict-ahead front end works. The
  short answer: the BPU never sees instruction bytes, so it doesn't "know" where
  branches are by decoding. It only knows a branch is there because the FTB 
  told it, and the FTB stores the branch's position as an offset from the block 
  start.

  The BPU predicts blindly, by PC

  Each cycle the BPU takes its s0_pc (block start) and looks it up in its
  tables. It has no instructions — just the address. Two different things come
  back:

  - Where the branches are → from the FTB (Fetch Target Buffer). An FTB entry,
  keyed by the block PC, stores up to numBr branch slots, and each slot holds an
  offset, not a full PC:

  FtbSlot.offset : UInt(log2Ceil(PredictWidth))  // in-block slot index
  - (this is the offset field in the tables in fe.md)
  - Whether each branch is taken → from TAGE/SC (conditional), ITTAGE (indirect
  target), RAS (returns). These are also indexed by PC + global history.

  The branch PC is reconstructed: startAddr + offset

  The full branch address is never stored — it's rebuilt from the block start
  plus the offset. That's exactly what Ftq_RF_Components.getPc does
  (NewFtq.scala:89):

  def getPc(offset: UInt) =
    Cat(getHigher(...startAddr/nextLineAddr...),
        getOffset(startAddr) + offset,
        0.U(instOffsetBits.W))

  offset is a 4-bit slot index (log2Ceil(PredictWidth), PredictWidth=16),
  counting 2-byte slots because RVC exists (instOffsetBits=1). So branch_pc = 
  block_start + offset*2. The offsets vec you saw in FullBranchPrediction is
  just entry.getOffsetVec copied out of the hit FTB entry.

  So the BPU knows branch PCs only relative to the block it's currently
  predicting, and only for branches the FTB has already recorded.

  So how did the FTB learn the offset in the first place?

  This is the important part — and it closes the loop back to the ifu_ftq.md and
  fe.md interfaces:

  1. Cold miss: first time a block is predicted, there's no FTB entry → hit = 
  false → the BPU predicts fall-through, nothing taken. It genuinely doesn't
  know a branch is in there yet.
  2. The block gets fetched and the IFU predecodes the bytes — the IFU is the
  first stage that actually looks at instructions and can say "there's a branch
  at slot 5."
  3. That travels back as pdWb (PredecodeWritebackBundle) → FTQ. FTBEntryGen
  (NewFtq.scala:232) builds a new/updated FTBEntry, computing the branch offset
  and target-low-bits.
  4. At commit it's written back via BranchPredictionUpdate.ftb_entry → the FTB
  SRAM.
  5. Next time that PC is predicted, the FTB hits and the BPU now "knows" the
  branch offset — before any decode.

  The mental model

  The BPU is a PC → (branch offsets + targets + taken bits) associative memory
  that was trained by the decoder after the fact. It predicts the shape of a
  fetch block it has never decoded, using only the start address, and
  reconstructs each branch PC as start + offset. The decoder (IFU predecode) is
  the ground-truth source that teaches the FTB where branches actually live.

  For your 8-wide Pacino port the consequence is: the FTB slot count and offset
  width are what bound "how many branches per block the predictor can even
  represent," and a cold FTB always predicts fall-through until the
  predecode→update path populates it.

✻ Churned for 39s


so continuing the dumb questions, is the process IFU->FTB->BPU->FTQ->IFU ?    

● Not dumb — but the arrow order has two things flipped, and fixing them is the
  whole point of the decoupled front end. Two corrections:

  1. The FTB is not a stage between IFU and BPU. It lives inside the BPU. The
  BPU reads the FTB (and TAGE/SC/ITTAGE/RAS) itself. So it's never "IFU → FTB →
  BPU." The FTB is just a table the BPU queries.

  2. The IFU is downstream of the BPU, not upstream. The BPU leads; the IFU
  follows. The only time information flows from the IFU back toward the FTB is
  training, and that's a separate, slower loop.

  So there are really two loops, not one ring.

  Loop 1 — prediction (fast, every cycle, BPU-internal)

          +----------------------------------------------------------------+
          |                       BPU (Predictor)                          |
          |  s0_pc --> [ FTB, uFTB, TAGE, SC, ITTAGE, RAS ] --> prediction |
          |     ^                                                  |       |
          |     +---------------- npcGen (target) -----------------+       |   <- self-feeds its
          |                            |                                   |      own next PC
          +----------------------------------------------------------------+
                                       |
                                       | resp (BranchPredictionResp), gated by resp.ready
                                       v
                                     [ FTQ ]           <- elastic buffer
                                       |
                                       | FetchRequest (start PC, ftqIdx, ...)
                                       v
                                     [ IFU ] -> ICache -> IBuffer -> backend

  The steady-state loop is BPU → BPU: the BPU predicts block N, produces the
  target that becomes block N+1's start PC, and feeds that back into its own
  s0_pc (the npcGen mux from the last section). It pushes each prediction into
  the FTQ and keeps running ahead. The FTQ hands fetch start-PCs to the IFU
  whenever the IFU/ICache are ready. The IFU does not talk to the BPU or FTB in
  this loop.

  Loop 2 — training / correction (slow, only on new branches or mispredicts)

  This is the only path where the IFU feeds back toward the FTB:

  [ IFU predecode ]  (first stage that actually decodes bytes)
       | pdWb (PredecodeWritebackBundle: where the branches really are)
       v
  [ FTQ ] -- FTBEntryGen --> builds/updates an FTBEntry
       |
       +-- update  (BranchPredictionUpdate.ftb_entry) --> writes FTB in BPU
       +-- redirect (on mispredict) ----------------------> resteers BPU s0_pc

  The IFU predecode discovers "there's actually a branch at offset K," the FTQ
  turns that into an FTB entry via FTBEntryGen, and it's written back into the
  FTB through update. On a mispredict, redirect also snaps the BPU's s0_pc onto
  the correct path. Backend commit does the final training of the FTB and the
  directional predictors.

  The corrected one-liner

  If you want a single ring, it's:

  BPU (reads FTB) → FTQ → IFU → [predecode/commit] → FTQ → BPU.update/redirect →
  FTB

  - Forward (prediction): BPU → FTQ → IFU — fast, autonomous, FTB read
  internally.
  - Backward (training): IFU → FTQ → BPU/FTB — occasional, only to
  correct/teach.

  The reason it's built this way: the fast loop never waits on decode. The BPU
  runs ahead generating fetch targets, the FTQ absorbs the slack, and the slow
  decode/commit feedback only nudges the FTB when the prediction was incomplete
  or wrong. Your "IFU → FTB → BPU → FTQ → IFU" collapses both loops into one and
  puts decode on the critical prediction path — which is exactly what the
  decoupled design avoids.

❯ so then s0_pc is set to 0 on reset, that gets looked up in the FTB, it        
  misses, what happens ? explain to me like i am barely skilled.                
  
● Great question, and there's one small thing to fix in the premise first,
  because it matters:

  s0_pc is not set to 0 on reset — it's set to the reset vector. That's the
  fixed address burned into the hardware where the CPU begins fetching after
  power-on/reset (often something like 0x80000000, set by io.reset_vector in the
  code). It's usually not 0. Everything else in your question is exactly right,
  so let's walk the cold-start.

  Think of the BPU as a person guessing what's on each page of a book without 
  reading it, using only notes they've taken on previous passes. On the very
  first pass, the notebook (the FTB) is blank.

  Step by step, cold start

  1. Reset. s0_pc = reset vector, say 0x80000000. The BPU is about to "guess"
  what the block of instructions starting there looks like.

  2. Look it up in the FTB. It misses. The FTB is empty, so there's no note
  saying "a branch lives in this block." The lookup returns hit = false.

  3. What does the BPU do on a miss? It makes the safe default guess: "no branch
  here — the code just runs straight through."
  - br_taken_mask = all zeros (nothing taken)
  - predicted next PC = fall-through = start + one fetch block (i.e. 0x80000000 
  + block_size)

     In plain terms: "I have no notes on this address, so I'll assume it's a
  plain sequential block with no branch, and the next thing to predict is simply
  the block right after it." That's the only sane default — it can't invent a
  branch it has never seen.

  4. The BPU keeps walking forward. Next cycle s0_pc = 0x80000000 + block_size,
  look it up, miss again, guess fall-through again, and so on. So right after
  reset the BPU just marches sequentially through memory, guessing "no branches
  anywhere," because everything misses in the cold FTB. It streams these guesses
  into the FTQ, which hands them to the IFU to actually fetch.

  5. Now the truth arrives — from the IFU. The IFU fetches the real bytes from
  the I-cache and predecodes them (this is the first place anything actually
  looks at the instructions). Suppose the block at 0x80000000 really did contain
  a taken branch at, say, offset 3. Two things happen:

  - Correction (redirect): The BPU guessed "fall-through," but the branch was
  taken. That's a misprediction. The front end throws away the wrong-path blocks
  it already fetched and snaps s0_pc to the correct target via a redirect.
  (Cost: a few wasted cycles — the "warm-up penalty.")
  - Learning (update): The predecode result (pdWb) travels to the FTQ, which
  builds a new FTB entry — "block 0x80000000 has a branch at offset 3, target =
  X" — and writes it into the FTB.

  6. The notebook now has a note. The next time the BPU predicts 0x80000000, the
  FTB hits. Now it immediately knows the branch is there and predicts taken +
  target correctly — no misprediction, no redirect, no wasted cycles. Full
  speed.

  The big picture

  Cold start is a warm-up period: the first time through any piece of code, the
  BPU guesses "straight through," gets corrected by the real decode, and records
  what it learned. After a pass or two the FTB is "warm," and from then on the
  BPU predicts that code accurately and runs ahead of fetch — which is the whole
  point of the design.

  So the honest answer to "it misses, what happens?" is:

  ▎ It defaults to predicting a plain sequential block (no taken branch). If 
  ▎ that guess turns out wrong once the instructions are decoded, the front end 
  ▎ pays a redirect to correct course, and the FTB is updated so the same 
  ▎ mistake isn't made next time.

  That "guess safe → get corrected → remember" cycle is exactly the two loops
  from the diagram: the fast loop makes the guess, the slow loop teaches the
  FTB.


