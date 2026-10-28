<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
=============================================================
# LLM Hardware Design and Verification Survey Notes
=============================================================

Notes on the Abdollahi et al. scoping review of LLMs in hardware
design and verification [1], two later agent-based papers [2][3],
and how they relate to Pacino and the uarchlabs methodology.

Status: notes only. No task, decision or TD entry is created by
this file. Items below are proposals for the architect to rule on.

-------------------------------------------------------------
## Context assumed
-------------------------------------------------------------

Pacino: 8-issue OoO RVA23 core, SystemVerilog, Verilator, built
front end first. The front end (BPU cluster, FTQ, IFU, L1I, ITLB,
walker, PMP/PMA checker) is in RTL with a 274-target regress.sh.
CSR definition began with the SYS series.

uarchlabs: the architect sets the architecture; the PA keeps
decisions and interface documents; the IA runs numbered tasks
with Results Capture. Handoffs, PROJECT_STATUS, the TD table and
check_planning.sh hold state across sessions.

-------------------------------------------------------------
## What the paper is
-------------------------------------------------------------

A PRISMA-ScR scoping review. It includes 71 papers, mostly from
2023-2024, sorted into six categories:

  design 31, co-design 6, accelerators 8, security 13,
  debugging 2, verification 11

It adds a small experiment of its own: ChatGPT, Gemini and
Copilot are asked to design, debug and write a UVM environment
for an 8-bit parameterized shift register. It ends with
challenges (sec. 5), open issues (sec. 6) and recommendations
(sec. 7.2).

Use: a map of the literature as of the end of 2024. Weak as
evidence, for the reasons below.

CAUTION. The paper predates agent-based design flows and covers
mostly single-prompt use. Its challenges and open issues are
open for that mode of use, as of 2024. They should not be read as
the current state of agentic hardware design, and comparisons
with Pacino should be drawn with that in mind. See "Two agentic
papers" below for the nearer comparison.

-------------------------------------------------------------
## Problems with the paper
-------------------------------------------------------------

### The model comparison was judged by reading, not running

Nothing was compiled or simulated. The tables do not match the
figures:

  - Figure 7 is the same image as Figure 11. The "design" output
    credited to ChatGPT is its answer to the debugging prompt.
  - Table 3 says Gemini lacks WIDTH==1 handling; Figure 8 shows
    the check.
  - Gemini's design (Fig. 8) declares data_in and data_out as
    1-bit scalars. Not noted.
  - Copilot's design (Fig. 9) contains "} else begin", a syntax
    error. Not noted.
  - Figures 11-13 give essentially the same debug fix from all
    three models; Table 7 still ranks ChatGPT clearly first.
  - The fix all three use is a procedural if (WIDTH == 1), not a
    generate-if. The dead branch still elaborates
    internal_data[WIDTH-2:0] as [-1:0], which most lint flows
    flag. A generate-if or a width-agnostic concatenation is the
    clean fix. One Verilator run would have shown it.

### The UVM scoreboards check almost nothing

  - Copilot (Fig. 17): the scoreboard asserts item.clk == vif.clk
    and similar, comparing monitored signals with themselves.
  - ChatGPT (Fig. 15): the scan path is left as a comment
    ("Implement check for scan shift operation"). The sequence is
    repeat(10) random at the default WIDTH. Table 9 still credits
    it with covering WIDTH==1.

### Method gaps

  - PRISMA counts: 3570 records minus 1260 duplicates leaves 2310,
    but 360 are reported screened. 1950 records are unaccounted
    for.
  - Eligibility requires peer review, yet 37% of included papers
    are arXiv preprints.
  - The date window is "2018 to present" in sec. 2.2 and
    2022-2024 in the abstract.
  - Many papers filed as "LLMs for hardware design" are hardware
    for LLMs: OliVe, ZipLM, HAT, NeuPIMs, LLMCompass, SlowLLM,
    and the recommender co-design paper [138].
  - Some summaries are generic and possibly wrong. AutoChip [110]
    is described as training on domain data; as recalled, it uses
    simulator feedback with off-the-shelf models. Check before
    citing.

-------------------------------------------------------------
## How it relates to Pacino
-------------------------------------------------------------

### 1. Where the paper's open problems meet Pacino practice

