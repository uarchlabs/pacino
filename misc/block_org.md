<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

frontend
  I$/ITLB/IPrefetcher
  FTQ (fetch target queue, aka bpq)
  IFU/Predecode/Branch Detector
  IBUF (instruction buffer)
  Decode
  BPU: uFTB/RAS/FTB/TAGE/SC/ITTAGE/LOOP
  Fusion/NOP filter

dispatch
  Rename
    RAT
    ARMT
    FreeList
  I/F/V/MM PRF
  ROB
  RS (I/F/V/LD-ST/MM)
  Scheduler
  Scoreboard
  CSR
  Trap/Exception

execute
  Integer (inc. branch)
  Float
  Vector
  Matrix (MM)
    Tile Register File
  Atomics Unit

lsu
  AGU
  Load Queue (LQ)
    virtual load queue
    ldqueue RAR
    ldqueue RAW
    ldqueue replay
  Store Queue (SQ)        speculative
  Store Buffer (SB)       committed
  Store-to-Load Forwarding
  Exception Buffer
  Uncache Buffer          MMIO/non-cacheable
  L1D$
    MSHR
    Writeback Queue
  DTLB
  Tile Load/Store Unit    MM dedicated path
  VLSU                    vector coprocessor memory path
    VSplit
    VMerge
    VSegmentUnit
    MisalignBuffer
    VfofBuffer

memory
  L2
  L3
  Prefetcher
  CCI (TileLink)

PMU
MMU (distributed)

