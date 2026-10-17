Both runs finished. The 2-slot tree passed all 21 scenarios. The 1-slot tree
  passed 19 and failed 2. The "failed" status on the background job came from a
  mistake in my final tail command; it doesn't reflect either run's result. Each
  run's own exit code is in its log: 0 for two slots, 2 for one slot.

  The 2-slot scratch run matches the project. For example, fd09 ends at cycle
  1277, as its doc says. That makes it a fair baseline. fd03 reporting 0 blocks
  with both slots valid confirms the 1-slot build really was one slot.

  ┌───────────────────────────┬──────────────────────┬──────────────────────┐
  │         Scenario          │       2 slots        │        1 slot        │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │ fd01, fd02, fd06, fd10,   │                      │ PASS, identical      │
  │ fd13-fd16, fd18-fd21      │ PASS                 │ figures and cycle    │
  │                           │                      │ counts               │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │                           │ PASS, both-slot      │ FAIL, 0/0, cyc 915   │
  │ fd03_two_branch           │ blocks 127/87, cyc   │ (expected: it needs  │
  │                           │ 570                  │ two slots)           │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │ fd04_p2_override          │ p2 redirects 38, cyc │ PASS, 83, cyc 558    │
  │                           │  488                 │                      │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │ fd05_p3_override          │ p3 redirects 49 (49  │ PASS, 56 (56 SC),    │
  │                           │ SC), cyc 968         │ cyc 1138             │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │                           │ pushes 76, highest   │ FAIL, pushes 45,     │
  │ fd07_calls_returns        │ recursion 8, cyc     │ highest recursion 0, │
  │                           │ 1404                 │  cyc 1538            │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │ fd08_indirect             │ ITTAGE predictions   │ PASS, 19, cyc 1661   │
  │                           │ 67, cyc 1121         │                      │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │                           │ tagged 216,          │ PASS, 253 / 209 /    │
  │ fd09_tage                 │ allocations 65, uaon │ 75, cyc 3567         │
  │                           │  37, cyc 1277        │                      │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │                           │ redirects 20,        │ PASS, 22 / 210, cyc  │
  │ fd11_be_mispredict        │ rollbacks 139, cyc   │ 624                  │
  │                           │ 500                  │                      │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │ fd12_training             │ cyc 449              │ PASS, same update    │
  │                           │                      │ counts, cyc 541      │
  ├───────────────────────────┼──────────────────────┼──────────────────────┤
  │ fd17_rvc                  │ cyc 270              │ PASS, same counts,   │
  │                           │                      │ cyc 281              │
  └───────────────────────────┴──────────────────────┴──────────────────────┘

  fd07's failure. Its proof requires max_rctr > 1, meaning the RAS recursion
  counter has to exceed 1 (fe_demo_proofs.svh:79). At one slot it stays 0, and
  there are fewer pushes (45 against 76). I haven't looked into why.

  What this says about your proposal:

  1. Eleven scenarios behave identically at one slot. Every figure and cycle
     count matches: fd01, fd02, fd06, fd10, fd13, fd14, fd15, fd16, fd18, fd19,
     fd20 and fd21. These could switch to the 1-slot build with no doc changes
     beyond the removed slot 1 rows.
  2. Seven pass with different numbers: fd04, fd05, fd08, fd09, fd11, fd12 and
     fd17. Their docs would need new event tables, markers and figures. fd09
     changes the most: the run is 2.8 times longer and allocations go from 65 to
     209, so its walkthrough would have to be rewritten. fd05 still shows its
     SC reversals at one slot, so it doesn't have to stay dual-slot as I thought
     earlier. fd08's ITTAGE predictions drop from 67 to 19, so its main event
     becomes much weaker.
  3. Two fail: fd03 as expected, and fd07, which is unexplained. Both would stay
     in the 2-slot set.
  4. The FST files didn't get smaller. All 21 total 9.84 MB at two slots and
     10.06 MB at one slot, because several runs are longer. The reduction is
     only in wave rows.

  The trial trees and logs are in /tmp/claude-1000/-home-jeff-Development-jeffny
  e-gh-pacino/ba58e7aa-e7d0-4b1f-a891-17c803813c92/scratchpad/slot_trial/. The
  run outputs are two.run and one.run there, and each tree's
  examples/fe_demo/out/ has the per-scenario logs and FSTs. Nothing in the
  project was changed.

