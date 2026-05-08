# BLOG_introduction.md

```
 FILE:    BLOG_introduction.md
 STATUS:  unpublished
 UPDATED: 2026-xx-xx
 CONTACT: uarchlabs@gmail.com
```
# Project Rationale

The emergence of LLMs raises a practical question for high performance
large-scale processor development: can a standards-compliant, competitively
performant design be built by a very small team on a small budget? If yes, the
implications to corporate development in team size, schedule, and cost are
significant.  This project is designed to explore these questions. 

To investigate this I am building Pacino — an RVA23S64 8-issue OOO RISC-V
processor targeting competitive SPECint2006 performance. The target is
deliberately ambitious. A simple pipeline would not stress the methodology; a
design at this complexity will expose where AI assistance genuinely helps and
where it breaks down.

Efficiently evaluating AI-generated RTL requires domain expertise — to direct
the work and to judge the output. Microarchitecture depth, verification
strategy, and performance correlation methodology are each useful prerequisites
for an honest assessment at lower token consumption rates, providing a
method that is efficient in outcome and cost. 

For other scope related discussions there is an [FAQ](https://uarchlabs.com/faq.html).

### Goals

Defining "practicality" requires a specific focus on methodology. This work is
driven by a central investigative question:

> **What prompting structures and methodology processes yield the best results when using LLMs for the co-design of a high-performance RISC-V processor?**

In addition to the primary goal, I am evaluating other qualitative and quantitative characteristics:

* **Context Management**: Developing repeatable mechanisms for managing context in the Planning Assistant (PA) and Implementation Assistant (IA).
* **Task Scaling**: Establishing an intuition for the size of a design task relative to the context required.
* **Human-in-the-Loop Requirements**: Determining the level of human interaction and domain expertise necessary to achieve functional results.
* **Future Impact**: Assessing how this methodology might reshape the workflow and composition of future microprocessor design teams.

## Methodology

I structured the approach around four complementary elements: a dual AI
assistant architecture that separates strategic planning from implementation, a
context isolation strategy that keeps individual experiments clean, a
structured prompt template that enables automated results reporting and
analysis, and a structured handoff process that preserves continuity across
planning sessions.

### Dual AI Assistant Architecture

The methodology utilizes two distinct Claude interfaces:
* **Claude.ai (Web)**: Serves as the **Planning Assistant (PA)**.
* **Claude Code (Terminal)**: Serves as the **Implementation Assistant (IA)**.

The roles were assigned based on the native capabilities of each interface.
This approach addresses the fundamental challenge of maintaining both strategic
architectural thinking and detailed implementation capability within the
constraints of AI context windows.

#### Claude.ai (Web Interface) — Planning Assistant (PA)

The PA serves as the strategic actor. Its primary functions include high-level
architectural guidance, experimental methodology design, structured prompt
generation for implementation work, results evaluation, and session-to-session
knowledge transfer via handoff documents.

In this role, the PA is responsible for:
* Design space exploration and trade-off analysis.
* Interface specification and module boundary decisions.
* Experimental planning and hypothesis formation.
* Cross-session state management via structured documentation.
* Quality assessment of implementation results contrasted with User developed assessment.

For context management, the PA maintains conversational history for
architectural reasoning, accesses past session data through search tools when
needed, preserves design rationale and decision context, and tracks
experimental methodology evolution.

User interaction is central to this phase. The user makes the final decision on
order and scope of implementation tasks, decisions required for compliance to
standards and interactive generation of specifications and design rules.  The
PA has no access to the IA file system or source control repositories.

#### Claude Code (Terminal Interface) — Implementation Assistant (IA)

The IA serves as the execution actor. Its primary functions include direct
SystemVerilog RTL generation and modification, file system access for reading
and writing project files, compilation, linting, and testing through Verilator
integration, and testbench creation and verification.

In this role, the IA is responsible for:
* Production-quality RTL code generation.
* Adherence to coding style and structural requirements.
* Integration with existing build and verification flows.
* Technical constraint satisfaction (timing, area, and functionality).

For context management, the IA reads project guidelines from CLAUDE.md
automatically but maintains no persistent state between sessions.  The IA
operates with a "clean context" for each task. It is the responsibility of the
PA session to declare the **Minimal Viable Context** required explicitly 
through the prompt for any given implementation task.

The IA currently has read/write privileges to the file system but has no
knowledge of the source control system (GIT) or knowledge of the repo.

### Workflow Integration Pattern

1. **Strategic Planning Phase (PA/User)** — I analyze requirements and
	 constraints with the PA, review previous session results and lessons
learned, define the experimental hypothesis and success criteria, and generate
a structured implementation prompt with complete context specification. This is
also the phase where specifications are developed as context. Domain knowledge
informs the scope and order of tasks throughout.

2. **Transfer Phase (User-mediated)** — I chose to keep this as a manual step
	 due to permissions and security considerations. The PA has no access to the
file system. I make the PA-generated task file available to the IA environment,
ensure all referenced files and contexts are accessible, update the repo with
the latest accepted edits, and initiate the implementation session.

3. **Implementation Phase (IA)** — The IA executes RTL implementation per the
	 structured prompt, performs compilation, linting, and basic verification,
generates a results summary identifying any issues, and produces deliverables
ready for integration. The IA populates a structured results section in the
task file and reports a summary to the console.

4. **Evaluation Phase (PA/User)** — I review implementation results against
the IA run — time, context used, model, completion status — and write an
assessment of the results. I provide my analysis and the IA results to the PA
for further analysis.  Status and technical debt are recorded and I plan the
next experimental phase or iteration.

5. **Knowledge Preservation Phase (User-mediated)** — I judge the PA's
	 remaining context and effectiveness. If warranted I initiate a session
handoff — refreshing context with the previous handoff document and requesting
that the PA produce the handoff document for the next session, recording
architectural decisions, rationale, and updates to project status and planning
documents.

## Workflow Summary

![PA/IA Workflow](diagrams/pa_ia_workflow.svg)

1. With PA discuss the next tasks or experiments, agree on scope, provide any implementation specifications, interfaces, etc.

2. I provide the PA the task template, the PA populates the IA session prompt
    - these tasks files use a numbering scheme DECODE-001.md, etc

3. I transfer the populated task file to the IA file system at ./prompts

4. A fresh Claude Code session is started
    - `claude`
    - There are additional options to control claude automation 
      --auto-accept-edits or --dangerously-skip-permissions
    - This is a user choice. It is independent of the methodology

5. I specify the /run command
    - `/run <task id> `
    - The run command locates the task file, verifies it's format, extracts
      the prompt and executes the instructions.

6. The IA will run and report summary results to the console and write to the
	 ::RESULTS CAPTURE:: section of the task file.

7. I populate the header data fields with run statistics, and optionally 
   edit the User Assessment section and paste the IA console output into the task file.
	 - This step supports the experimental record — it is part of the methodology
	   documentation, not the design flow itself.

8. I share the completed task file with PA, discuss results, record
		decisions, plan next task
		- This is interactive and can generate a number of actions, technical debt,
		  additional or clarified documents, or occasionally require updates to
      CLAUDE.md

9. Once ready I commit the git repo changes
    - The IA does not have knowledge of the repo. This is a deliberate design choice. 
    - I also mirror the repo on a separate file system distinct from the file system the IA has access to.

Since PA also has context limits at some point it will be necessary to perform
a session handoff. This is usually indicated by incomplete or inaccurate
answers by the PA, forgetting instructions from earlier in the session, etc.

In this case, I supply PA with the SESSION_HANDOFF.md template, a copy of the
previous session handoff file, and ask that PA generate the next session
handoff document. Supply the current session number and the next. PA will
produce session_handoff-NNN.md with

- Key architectural decisions and their reasoning
- Technical debt inventory
- Tools status and known issues
- Next steps in priority order
- Anything not captured elsewhere in the repo

When starting the next session supply STATUS.md, and the latest
session_handoff-00N.md file. If flows or changes to CLAUDE.md were made in the
last session supply CORE.md and/or CLAUDE.md as well.

## Methodology Mechanics

### MD support files
MD files form the conventional basis for interacting with IA and PA.

| File / Directory | Description |
| :--- | :--- |
| `./CLAUDE.md` | Canonical baseline context, constant across IA sessions. Covers purpose, text output rules, fixed constraints (e.g. read fully before write), and how the IA should respond to conflicting or poorly defined requirements. |
| `./pa_handoffs/` | Previous PA session handoff files. |
| `./planning/PROJECT_CORE.md` | High level description of project intent, scope, roles, workflow, conventions, and 3rd party tool status. Supplied to PA only when project-level changes occur — new steps, new tools, methodology changes. |
| `./planning/PROJECT_STATUS.md` | Current project state: module status, technical debt, development and design open items, SV package conventions, key cluster/module parameters, prompt generation guide, architecture decisions, and prompt decomposition list. Used in handoff and planning sessions. |
| `./planning/arch/` | Contains documentation of architecture decisions and guidance. These documents are tactically supplied as reference context in IA prompts. |
| `./planning/interfaces/` | Contains definition of module ports necessary for sharing between modules and subsystems. This is the primary mechanism to ensure minimal issues with interoperability. These documents are tactically supplied as reference context in IA prompts. |
| `./planning/testbenches/` | Contains context for test bench guidance. |
| `./planning/tools` | 3rd party tool capabilities, usage, etc, these are not claude tools or skills. |
| `./prompts/` | IA task files generated by PA using the task template, labeled by module and iteration e.g. `DECODE-002.md`. |
| `./templates/TASK_TEMPLATE.md` | Structured document populated by PA with goals and IA prompt. Contains task header (ID, context stats, runtime, model, resume SHA, status), a user assessment section, the extracted IA prompt, and a results capture section the IA populates. Once populated, labeled `<Module>-<ID>.md` and stored in `./prompts/`. |
| `./templates/SESSION_HANDOFF.md` | Structured document populated by PA at session handoff. Records session progress, decisions carried forward, prompts generated, and PROJECT_STATUS.md updates. PROJECT_CORE.md and PROJECT_STATUS.md updates are applied manually. |


# Evaluation Criteria

The primary evaluation metric is projected SPEC CPU2006 and CPU2017 IPC, derived from a validated C++ performance model executing SimPoints. Model validation is established by correlating against the RTL using a common microarchitectural event schema anchored to the RISC-V Hardware Performance Monitor specification, with RISC-V micro-benchmarks, Dhrystone, and CoreMark as the correlation workloads. Linux boot on an FPGA platform is anticipated as a further correctness validation and provides a natural environment for HPM counter verification. PPA characterization and silicon measurement remain open for future work.

# Summary

The dual assistant architecture is a practical solution to a real problem:
maintaining architectural coherence across a long, complex design while keeping
individual implementation sessions clean and reproducible. The PA handles
design reasoning and continuity. The IA handles execution. The user owns every
decision.  Whether this approach can produce a competitive 8-issue OOO
processor is the question this project is designed to answer. The methodology,
the prompts, the failures, and the results will all be published. That
transparency is part of the point.

---
---
*Jeff Nye is a microprocessor architect with 35 years of industry experience 
spanning performance modeling, RTL implementation, and architecture for 
high-performance OOO processors. He has contributed RTL to Pentium 4, ARM V7,  TI C6x and RISC-V designs, and recently served as sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE branch prediction cluster in an 8-issue RVA23 RISC-V processor — from research through timing closure at 2.75 GHz. He holds +20 issued patents in processor design, architecture, and hardware 
virtualization. He is the author of Pacino and the uarchlabs methodology documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926/).*

