# Decoupled/Out-of-Order Front-End Organizations for Microprocessors

## Front-End Organization Taxonomy

| Organization | Authors / Venue | Core Mechanism | Problem Targeted | Key New Structure | Notable Limitation |
|---|---|---|---|---|---|
| **W16 (sequential baseline)** | — | Fetch N contiguous bytes/cycle, stop at first predicted-taken branch | — (baseline) | Wide I-cache port | Bandwidth collapses on taken branches / poor code density |
| **Collapsing Buffer** | Conte, Menezes, Mills, Patel — ISCA'95 | Banked I-cache stitches a few non-adjacent lines into one fetch | Taken-branch fetch discontinuities | Multi-bank I-cache + alignment logic | Generally underperforms trace cache; limited to nearby discontinuities |
| **BBTB (Basic Block Target Buffer)** | Yeh & Patt | Predicts whole basic blocks, not single branches | Fetch-block boundary detection | BBTB structure | Still tightly coupled to fetch; no lookahead queue |
| **Multiple-Block-Ahead predictor** | Seznec, Jourdan, Sainrat, Michaud — ASPLOS'96 | Predicts several blocks per cycle from one structure | Prediction throughput | Wide-output predictor | Predictor complexity scales with lookahead width |
| **Trace Cache** | Rotenberg, Bennett, Smith — MICRO'96 | Caches instructions in dynamic execution order | Taken-branch + discontinuity fetch bandwidth | Trace cache (parallel to I-cache) | Redundant storage across overlapping traces; cold-trace misses |
| **Block-Based Trace Cache** | Black, Rychlik, Shen — ISCA'99 | Trace cache built from reusable basic-block segments | Trace-cache storage redundancy | Segmented trace cache | Extra indirection to assemble segments |
| **Software Trace Cache** | Ramirez et al. | Reorders code at compile/link time for sequential-like locality | Same as trace cache, no hardware cost | Compiler pass only | No adaptivity to runtime behavior |
| **SRP out-of-order fetch** | Stark, Racunas, Patt — MICRO'97 | Lockup-free I-cache; predictor keeps predicting during a miss; results land in reservation stations out of order | I-cache **miss** stalls specifically | Result/fetch reorder logic (no queue) | No prefetch, no predictor pipelining; benefit vanishes once instruction window fills |
| **RCA decoupled front-end (FTQ)** | Reinman, Calder, Austin — ISCA'99 / MICRO'99 / TC'01 | FTQ inserted between predictor and I-cache; predictor races arbitrarily far ahead | I-cache misses **+** enables prefetch **+** predictor pipelining | Fetch Target Queue (FTQ) + FTB | FTQ sizing, squash/refill logic on mispredict, more state overall |
| **BLISS (Block-aware ISA)** | — | ISA carries explicit basic-block descriptors | Removes need for dynamic block-boundary detection | ISA extension | Requires ISA/compiler cooperation, not retrofittable |
| **Multiscalar** | Sohi, Breach, Vijaykumar — ISCA'95 | Program split into tasks; each task fetched/executed on its own PE in parallel | Whole-pipeline parallelism (front end is a side effect) | Task predictor + multiple PEs | Task partitioning quality drives everything; heavyweight machine |
| **Parallel Fetch / Parallel Fetch+Rename (PF/PR)** | Oberoi & Sohi — ICPP'02 / ISCA'03 | Several independent sequencers fetch predicted fragments in parallel into per-sequencer buffers; PR also parallelizes rename | Front-end bandwidth **and** I-cache-capacity pressure | Fragment predictor + N fetch units + fragment buffers (+ parallel renamer for PR) | Fragment misprediction cost; inter-fragment rename dependencies (solved in PR) |
| **Skipper** | Cher & Vijaykumar — MICRO'01 | Fetch skips low-confidence/hard-to-predict regions, fills them in later speculatively | **Control independence**, not just misses | Confidence estimator + skip/backfill logic | Backfill correctness/recovery complexity |
| **Block-Based OoO Fetch** | Oberoi (dissertation proposal) | Treats cache blocks like instructions in an OoO issue window — a scheduler picks which predicted-but-unfetched block to fetch next | Generalizes PF/PR to fine (block) granularity, dynamic scheduling | Block "issue window" + scheduler | Proposed/exploratory — less validated than the above |

