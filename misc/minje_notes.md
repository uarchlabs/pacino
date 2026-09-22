<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# MinJie / XiangShan Notes
=============================================================

Notes on the MinJie agile development platform and the XiangShan
RISC-V processor [1], and how they relate to Pacino and the
uarchlabs methodology.

Status: notes only. No task, decision or TD entry is created by
this file. Items below are proposals for the architect to rule on.

-------------------------------------------------------------
## Context assumed
-------------------------------------------------------------

Pacino: 8-issue OoO RVA23 core, SystemVerilog, Verilator 5.020,
2.75 GHz target, built frontend first. Decoder complete. BPU
cluster (uBTB, FTB, TAGE-SC-L, ITTAGE, RAS) in RTL. FTQ, IFU, L1I
and ITLB in planning and audit. No backend, so no instruction
commit exists yet.

uarchlabs: architect sets the architecture; the PA keeps decisions
and interface documents; the IA runs numbered task prompts with
Results Capture. Handoffs, the TD table and check_planning.sh hold
state across sessions. cachegen generates the L1I from JSON.

Correct this section if it is out of date before acting on the
rest.

-------------------------------------------------------------
## Relationship to XiangShan
-------------------------------------------------------------

Pacino's frontend is structured much like XiangShan NH: a
decoupled BPU running ahead of the IFU through an FTQ, with FTB,
uBTB, TAGE-SC, ITTAGE and RAS. The pftAddr field in handoff-071
appears to be XiangShan's FTB partial-fall-through term. Pacino
already borrows the microarchitecture. It has not borrowed the
verification and evaluation platform, which is where [1] is most
useful.

-------------------------------------------------------------
## Main benefit: an independent oracle
-------------------------------------------------------------

The most important idea in [1] for uarchlabs is that the DiffTest
reference model (NEMU or Spike) is not written by whoever writes
the RTL.

Pacino testbenches are self-checking and directed, but the agent
that writes the RTL also writes the expected values. If both read
the spec the same wrong way, the error cannot be seen. This gap
was flagged in Part 1. The spike-dasm check closed it for the
decoder. DRAV closes it for the whole core.

Diff-rules and directed validation. A diff-rule is a deliberate
relaxation of equivalence, so it is where a false negative can
hide. [1] handles this only partly: it counts forced page faults
and SC failures and asserts they do not repeat, and its artifact
injects a single fault. The uarchlabs rule is stricter: a check
whose failure has never been observed is not evidence. Applied to
diff-rules, every rule ships with an injected fault that proves
the rule can fire. This would be a contribution beyond [1].

-------------------------------------------------------------
## Adoption, in the order Pacino can use it
-------------------------------------------------------------

### Now, frontend only

A1. LightSSS. The cheapest win in [1]. Roughly a page of C++
    around fork() in the Verilator harness; circuit-independent.
    CAVEAT, unverified: fork() copies only the calling thread.
    With Verilator's multithreaded model the child must rebuild
    or bypass the thread pool before replay. Check how the
    XiangShan difftest repo handles this before relying on it.

A2. Frontend-only DiffTest. Full DiffTest needs instruction
    commit, which Pacino does not have. The idea still applies
    one level down:
    - Predictions are non-architectural. No rule checks them
      directly.
    - The committed fetch stream is architectural.
    - NEMU or Spike produces the committed-path PC trace.
    - A stand-in backend drives redirects taken from that trace.
    - Check that the FTQ and IFU eventually deliver exactly that
      stream.
    Diff-rule: the frontend may fetch any wrong path, but after
    each redirect the delivered stream must converge to the REF.
    This tests the FTQ/IFU flush indexing that TD#126 concerns
    better than directed tests can.

A3. Probes generated from interface documents. [1] argues that
    designers, not verification engineers, should own extraction
    points, because monitors break whenever the design changes.
    This transfers to SystemVerilog via bind modules plus DPI-C.
    The project already requires each struct layout to live in
    one place. A small generator in the spirit of cachegen could
    emit both the SV probe package and the matching C++ checker
    struct from one definition.