Recommendation 7.2(5) calls for real-world case studies on
large-scale projects. Several items the paper lists as open,
for single-prompt use, are things Pacino does in an agentic flow.
Per the caution above, this shows the paper's age as much as
anything about Pacino; agentic work since [2][3] also addresses
the first and third rows.

  Paper item                          Pacino practice
  ----------------------------------  ------------------------------
  EDA integration (6.3 item 8)        IA implement-simulate-fix loop
                                      on Verilator and regress.sh
  Memory and state tracking across    State kept in files, not model
  large projects (6.3 item 9)         memory: PROJECT_STATUS,
                                      handoffs, TD table,
                                      check_planning.sh checksums
  Expert feedback loops (5.2)         Architect rulings recorded in
                                      decisions documents
  Hybrid LLM + traditional            Spike and spike-dasm as
  verification (7.2(3))               external oracles

On 6.3 item 9: the paper expects better model memory. Pacino's
experience (compaction losses, sessions 078-079) is that model
memory is unreliable, and the working answer is versioned,
checksummed documents outside the model.

### 2. The paper never addresses oracle independence

The paper says LLMs can generate test cases and assertions but
never asks who checks the checker. Its own Figure 17 is the
failure in small: a model-written scoreboard checking values the
model chose passes trivially.

Pacino has hit this repeatedly and dealt with it:

  - Part 1: decoder tests all agent-written; closed with
    spike-dasm.
  - BP-040: fixes that reversed earlier fixes passed 76/76.
  - The three-layer split: the author writes expected values by
    hand from planning rule rows.
  - CLAUDE.md: assertions need an independent source.
  - TD#145: exhaustive RVC expander comparison against Spike.
  - Fetch/4 draft rule (not yet recorded): a path counts as
    covered only when removing it fails a check.

The closest the paper gets is Srikumar [151], which argues for
formal methods because LLM-written specifications are
syntactically valid but semantically wrong.

### 3. Scale

The cited benchmarks (RTLLM, VerilogEval, RTLCoder, MG-Verilog)
are single-module problems. Pacino's unit of work is a task over
a multi-module front end. Cited papers closest to Pacino's scale,
in suggested reading order:

  [174] Xiao et al. LLM-generated C and assembly tests for a
        RISC-V core and a neuromorphic core; 89-91% code
        coverage.
  [135] ROME. Hierarchical prompting that decomposes designs into
        submodules; close to the tage_table / tage_cntrl split and
        numbered tasks.
  [175] VerilogReader. LLM-directed tests aimed at uncovered
        branches; relevant to the TD#188 counters.
  [173] Qayyum et al. Incremental module-by-module proofs with an
        SMT solver.

### 4. Open-issues tables (Tables 11 and 12)

  Applies now:   DSE (cachegen), FSM design, UVM and SVA
                 verification, hardware security (PMP/PMA, CSR).
  Applies later: timing, floorplanning, CTS, post-silicon.
  Contrast:      7.2(1) domain-specific LLMs. Pacino's results
                 come from process discipline around a general
                 model, not from fine-tuning.

-------------------------------------------------------------
## Two agentic papers
-------------------------------------------------------------

Both are agentic (tools in the loop, several agent roles,
iterative repair), so newer in method than [1]. Neither is
newer than Pacino's practice, and neither works above the scale
of a single small block. Together they bracket the question of
where the oracle comes from.

### VerilogCoder [2]

Method: multi-agent on AutoGen, ReAct tool calls.
  - A planner breaks a module description into sub-tasks, each
    linked to its signals, state transitions and examples through
    a graph (TCRG).
  - A code agent and a verification-assistant agent write each
    piece and check it with iverilog.
  - A debug agent simulates; on a mismatch, an AST-based tool
    traces back from the failing output and shows the waveforms
    of the signals that drive it.
  - 94.2% on the 156 VerilogEval-Human v2 problems (GPT-4 Turbo).

Relevance to Pacino:
  - Supports detailed planning. Ablation: planner +7.7 points,
    tracing tool +11.5, both +27.5. The planner helps most on
    Karnaugh-map and transition-table problems (+33, +44), because
    it carries every table row into the sub-task. This is the
    role Pacino's rule rows and truth tables play.
  - Its loop is the IA's loop: implement, simulate, trace, fix.
    The AST waveform tracer is the one idea worth borrowing, as an
    IA debug aid.
  - The oracle is given, not solved. The debug agent repairs until
    "a provided testbench" passes, and results are scored with
    "the provided golden testbench"; these read as the same
    testbench. 94.2% measures convergence on a visible testbench;
    the baselines never saw one. Baselines are best pass@1 across
    settings; VerilogCoder runs once and uses about 13x the tokens.
  - Agent memory is the original query plus the last four
    messages: the opposite of Pacino's state in files.

