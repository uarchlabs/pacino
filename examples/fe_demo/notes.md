```
There is no fe_top port that asks TAGE for a prediction. The FTQ inside fe_top
  makes the request, and it does so on its own after reset. From outside, your
  control is limited to keeping the request from being held and choosing which
  PC it uses.

  The request path, all internal

  ftq_npc → ftq_pred_val_p0 / ftq_pred_pc_p0 / ftq_pred_idx_p0 → bp_cluster →
  tage.

  - Start PC. In reset, r_next_pc loads RESET_VECTOR, which is 0x8000_0000 in
    bp_defines_pkg.sv:40 (ftq_npc.sv:478).
  - Valid. The FTQ sets ftq_pred_val_p0 = ~w_hold (ftq_npc.sv:377). r_next_val
    is not a flop. The request is valid in every cycle where rstn is high and
    nothing holds it.
  - Cluster gate. bp_cluster ANDs the valid with tage_pq_not_full &
    ittage_pq_not_full (bp_cluster.sv:620-621).

  What must be true for the request to go out (w_hold = 0)

  Hold term: tage_rdy, ittage_rdy, sc_ready
  Where it comes from: SRAM init walks
  What you control at the boundary: All three must be done, not just TAGE's. In
  the testbench the +*_FAST_INIT plusargs shorten them
  ────────────────────────────────────────
  Hold term: tage_pq_not_full, ittage_pq_not_full, sc_uq_not_full
  Where it comes from: predictor queues
  What you control at the boundary: Indirect
  ────────────────────────────────────────
  Hold term: h2_ftq_full (ftq_full)
  Where it comes from: FTQ occupancy
  What you control at the boundary: Entries must drain: fetch must progress
  through the IFU, ITLB/walker and L1I, and the backend must commit with
  bkend_ftq_commit_*
  ────────────────────────────────────────
  Hold term: r1_fault_hold
  Where it comes from: a live FTQ entry faulted
  What you control at the boundary: Indirect, through a translation fault
  ────────────────────────────────────────
  Hold term: h3_ftb_upd
  Where it comes from: FTB update scheduled next cycle
  What you control at the boundary: Indirect, through training

  A stalled IFU is not a hold, because the front end is decoupled. If fetch
  never moves, though, the FTQ fills, ftq_full rises, and requests stop.

  Choosing the PC

  The only boundary input that picks the request PC is the backend redirect, arm
  1: bkend_ftq_redir_val with bkend_ftq_redir_pc, plus _idx, _pos, _self,
  _cause and _taken. Every other request PC comes from reset, a predictor
  redirect, or the p1 successor. I have not checked what the FTQ requires of
  _idx for a redirect issued just to steer the PC.

  "Slot 0" is not a separate request

  TAGE has no per-slot request. bp_cluster copies the one valid to every slot,
  and every slot gets the same block start PC (bp_cluster.sv:625, 1605-1606).
  Slot s is the s-th conditional branch in the FTB entry for that block. The
  slot 0 TAGE result is used at p2 (bp_cluster.sv:1000-1015) only when all of
  these hold:

  1. The FTB hits for the block and br0 is valid (w_ftb_br_valid_p2[0]). The
     block therefore needs an FTB entry, which only training creates: commit,
     then an FTB update.
  2. TAGE's response is ready and its branch_id matches the p2 FTQ index
     (w_tage_pred_rdy_p2[0] and the branch_id == r_idx_p2 check).
  3. The loop predictor does not claim the branch (the LP > SC > TAGE priority).

  If fe_cfg.sc_enable is set, TAGE also waits on consumer_ready
  (bp_cluster.sv:1524). That signal drops whenever the SC RAM port goes to an
  update.

  In practice: release rstn with init complete, then keep the FTQ draining. TAGE
  is looked up for every block from 0x8000_0000 onward. To see the slot 0
  direction actually used, the program needs a conditional branch that has
  trained into an FTB entry for its block. Until that happens, TAGE is looked up
  but its result is not used.


so even a request that goes to tage will block if ittage is full ?            

● Yes. There is no request that goes to TAGE alone. The FTQ sends one p0 request
  per fetch block, and bp_cluster passes it to every predictor in the same
  cycle with the same PC and FTQ index (bp_cluster.sv:620-628):

  systemverilog
  assign w_pq_rdy_p0  = tage_pq_not_full & ittage_pq_not_full;
  assign w_req_val_p0 = ftq_pred_val_p0 & w_pq_rdy_p0;
  assign w_tage_pred_val_p0   = {NUM_PRED_SLOTS{w_req_val_p0}};
  assign w_ittage_pred_val_p0 = {NUM_PRED_SLOTS{w_req_val_p0}};
  assign w_lp_pred_val_p0     = {NUM_PRED_SLOTS{w_req_val_p0}};

  The comment above that code (bp_cluster.sv:613-618) gives the reason. A
  request goes out only when every prediction queue can accept it, so no
  prediction is dropped and the predictors stay in step. Each response is
  matched to its block by FTQ index (the branch_id == r_idx_p2 check), and the
  design assumes each predictor sees the same request sequence.

  At p0 there is also no information about what the block contains. The FTB
  lookup happens later in the pipeline, so at request time the FTQ cannot tell
  whether a block has an indirect jump that needs ITTAGE. Every block is looked
  up in every predictor.

  The FTQ's hold is wider still. A full ITTAGE prediction queue blocks the
  request, and so do a full SC update queue (sc_uq_not_full) and a pending FTB
  update (h3_ftb_upd). So update traffic can also stop a request.

❯ doesnt that make the individual queues less useful ?                          

● Partly, yes. The queues absorb something different from what you might expect,
  though.

  What each queue absorbs. TAGE and ITTAGE each have one RAM port, shared
  between predictions and updates. tage_arb arbitrates that port between the
  prediction queue (PQ) and the update queue (UQ), using credits and a
  starvation count. When the port goes to an update, the prediction requests
  arriving in that cycle wait in the PQ instead of being lost. So the PQ
  separates the arrival of requests from that predictor's own port arbitration.
  It does not separate one predictor from another. The lockstep rule ties them
  together on purpose: the same request goes to every predictor in the same
  cycle, so each response can be matched by FTQ index.

  What you lose with lockstep:
  - The shallowest queue sets the depth. TAGE_PQ_DEPTH = 8 but ITTAGE_PQ_DEPTH =
    4 (bp_defines_pkg.sv:408, 522). If ITTAGE falls behind while TAGE still has
    room, the FTQ holds anyway. So the extra TAGE depth only helps while ITTAGE
    also has room. ITTAGE's parameters are still marked "TBD" there.
  - A stall anywhere stalls everything. One predictor's update traffic stops
    requests to all of them. sc_uq_not_full and h3_ftb_upd widen this further,
    and consumer_ready adds a link from SC back to TAGE.

  What lockstep buys: no prediction is ever dropped, and every predictor sees
  the same request sequence. The alternative is to let a predictor with a full
  queue skip a request. The response match (branch_id == r_idx_p2) and the
  fallback to the FTB direction when TAGE doesn't match
  (bp_cluster.sv:1000-1015) already exist for that case. The cost would be a
  less accurate prediction for that block in place of a lost request cycle.

  Which choice is better depends on how often each queue actually fills. I
  haven't measured that. The tage_pq_not_full and ittage_pq_not_full low-cycle
  counts in an fe_demo run would show whether the shared hold costs anything in
  practice.

those are not the only choices, why wouldnt it be better to block at the      
  predictors queue, once you know where it is going and that predictor is full  
  you hold.                                                                     

● You're right, that's a third option and I left it out. Its cost is timing:
  when is "where it is going" known?

  At p0 the request is only a PC. What the block contains comes from the FTB
  entry, and the FTB is read at p1 (ftq_npc.sv, the H3 comment: the request
  "would reach its FTB read at p1"). TAGE and ITTAGE start their lookups at p0,
  in parallel with the FTB, and return at p2 (tage_pred_rdy_p2). Every predictor
  gets every request because the lookups start before anyone knows which of
  them are needed.

  That leaves two ways to route by destination:

  1. Route first, then look up. Wait for the FTB entry at p1, then send the
     request only to the predictors the block needs, and hold on that
     predictor's queue alone. TAGE and ITTAGE would then start at p1 or p2 and
     finish at p3 or p4. A block whose prediction gets overridden would lose one
     or two more cycles at every redirect.
  2. Look up everywhere, but hold only on the queue that matters. Keep the p0
     lookups, but stop letting a full queue block p0. Once the FTB entry shows
     which predictors the block needs, apply backpressure for that block's slot
     only if its predictor's queue is full. A block with no indirect jump would
     never wait on ITTAGE, and a block with no FTB hit would wait on nothing.
     The cost is that a full queue then stalls a block in the middle of the
     pipeline instead of at the entrance. That needs a stall or replay mechanism
     at p2/p3, and the cluster does not have one today. The current design
     avoids needing one because it can only hold at p0.

  A cheaper middle ground is to carry the routing information one block early.
  The FTB entry or FTQ entry for block N would store which predictors block N+1
  needs, so the p0 request for N+1 arrives with a destination mask. That
  information is speculative, because it is wrong after a redirect, and a wrong
  mask causes either one unnecessary hold or one prediction lost to the FTB
  fallback.

  Option 2 does what you describe without adding latency to the prediction path.
  Whether it beats the current single hold depends on how often each queue is
  full. That still needs measuring.


❯ measure how often each queue is full in fe_demo

> i dont think the demos are representative of real code. so measuring (holds) seems not helpful. do you agree ?                                                   
  
● Yes, for the question of how often the queues fill. The fe_demo programs are
  directed scenarios, and the testbench header says so: "A DEMONSTRATION, NOT A
  VERIFICATION TESTBENCH". Each program is written to make one behaviour happen.
  How full the queues get depends on things those programs don't represent:
  - branch density per block;
  - the fraction of indirect jumps;
  - the mispredict rate;
  - commit pacing, which comes from the testbench's simple in-order backend
    model.

  Rates measured on them would not carry over to real code.

  They are still useful for two narrower purposes:
  - Mechanism. A directed scenario can fill the ITTAGE prediction queue on
    purpose and show TAGE requests being held because of it. That confirms the
    coupling exists and how many cycles one event costs.
  - Bounds. A queue fills only when updates take the predictor's RAM port.
    Updates come from committed branches, so their rate is limited by the commit
    rate. With the arbiter's credit and starvation settings, you can work out
    the worst-case hold rate without any workload.

  Representative numbers need real code, such as CoreMark, Dhrystone or SPEC
  traces, run with a realistic backend. That could be a performance model or the
  RTL with something better than the testbench's in-order backend. The project
  has neither yet, as far as I know.

❯ please look at planning/PROJECT_STATUS for the technical debt format. please  
  create a TD for this issue as part of a performance measurement exercise.     
  Emit this to the console do not change the file.   

(TD but later revised, revised version is TD186 in PROJECT_STATUS)

❯ does it seem useful to do a fe_demo scenario for your suggestion:             
  - Mechanism. A directed scenario can fill the ITTAGE prediction queue on      
    purpose and show TAGE requests being held because of it. That confirms the  
    coupling exists and how many cycles one event costs.                        
    , does this cover new ground ?   

Yes, it would cover new ground. But first I need to correct what I told you
  about the queues. I have now read the arbiters, and they don't work the way I
  described.

  Correction. In both tage_arb and ittage_arb, a prediction always gets the RAM
  port ahead of an update (BP-121, ittage_arb.sv:172-190). A prediction is never
  delayed by an update. An update gets the port only in a cycle with no
  prediction. The p0 hold comes from starvation, not from a prediction queue
  filling:

  systemverilog
  assign ittage_pq_not_full = !pq_full &&
                              !(!uq_empty &&
                                (starve_ctr_r >=
  STARVE_W'(ITTAGE_STARVE_THRESH)));

  Once an ITTAGE update has waited ITTAGE_STARVE_THRESH (2) cycles,
  ittage_pq_not_full drops for one cycle. That holds the FTQ's p0 request for
  every predictor, which gives the update its cycle. TAGE works the same way
  with a threshold of 8. A full prediction queue is probably rare or unreachable
  for ITTAGE, because nothing blocks its prediction grants. I haven't checked
  whether TAGE's response buffer and consumer_ready path can fill it.

  Two of my earlier statements were therefore wrong:
  - "The PQ absorbs requests while the port goes to an update." It doesn't,
    because updates never take the port from a prediction.
  - "The shallowest queue sets the depth." The 8 and 4 depths are not what links
    the predictors. The link is that a starving update in any predictor causes
    a one-cycle p0 bubble for all of them.

  TD#186's "The cost" paragraph says the same wrong things. I'll re-emit it if
  you want.

  Is the scenario new ground? Yes. FD-1 shows the init-ready hold, and FD-20
  shows the FTQ-full hold (H2) and counts the FTB update hold (H3, n_ftb_bub in
  fe_demo_mon.svh:484). No scenario shows the predictor-queue hold (H1), and the
  monitor doesn't count it.

  Before writing a new scenario: count the H1 holds across the existing 21 runs,
  split into pq_full and starvation, per predictor. The ITTAGE threshold is
  only 2 cycles, so FD-8 (indirect) or FD-12 (training) may already trigger it
  without showing it.
  - If one of them does: add the count to the monitor and a section to that
    scenario's doc. That's enough.
  - If none does: write a scenario with dense ITTAGE training, such as an
    indirect jump in a tight loop committing one update per iteration while p0
    issues every cycle. It would show an ITTAGE update starving,
    ittage_pq_not_full dropping, and p0 requests held for blocks that only
    needed TAGE. That is the coupling TD#186 describes, and it gives the cost
    per event.
❯ re-emit TD#186 with the corrected cost paragraph                             

(New TD 186 see PROJECT_STATUS)

❯ count the H1 holds across the 21 existing fe_demo runs   

● I counted the H1 holds in all 21 runs. There were none. No predictor hold
  stopped a p0 request in any scenario, and all 21 scenarios passed.

  How I counted. I added a counter in a scratch copy of rtl/ and
  examples/fe_demo/, with RVA_ROOT pointed at the copy and Verilator 5.048 from
  tools/bin. No project file changed. The counter starts once all three init
  readies are high. In every cycle it records which hold terms are asserted. It
  splits TAGE and ITTAGE into a full prediction queue (pq_full) versus
  starvation, and SC into a full update queue versus w_sc_hold.

  ┌────────────────────┬────────┬──────┬─────┬──────────┬─────────┬───────┐
  │      scenario      │ cycles │ p0   │ H1  │   H2     │   H3    │  R1   │
  │                    │        │ held │     │ ftq_full │ ftb_upd │ fault │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd01_reset_init    │ 6136   │ 3000 │ 0   │ 0        │ 3000    │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd02_steady        │ 184    │ 0    │ 0   │ 0        │ 0       │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd03_two_branch    │ 670    │ 192  │ 0   │ 0        │ 192     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd04_p2_override   │ 588    │ 144  │ 0   │ 0        │ 144     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd05_p3_override   │ 1068   │ 288  │ 0   │ 0        │ 288     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd06_loop_pred     │ 528    │ 176  │ 0   │ 0        │ 176     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd07_calls_returns │ 1504   │ 192  │ 0   │ 0        │ 192     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd08_indirect      │ 1221   │ 319  │ 0   │ 0        │ 319     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd09_tage          │ 1377   │ 512  │ 0   │ 0        │ 512     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd10_pd_redirect   │ 347    │ 42   │ 0   │ 0        │ 42      │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd11_be_mispredict │ 600    │ 128  │ 0   │ 0        │ 128     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd12_training      │ 549    │ 154  │ 0   │ 0        │ 154     │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd13_l1i           │ 309    │ 20   │ 0   │ 0        │ 20      │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd14_translation   │ 385    │ 131  │ 0   │ 130      │ 1       │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd15_faults        │ 800    │ 311  │ 0   │ 308      │ 4       │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd16_page_cross    │ 212    │ 7    │ 0   │ 7        │ 1       │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd17_rvc           │ 370    │ 40   │ 0   │ 0        │ 40      │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd18_uncached      │ 898    │ 14   │ 0   │ 0        │ 14      │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd19_fencei_cbo    │ 355    │ 13   │ 0   │ 0        │ 13      │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd20_backpressure  │ 637    │ 331  │ 0   │ 324      │ 40      │ 0     │
  ├────────────────────┼────────┼──────┼─────┼──────────┼─────────┼───────┤
  │ fd21_commit        │ 302    │ 42   │ 0   │ 0        │ 42      │ 0     │
  └────────────────────┴────────┴──────┴─────┴──────────┴─────────┴───────┘

  The TAGE, ITTAGE and SC columns, both full and starvation, were zero in every
  run. The H2 and H3 counts are nonzero, so the counter was reading live
  signals.

  What this shows:
  - H1 never fired. FD-8 trains ITTAGE 67 times, and ITTAGE's starvation
    threshold of 2 was never reached.
  - The FTB update hold (H3) is the p0 cost in these programs. It accounts for
    37% of cycles in fd09 and about 26% in fd08 and fd04. In every scenario
    except fd14-fd16 and fd20, it is the only cause of held requests.
  - A likely reason H1 never fires, not verified: a branch's predictor updates
    arrive at commit together with its FTB update. The H3 bubble is a cycle with
    no request, so TAGE, ITTAGE and SC may drain their update queues in that
    same free cycle before starvation is reached. Checking this needs a trace of
    update arrival against the H3 cycles.
  - fd01 looks odd: H3 holds 3000 of 6136 cycles. I haven't looked into why.
  
  For TD#186, this means the shared H1 hold costs nothing in these programs,
  though they are not representative. H3 is the hold they do pay for. That is
  the one-cycle-per-FTB-update rule from BP-121/TD#162, and it is a separate
  item from TD#186.

❯ find out why fd01 has 3000 H3 holds   

The 3000 H3 holds in fd01 are not a fault. fd01's program runs a loop 3000
  times with one conditional branch per iteration. Every resolved branch
  produces one FTB update, and every FTB update costs one p0 bubble.

  The chain:
  1. Program. programs/fd01_reset_init.svh sets FD01_ITERS = 3000. Each
     iteration is W.mixed(6) plus one bcc back to the top, so 3000 conditional
     branches resolve.
  2. Every resolved branch is sent to the FTB. In ftq_resolve.sv:539-541,
     ftb_upd_val is set for every accepted resolution whose br_type is not
     NO_BRANCH. That includes a branch that hit in the FTB and was predicted
     correctly.
  3. The scheduler issues that update. In ftq_ftb_sched.sv, a correctly
     predicted hit is a LOW-value update, "a routine conf step" (5.7.2). A LOW
     update is dropped only when another update is pending and the one-deep skid
     is full (S5). With one branch per iteration that never happens, so every
     update issues.
  4. Each issue holds p0 for one cycle. issue_next becomes h3_ftb_upd in
     ftq_npc. The FTB has one read port and the update uses it, so the p0
     request in the cycle before is withheld (BP-121, TD#162).

  3000 branches gives 3000 updates and 3000 bubbles, an exact match.

  The same rule explains the H3 column in the other scenarios. Their counts
  follow how many branches each program resolves.

  TD#162 already records this cost: "Costs one p0 bubble per FTB update". What
  the count adds is the size of it. Because correctly predicted branches also
  update, the cost is one bubble per resolved branch. In fd01 that is 3000 of
  6136 cycles, about half the request slots, because each iteration is about one
  fetch block. Any one-block loop would lose prediction bandwidth at about that
  rate.

  I didn't check whether the FTB write changes anything for a hit that was
  already predicted correctly, for example a confidence counter that is already
  saturated. If it doesn't, skipping that update would remove the bubble without
  changing what the FTB learns. Answering that needs a read of ftb_cntrl.sv.


❯ check whether the FTB write changes anything on a correct hit  

● The FTB metadata the FTQ keeps doesn't include the confidence counter. To get
  a number instead of an inference, I'm counting identical writes directly in
  the scratch sims.

Usually it changes nothing. Out of 5322 FTB updates across the 21 runs, 4300
  (81%) wrote back exactly the entry that was already there. In every one of
  those cases the PLRU touch also left the replacement state unchanged. Without
  fd01 the figure is 1305 of 2322 (56%).

  How I checked. I read ftb_cntrl.sv and added a second counter to the same
  scratch copy. For every cycle with upd_active, it compares upd_new (the
  write-back entry) with upd_old (the entry read from the carried way) on a hit,
  and upd_plru_next with plru_rd_plru. All 21 runs passed. No project file
  changed.

  What a hit-update writes (ftb_cntrl.sv:446-560):
  - conf of the resolving conditional. This is a saturating 3-bit step toward
    the resolved direction. A fill starts at 100 for taken or 011 for not taken.
    Once the counter is saturated (111 or 000), the step writes the same value.
  - tgt, stat and pos of that field. These are rewritten from the update. For
    the same direct branch they are the same values.
  - pft. Rewritten on every update. The comment says an unchanged boundary
    "stores the same value (harmless)".
  - The jump field. Rewritten in full. For a direct jump it doesn't change. For
    an indirect jump, the target changes whenever the resolved target differs
    from the stored one, even when ITTAGE predicted it correctly.
  - The PLRU mark-used. The prediction lookup already marked the same way, so
    the update's mark usually changes nothing.

  ┌────────────────────┬─────────┬───────────┬───────────────┬───────────────┐
  │      scenario      │ updates │ unchanged │ cond: upd /   │ jump: upd /   │
  │                    │         │           │   unchanged   │   unchanged   │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd01_reset_init    │ 3000    │ 2995      │ 3000 / 2995   │ 0 / 0         │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd03_two_branch    │ 192     │ 106       │ 120 / 60      │ 72 / 46       │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd04_p2_override   │ 144     │ 108       │ 128 / 95      │ 16 / 13       │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd05_p3_override   │ 288     │ 120       │ 288 / 120     │ 0 / 0         │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd06_loop_pred     │ 176     │ 136       │ 176 / 136     │ 0 / 0         │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd07_calls_returns │ 192     │ 64        │ 48 / 17       │ 144 / 47      │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd08_indirect      │ 319     │ 76        │ 120 / 0       │ 199 / 76      │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd09_tage          │ 512     │ 437       │ 512 / 437     │ 0 / 0         │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd11_be_mispredict │ 128     │ 62        │ 64 / 0        │ 64 / 62       │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd12_training      │ 154     │ 89        │ 112 / 63      │ 42 / 26       │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd20_backpressure  │ 40      │ 34        │ 40 / 34       │ 0 / 0         │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ fd21_commit        │ 42      │ 31        │ 6 / 1         │ 36 / 30       │
  ├────────────────────┼─────────┼───────────┼───────────────┼───────────────┤
  │ other 9            │ 135     │ 42        │               │               │
  └────────────────────┴─────────┴───────────┴───────────────┴───────────────┘

  In fd01, the only 5 writes that changed anything were the first allocate
  (miss), three conf steps from 100 to 111, and the final not-taken exit.

  What this means for the bubble. The bubble comes from the update's read of the
  carried way, not from its write. So suppressing the write inside the FTB
  would remove nothing. The skip has to be decided in the FTQ, before the
  scheduler issues the update. The FTQ can't decide it today, because
  ftb_pred_meta_t carries only hit, way and jmp_pos, not conf. Two changes would
  cover the common case:
  - Conditional branches: carry the predicted conf per slot (3 bits) in the FTQ
    metadata. Skip when the update hit in place, conf is saturated in the
    resolved direction, and the branch's target and the block end are unchanged.
  - Jumps: skip a direct jump on a hit with the same position and type. An
    indirect jump needs the stored target, which is costly to carry, or it is
    always written.

  This is the same coupling as TD#186, with H3 in the role of H1. Would you like
  it added to TD#186's options, or drafted as a separate TD?

❯ draft it as a separate TD  

❯ lets draft this as two TD's, I will have a prompt here shortly for            
  implementation of the counter in fe_demo_mon.svh and subsequent performance   
  analysis for the other td.                                                    
  
● I'm assuming the split is: TD#187 stays as the design question, and a new
  TD#188 covers adding the counters to fe_demo_mon.svh. TD#187 then points to
  TD#188 for the instrumentation and drops the paragraph I offered. Both rows
  are formatted to the table width, ASCII only, 80 columns or fewer.

  TD#187, revised. The only change from the earlier draft is the last paragraph.

  | 187 | ftq, bpu | OPEN, PERFORMANCE. FTB UPDATES THAT CHANGE NOTHING STILL |
  |     |          | COST A p0 BUBBLE. Every accepted resolution with br_type |
  |     |          | not NO_BRANCH is sent to the FTB (ftq_resolve.sv         |
  |     |          | ftb_update), including a hit that predicted correctly    |
  |     |          | (LOW, ftq_decisions.md 5.7.2). ftq_ftb_sched issues it   |
  |     |          | whenever the one-deep skid has room, and each issue      |
  |     |          | withholds one p0 request (h3_ftb_upd, TD#162). The       |
  |     |          | bubble comes from the update's read of the carried way,  |
  |     |          | so suppressing the write inside ftb_cntrl removes        |
  |     |          | nothing; the skip has to be decided in the FTQ, before   |
  |     |          | issue.                                                   |
  |     |          |                                                          |
  |     |          | MEASURED, session-080, scratch counter on the 21 fe_demo |
  |     |          | runs (upd_new == upd_old on a hit, and upd_plru_next ==  |
  |     |          | plru_rd_plru): 4300 of 5322 FTB updates wrote back the   |
  |     |          | entry already stored, PLRU unchanged in every one; 1305  |
  |     |          | of 2322 without fd01. fd01: 3000 updates, 2995 unchanged |
  |     |          | (one allocate, three conf steps 100 -> 111, one exit),   |
  |     |          | 3000 bubbles in 6136 cycles. For a branch already stored |
  |     |          | in the entry, the write changes only its conf until it   |
  |     |          | saturates, an indirect jump's target when the resolved   |
  |     |          | target differs, or a changed block end.                  |
  |     |          |                                                          |
  |     |          | The FTQ cannot decide the skip today: ftb_pred_meta_t    |
  |     |          | carries hit, way and jmp_pos, not conf.                  |
  |     |          |                                                          |
  |     |          | Options, none ruled:                                     |
  |     |          |   - carry the predicted conf per slot (FTB_CONF_WIDTH, 3 |
  |     |          |     bits) in ftb_pred_meta_t; skip a conditional update  |
  |     |          |     that hit in place with conf saturated in the         |
  |     |          |     resolved direction and an unchanged block end        |
  |     |          |   - skip a direct jump update on a hit with the same     |
  |     |          |     position and type; an indirect jump is always        |
  |     |          |     written, or carries its stored target                |
  |     |          |   - a second FTB read port for updates; area             |
  |     |          |                                                          |
  |     |          | The hold of TD#162 is unchanged by any of these; they    |
  |     |          | issue fewer updates. The fe_demo programs are not        |
  |     |          | representative (Jeff); the fraction on compiled          |
  |     |          | benchmarks decides the value. Counters: TD#188.          |
  |     |          | Related: TD#186 (the same p0 coupling through H1),       |
  |     |          | TD#80 (FTB conf tuning), TD#179. Opened session-080      |
  |     |          | (Jeff).                                                  |

  TD#188, new.

  | 188 | fe_demo  | OPEN, VERIFICATION. THE p0 HOLD AND FTB WRITE COUNTERS   |
  |     |          | IN fe_demo_mon.svh. Measurement support for TD#186 and   |
  |     |          | TD#187; a session-080 scratch copy built them outside    |
  |     |          | the tree. Counted after the three init readies are high: |
  |     |          |   - p0 held cycles, and per cause: H1 per predictor      |
  |     |          |     (TAGE and ITTAGE split pq_full vs starvation, SC     |
  |     |          |     split uq_full vs w_sc_hold), H2 ftq_full, H3         |
  |     |          |     h3_ftb_upd, R1 r1_fault_hold, and H1 with no other   |
  |     |          |     cause                                                |
  |     |          |   - FTB updates: total, miss, written back unchanged on  |
  |     |          |     a hit (upd_new == upd_old), PLRU unchanged, each by  |
  |     |          |     conditional and jump                                 |
  |     |          | The scratch values to reproduce: H1 0 in all 21 runs;    |
  |     |          | FTB unchanged 4300 of 5322, fd01 2995 of 3000.           |
  |     |          |                                                          |
  |     |          | Constraints: printed through say() in the FDT-10a format |
  |     |          | (DOC-003), not $display; the scratch counter printed     |
  |     |          | from a final block outside the format. No blocking       |
  |     |          | assignment in a clocked block (the scratch copy          |
  |     |          | suppressed BLKSEQ). The H1 split and the FTB compare     |
  |     |          | read internals by hierarchical reference (u_tage_arb,    |
  |     |          | u_ittage_arb pq_full; u_bpu w_sc_hold,                   |
  |     |          | w_sc_uq_not_full_int; u_ftb_cntrl upd_new, upd_old,      |
  |     |          | upd_plru_next, plru_rd_plru). n_ftb_bub already counts   |
  |     |          | H3. fe_demo_tb_decisions.md has no entry for these       |
  |     |          | counters; the PA drafts one. Opened session-080 (Jeff).  |