---

## Side-by-Side: Oberoi/Sohi (PF, PR) vs. Skipper

| Dimension | Parallel Fetch (PF) | Parallel Fetch+Rename (PR) | Skipper |
|---|---|---|---|
| **What stalls it. What it fixes** | Sequential fetch bandwidth loss from taken branches and small-cache pressure | Same as PF, plus the serialization PF reintroduces at rename | Fetch/issue stalls caused by *specific* hard-to-predict branches (low-confidence regions), i.e. control dependence |
| **Granularity of parallelism** | Coarse: whole predicted "fragments" (Multiscalar-style tasks), each fetched by its own sequencer | Same fragment granularity as PF, but rename is also parallelized across fragments | Fine: individual low-confidence branch regions are skipped, not whole fragments |
| **New structures added** | Fragment predictor, multiple fetch units, per-fragment fetch buffers | All of PF's structures + a parallel/distributed rename mechanism | Confidence estimator on branches, mechanism to fetch past a skipped region and later backfill/verify it |
| **How correctness is recovered** | Misfetched fragment discarded like a normal misprediction | Same, but rename dependencies across fragments must also be unwound | Skipped region's outcome is resolved later; backfilled results merged back into program order — more delicate recovery than a simple squash |
| **Primary metric improved** | Sustained fetch bandwidth despite branches | Fetch bandwidth **and** removes rename as the new bottleneck once fetch is parallelized | Reduces stalls from *specific* branches rather than raw fetch bandwidth |
| **Sensitivity to I-cache size** | Explicitly evaluated under cache pressure: tolerates 128 KB → 8 KB I-cache with only ~6% IPC loss (vs. 50–65% loss for sequential/trace-cache designs) | Inherits PF's cache-size robustness; adds robustness on rename-bound workloads | Not primarily an I-cache-capacity technique — orthogonal axis |
| **Relationship to Multiscalar** | Direct descendant — applies task-style parallel fetch to a conventional monolithic OoO core instead of a clustered machine | Extends PF within the same lineage | Independent lineage — descends from SRP/decoupled-fetch ideas about tolerating specific stalls, not from task parallelism |
| **Where it loses to alternatives** | Loses to trace cache when working set is small and mispredictions are rare (trace cache's simplicity wins) | Same as PF, plus added rename complexity may not pay off if fragments rarely overlap in dependencies | If confidence estimation is inaccurate, backfill overhead can exceed the stall it was meant to avoid |
| **Best-fit workload profile** | Large code footprints, cache-constrained designs, workloads with frequent discontinuities | Same as PF, with additional benefit when back-end rename is also a bottleneck | Workloads dominated by a small number of genuinely hard-to-predict branches (rather than uniformly noisy prediction) |

---

### Sources
- G. Reinman, T. Austin, B. Calder. *A Scalable Front-End Architecture for Fast Instruction Delivery.* ISCA 1999.
- G. Reinman, B. Calder, T. Austin. *Fetch Directed Instruction Prefetching.* MICRO 1999.
- G. Reinman, B. Calder, T. Austin. *Optimizations Enabled by a Decoupled Front-End Architecture.* IEEE Trans. Computers, 2001.
- J. Stark, P. Racunas, Y. Patt. *Reducing the Performance Impact of Instruction Cache Misses by Writing Instructions into the Reservation Stations Out-of-Order.* MICRO 1997. (See also: J. Stark, *Out-of-Order Fetch, Decode, and Issue*, PhD Dissertation, Univ. of Michigan, 1999/2000.)
- P. Oberoi, G. Sohi. *Parallelism in the Front-End.* ISCA 2003.
- P. Oberoi. *Out-of-Order Front-Ends* (dissertation proposal), Univ. of Wisconsin-Madison.
- C.-Y. Cher, T. N. Vijaykumar. *Skipper: exploiting control-independence in a superscalar architecture.* MICRO 2001.
- G. Sohi, S. Breach, T. N. Vijaykumar. *Multiscalar Processors.* ISCA 1995.
- E. Rotenberg, S. Bennett, J. E. Smith. *Trace Cache: a Low Latency Approach to High Bandwidth Instruction Fetching.* MICRO 1996.