### Gadde et al. [3]

Cites [1] as its reference [2], so it is the direct successor.

Method: multi-agent on AutoGen, GPT-4o.
  - Planning: from one specification, a design lead agent writes
    a microarchitecture and a verification lead agent writes a
    vPlan.
  - Development: RTL agents and SVA agents in parallel; critic
    agents review.
  - Execution: an executor agent runs SpyGlass and JasperGold;
    counterexamples go back to the agents.
  - Escalation to a human after five failed iterations.
  - Five small designs: CRC, ECC, FIFO, Lemming, Timer.

Relevance to Pacino:
  - Nearest published structure. Lead agents ~ PA; task
    dispatcher ~ task files; development agents ~ IA; HITL ~
    architect. Differences: in Pacino the architect sets the
    architecture, not an agent; the IA escalates when it cannot
    cite a rule row, not when an iteration count runs out.
  - Clearest example of the independence problem. The paper
    claims deriving RTL and properties from one specification
    "eliminates" divergence between intent and verification; it
    does not test this. Both come from one model reading one
    specification, so a proof shows only that the two agree, and
    a counterexample can be "fixed" on either side.
  - Humans supplied the correctness. Lemming and Timer had
    functional bugs at every temperature; humans fixed them.
    Humans cut property counts (CRC 16 to 11, ECC 19 to 12, FIFO
    20 to 13) before the 100% assertion pass rate. How "logical
    accuracy" was judged is not stated.
  - Details that do not hold up: the text cites an ECC run at
    temperature 0.3, but Table I has only 0.2, 0.5 and 0.8; GPT-4o
    is called "a 1.8 trillion parameter LLM", a figure OpenAI has
    not, to our knowledge, published.

### Not covered by either

  - State across sessions.
  - Designs larger than a single small block.
  - Expected values written by someone other than the agent.

These remain what is distinctive about Pacino.

-------------------------------------------------------------
## Proposals
-------------------------------------------------------------

P1  Blog: cite [1] in a methodology post as the field's view as
    of 2024. Framing only; under the blog rule, external work is
    cited where the project took something from it, and Pacino
    took no design from this paper.

P2  Blog: the shift-register comparison is a concrete, fair
    illustration of evaluation by inspection versus evaluation
    against an oracle the implementer did not write.

P3  Read [174], [135], [175], [173] in that order.

P4  If a current picture is wanted, survey 2025-2026 agentic
    hardware design work separately; [1] does not cover it, and
    [2][3] are two data points, not a survey.

P5  Consider an AST-based waveform back-tracer, as in [2], as an
    IA debug aid.

P6  Blog: [3] is the nearest published structure to Pacino's and
    a concrete case of same-model design and verification; it
    could anchor the oracle-independence argument in a
    methodology post. Framing only, as in P1.

-------------------------------------------------------------
## References
-------------------------------------------------------------

[1] M. Abdollahi, S. F. Yeganli, M. Baharloo and A. Baniasadi,
    "Hardware Design and Verification with Large Language Models:
    A Scoping Review, Challenges, and Open Issues," Electronics,
    vol. 14, no. 1, art. 120, 2025.
    doi:10.3390/electronics14010120

[2] C.-T. Ho, H. Ren and B. Khailany, "VerilogCoder: Autonomous
    Verilog Coding Agents with Graph-based Planning and Abstract
    Syntax Tree (AST)-based Waveform Tracing Tool," in Proc.
    39th AAAI Conference on Artificial Intelligence (AAAI-25),
    2025, pp. 300-307. Code: github.com/NVlabs/VerilogCoder

[3] D. N. Gadde, K. Kopparam Radhakrishna, V. Naduvodi
    Viswambharan, A. Kumar, D. Lettnin, W. Kunz and S. Simon,
    "Hey AI, Generate Me a Hardware Code! Agentic AI-based
    Hardware Design & Verification," to appear in Proc. 38th
    SBC/SBMicro/IEEE Symposium on Integrated Circuits and Systems
    Design (SBCCI), 2025. arXiv:2507.02660
