# Note to the PA: fe_demo waveform simplification, inputs for a DOC- task

From:   IA, interactive session 2026-10-17
Source: tree at ab80cfe; 1-slot trial in scratch (no project file
        changed); signal widths read from out/fd09_tage/fd09_tage.fst
        through waves/fe_demo_sigs.fst_names.
Goal (Jeff): simpler waveforms, so a reader skilled in branch
        prediction understands each predictor sooner. Two slots are
        interesting but not needed to understand loop, uBTB, FTB,
        TAGE, TAGE+SC, ITTAGE and RAS.

---

## A. Decisions for Jeff before the task is written

A1. FDT-5 says "NUM_PRED_SLOTS = 2. No 1-slot build." The change below
    reverses it: the default demo build is 1 slot, and a second 2-slot
    build serves the dual-slot scenarios. FDT-5 needs redrafting.
A2. FDT-12a says every non-enum signal other than clk, rstn and cyc
    takes the format fe_demo_sigs.radix gives it, which is Binary for
    every 1-bit signal. Section C changes that rule. FDT-12a needs
    redrafting.
A3. fd07 (RAS) cannot move to 1 slot until defect D1 is fixed
    (misc/pa_note_fd07_slot1.md): at 1 slot the call in block f is
    never presented to the RAS and the proof fails. Either sequence
    the DOC task after the D1 fix, or keep fd07 in the 2-slot set until
    then. Rewriting fd07's program to avoid {cond, call} in one block
    would hide D1 and is not suggested.

## B. Slot count

B1. Build. The Makefile builds the 1-slot model by default
    (+define+BP_NUM_PRED_SLOTS=1 +define+BP_EXPECT_PRED_SLOTS=1) and a
    2-slot model in a separate object directory. Each scenario names
    the build it runs on.
B2. Scenario sets, by the 1-slot trial:
    - 1 slot, figures identical to 2 slots (12): fd01, fd02, fd06, fd10,
      fd13, fd14, fd15, fd16, fd18, fd19, fd20, fd21. (fd21: re-check
      after D2 is fixed; it shows the RAS.)
    - 1 slot, passes with different figures (7): fd04, fd05, fd08, fd09,
      fd11, fd12, fd17. Their result lines, walkthroughs and event
      tables must be re-derived from the 1-slot run; the markers
      follow from the tables.
    - 2 slots: fd03_two_branch (fails at 1 slot by design), and fd07
      until A3 is resolved.
    Predictor coverage at 1 slot: uBTB fd02/fd04 (p1), FTB fd04 (p2
    override), TAGE fd09, TAGE+SC fd05, ITTAGE fd08, loop fd06, RAS fd07
    (after D1).
B3. New 2-slot scenarios ("a few complex scenarios"), for the PA to
    define. Candidates the trial suggests:
    - two conditionals in one block, the second predicted by a
      different component than the first (TAGE in slot 0, SC override
      in slot 1 at p3);
    - a block {cond, cond, jump}: shows the slot policy the D1 fix
      chooses when branches exceed slots;
    - a call in slot 1 behind a not-taken conditional in slot 0 (RAS
      push from slot 1).
B4. Signal lists. fe_demo_sigs.py writes slot indices 0 and 1 by hand
    (slots(arr, n=2), redir() range(2), the RAS, TAGE, SC, ITTAGE, loop
    and uBTB-update lists). These must follow the build's slot count.
    mk_sucl.py stops on a name not in the FST, so a 1-slot FST fails
    the current generator; the slot count can be read from the FST
    (presence of index [1]) rather than passed in.
B5. Effect on rows: about 137 of the 1072 rows across the 21 files are
    slot 1; all are in fd02-fd09, fd12, fd21. Per scenario, for
    example: fd06 84 -> about 58, fd05 66 -> about 43, fd09 56 -> about
    32. FST size does not drop: 9.84 MB (2 slots) vs 10.06 MB (1 slot)
    for all 21. The gain is rows on screen, not disk.
B6. docs/demo_explainer.md: a short section saying the demo runs at
    1 slot, what a slot is, and which scenarios use 2. README.md
    scenario list marks the 2-slot scenarios.

## C. Formats

The rule in fe_demo_sigs.radix is: width 1 -> Binary; width > 8 or a
name matching pc|addr|target|... -> Hexadecimal; else Unsigned. As
built that gives:

C1. 1-bit signals shown Binary: 445 rows of 1010 checked. Change to
    Bit (the format tb.rstn already uses).
C2. Multi-bit valid/ready masks, one bit per slot or lane, shown as a
    number:
      Hexadecimal: tb.bkend_ftq_rsv_val, tage_upd_val_u0 (u_tage_cntrl),
                   w_tage_upd_val_u0, w_ittage_upd_val_u0,
                   w_sc_upd_val_u0, w_lp_upd_val_p0, ifu_ibuf_en (16)
      Unsigned:    w_tage_pred_rdy_p2, w_ittage_pred_rdy_p2,
                   w_sc_pred_rdy_p3, bpu_tage_upd_rdy,
                   tb.ftq_bkend_rsv_rdy
    Proposed rule: a per-slot or per-lane mask is Binary. At 1 slot
    the 2-bit masks become 1 bit (Bit under C1); ifu_ibuf_en stays a
    16-bit mask.
C3. Counts shown Hexadecimal because width > 8: lp_curs and
    lp_past_itr (14 bits, loop iteration counts, fd06). Proposed rule:
    a count or iteration number is Unsigned at any width. The SRAM
    init write addresses (u_sram_init.waddr, fd01) are the PA's call.
C4. Encoded fields with no FST enum table, shown Unsigned:
    itlb_ifu_status, itlb_ifu_cause, tb.l2t_itlb_status,
    tb.itlb_l2t_priv (fd14, fd15), and trx_type (1 bit, fd09). Surfer
    can only show Enum where Verilator wrote an enum table. Options:
    retype the field as an enum (an RTL or tb change, outside a DOC
    task), or keep Unsigned and give the encoding in the scenario
    description.
C5. The rule should be a table in fe_demo_sigs.py (signal or pattern ->
    format) rather than a width/name heuristic, so a reviewer can read
    each signal's format directly. chk_sucl.py checks the files
    against it.

## D. Further simplification (optional, PA's call)

Large groups after B: fd02 decode (8 lanes x valid/start_pc, 16 rows),
fd06 loop_pred_p1_p2 (p1 and p2 copies of the same 6 fields), fd17
decode (8 lanes x 3). Each could show fewer lanes or one stage, if the
description does not walk through the omitted rows.

## E. Dependencies

- D1 fix before fd07 moves to 1 slot (A3).
- D2 fix changes fd07 and possibly fd21 (the wrong-path fetch to 0x0
  disappears); re-derive their descriptions after it.
- Regenerate all .sucl files and run chk_sucl.py after B and C.