### When the backend reaches commit

B1. Integrate full DiffTest with NEMU as REF.

B2. Start from the rule set in [1]: speculative page walks, LR/SC
    timeout failures, MMIO, interrupts, performance counter
    reads. RVA23 needs rules [1] does not list:
    - vector: vl/vstart behaviour on faults
    - hypervisor: two-stage translation
    - Zicbom/Zicboz

### cachegen

C1. [1] Section III-B2b treats caches as black boxes checked by
    bus-protocol rules and a permission scoreboard. This is the
    "verification as generators" model of [1] Figure 1(c).
    cachegen already knows the protocol and topology from its
    links and topology schemas, so it is well placed to emit a
    transaction checker alongside each generated cache.

### Performance

D1. The checkpoint flow in [1] (NEMU, then SimPoint, then
    parallel RTL simulation) is the practical way to get numbers
    from an 8-issue core.

D2. The PUBS case study in [1] is a caution: an idea with gains
    in a simple simulator produced nothing on a wider real core.
    Pacino's TAGE-SC-L derives from championship work that does
    not model real update latency or pipeline timing. Compare
    MPKI of the Pacino BPU RTL against a C++ TAGE-SC-L on the
    same traces, within an agreed tolerance, to show where
    timing closure cost prediction accuracy.

-------------------------------------------------------------
## Where uarchlabs differs
-------------------------------------------------------------

MinJie is tooling for a team of about thirty-five. Its bottleneck
is machine time: slow simulation, costly debug replay, and
rewriting verification code when the design changes.

uarchlabs is one architect with LLM agents. Recent sessions show a
different bottleneck: agents supplying facts they do not have.
Examples are invented quotations, counts carried forward without a
run behind them, and edits that fix the named site but not the
tree.

A MinJie-style platform for uarchlabs would pair the machinery of
[1] with things [1] never needed:

- Tree-level consistency checks. check_planning.sh is the start.
- Traceability from each diff-rule and directed test back to a
  clause in a decisions document.
- Oracle independence as a stated rule: no check may have both
  its expected and actual values produced by the agent.

Possible publication angle. [1] asks whether agile methods can
build a high-performance core. uarchlabs would ask what
verification discipline makes that possible when most of the code
is written by agents.

-------------------------------------------------------------
## Critical reading of [1]
-------------------------------------------------------------

- No measure of verification effectiveness: no bug counts,
  coverage, or time saved against a baseline.
- Figure 6 shows no overhead but gives no actual values.
- RTL-simulation scores come from sampled checkpoints and differ
  from silicon by 5 to 10 percent.

The tools are real and in use. By the uarchlabs evidence standard,
[1] supports "this works for us" more than "this is better." Pacino
could report its own results more rigorously.

-------------------------------------------------------------
## Licensing
-------------------------------------------------------------

XiangShan, NEMU and DiffTest are under the Mulan Permissive
Software License v2. Not legal advice: confirm compatibility with
Pacino's Apache-2.0 licensing before vendoring any of their code.

-------------------------------------------------------------
## References
-------------------------------------------------------------

[1] Y. Xu, Z. Yu, D. Tang, G. Chen, L. Chen, L. Gou, Y. Jin,
    Q. Li, X. Li, Z. Li, J. Lin, T. Liu, Z. Liu, J. Tan, H. Wang,
    H. Wang, K. Wang, C. Zhang, F. Zhang, L. Zhang, Z. Zhang,
    Y. Zhao, Y. Zhou, Y. Zhou, J. Zou, Y. Cai, D. Huan, Z. Li,
    J. Zhao, Z. Chen, W. He, Q. Quan, X. Liu, S. Wang, K. Shi,
    N. Sun, and Y. Bao, "Towards Developing High Performance
    RISC-V Processors Using Agile Methodology," in Proc. 55th
    IEEE/ACM International Symposium on Microarchitecture
    (MICRO), 2022, pp. 1178-1199.
    doi: 10.1109/MICRO56248.2022.00080
