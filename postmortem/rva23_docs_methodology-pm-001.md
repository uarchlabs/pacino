<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->
# Project Rationale

The primary objective of this project is to determine if it is practical to use AI to fully develop a world-class, out-of-order superscalar microprocessor.

To investigate this, I chose to target the implementation of an **RVA23-compliant RISC-V machine** in an 8-issue, out-of-order configuration. I expect this target to be sufficiently complex to serve as a legitimate benchmark for AI capability and I have domain knowledge acquired in +30 years of microprocessor development. This domain knowledge should assist in evaluation of the effectiveness of automated design relative to direct human design, as well as provide the background necessary to form reasoned opinions on the quality and completeness of the AI-generated output.

### Goals
Defining "practicality" requires a specific focus on methodology. This work is driven by a central investigative question:

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

User interaction is central to this phase. The user makes
final decision on order and scope of implementation tasks, decisions required
for compliance to standards and interactive generation of specifications and
design rules. Note: The PA currently has no access
to the IA file system or source control repositories.

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
automatically but maintains no persistent state between sessions.
documents directly, maintains no persistent state between sessions. It operates
with a "clean context" for each task. It is the responsibility of the
PA session to declare the **Minimal Viable Context** required for any given 
implementation task.

The IA currently has read/write privileges to the file system but has no knowledge of the source control system (GIT) or knowledge of the repo.

### Workflow Integration Pattern

1. **Strategic Planning Phase (PA/User)** — We analyze requirements and constraints, review previous session results and lessons learned, define the experimental hypothesis and success criteria, and generate a structured implementation prompt with complete context specification. This is also the phase were context in the form of specifications are developed. There is significant human interaction in this phase as domain knowledge informs the scope and order of tasks.

2. **Transfer Phase (User-mediated)** — This is a manual step due to considerations for permissions and security. The convention is that PA does not have access to the file system. I copy the structured prompt from the PA to the IA environment, ensure all referenced files and contexts are accessible, update the repo with the latest accepted edits and initiate the implementation session with clear deliverables.

3. **Implementation Phase (IA)** — The IA executes RTL implementation per the structured prompt, performs compilation, linting, and basic verification, generates a results summary identifying any issues, and produces clean deliverables ready for integration. There is a structure Results section in the prompt which IA populates as well as reporting a summary to the console.

4. **Evaluation Phase (PA/User)** — We review implementation results against success criteria, capture lessons learned and methodology refinements. I record the statistics from the IA run in the results prompt (time, context used, model, completion/etc.) I provide the IA/user completed results to PA for assessment. Status and technical debt are manually recorded. We then plan the next experimental phase or iteration, and generate the prompt for the next IA task. 

5. **Knowledge Preservation Phase** — I make a judgement of PA's remaining context and effectiveness. If warranted I initiate a session handoff. This is refreshing the context with the previous handoff document and request that PA produce the handoff document for the next session. The produced document records the architectural decisions/rationale, records updates  to project status and planning documents.

## Workflow Summary

1. With PA discuss the next tasks or experiments, agree on scope, provide any implementation specifications, interfaces, etc.
2. Provide PA the task template, PA populates the IA session prompt
    - these tasks files use a numbering scheme DECODE-001.md, etc
3. User transfers the populated task file to the IA file system at ./prompts
4. User executes the task file validation script. 
    - This script verifies for the format and extracts the IA prompt to ./claude/tmp/current-prompt.md
5. A fresh Claude Code session is started
    - claude --dangerously-skip-permissions
    - The skip option can be downgraded to --auto-accept-edits or eliminated completely
    - This is independent of the methodology
6. Command IA to execute the prompt
    - `read .claude/tmp/current-prompt.md and execute it`
7. IA will run and report summary results to the console and write to the ::RESULTS CAPTURE:: section of the task file.
8. Optionally the User will paste the console output to the task file.
9. User will populate the header data fields, and optionally edit the User Assessment section
10. Share the completed task file with PA, discuss results, record decisions, plan next task
    - This is interactive and can generate a number of actions, technical debt, additional or clarified documents, or occasionally require updates to CLAUDE.md
11. Once ready commit the git repo changes

Since PA also has context limits at some point it will be necessary to perform a session handoff. This is usually indicated by incomplete or inaccurate answers by the PA, forgetting instructions from earlier in the session, etc.

In this case, supply PA with the SESSION_HANDOFF.md template, a copy of the previous session handoff file, and ask that PA generate the next session handoff document. Supply the current session number and the next. PA will produce session_handoff-00N.md with

- Key architectural decisions and their reasoning
- Technical debt inventory
- Tools status and known issues
- Next steps in priority order
- Anything not captured elsewhere in the repo

When starting the next session supply STATUS.md, and the latest session_handoff-00N.md file. If flows or changes to CLAUDE.md were made in the last session supply CORE.md and/or CLAUDE.md as well.

## Methodology Mechanics

### MD support files
MD files form the conventional basis for interacting with IA and PA.

| File / Directory | Description |
| :--- | :--- |
| ./CLAUDE.md | This contains instructions that remain constant across IA sessions. Common sections are purpose, text output rules (ASCII only, # cols, etc). Fixed constraints (such as read fully before write, etc), how to respond when prompts have conflicting or poorly defined requirements, etc. |
| ./planning/CORE.md   | High level description of the project, intent, scope, roles, workflow, conventions and 3rd party tools status. This is only supplied to new sessions when project level changes occur, e.g. new steps, new tools, etc. |
| ./planning/STATUS.md | Describes the current state of the project, used as part of handoff process |
| ./planning/arch | Documentation of architecture decisions and guidance. |
| ./planning/interfaces | Definition of module ports necessary for sharing between modules and subsystems. This is the primary mechanism to ensure minimal issues with interoperability. These documents are tactically supplied as context in IA prompts. |
| ./planning/testbenches | Test bench guidance |
| ./planning/tools | 3rd party tool capabilities, usage, etc, these are not claude tools or skills. |
| ./prompts | Prompts are labeled and number by module and iteration, DECODE-002.md These are generated by PA using the prompt task template |
| ./sessions                   | Contains session handoff and status files |
| ./templates/TASK_TEMPLATE.md | This is a structured document that is populated by PA for the initial task and updated by IA with results. The user also updates this with the claude.code run statistics and status of the task. |
| ./templates/SESSION-HANDOFF.md | This is a structured document that is populated by PA as a record of the current planning session. This includes results and decisions to be carried forward into the next PA session |

### MD Structures

#### CLAUDE.md
This file has a conventional usage. It provides context that is constant across tasks.

The current version is at the top of the repo.

#### CORE.md
CORE.md is the primary methodology context for PA. It discusses roles, processes, available tools, file structure. This is slow changing project wide context. When changes occur this is supplied as additional session handoff context.

The current version is at ./planning/CORE.md

#### STATUS.md
This is the up to date project status, this includes module status, a list of technical debt, development/flow open items, design open items, SV package conventions, key cluster/module parameters, a prompt generation guide section, architecture decisions, itemized module/cluster prompt decomposition list.

The current version is at ./planning/STATUS.md

#### TASK_TEMPLATE.md
A task template is provided to Claude.ai, which populates the goals and provides the Claude Code prompt. There are text markers identifying sections that Claude Code or Claude.ai populate. The task header includes a table for task id, context usage stats, run time, model uses, resume SHA, task type and current status. There is a results analysis section populate by the user. There is a structured section which is the prompt for Claude Code. This section is extracted for Claude Code with a script. And there is a results capture section which Claude Code is instructed to populate. 

The current template for this file is ./templates/TASK_TEMPLATE.md. 

Once this file is populated it is labeled \<Module\>-\<ID\>.md and stored in ./prompts

#### SESSION_HANDOFF.md

The session handoff template along with the previous sessions handoff document are provided to Claude.ai when a session handoff is intended. The template includes book keeping boiler plate that includes the new session number and the generating session number, date, etc. There is structure to facilitate Claude.ai's summarization of current session progress and goals for the next session. Claude.ai also documents prompts generated this session and status, and changes to reflect in project status (STATUS.md) as a result of the current session.

The CORE.md and STATUS.md updates are manual at this stage of the project.

# Evaluation Criteria
The primary evaluation metric is projected SPEC CPU2006 and CPU2017 IPC, derived from a validated C++ performance model executing SimPoints. Model validation is established by correlating against the RTL using a common microarchitectural event schema anchored to the RISC-V Hardware Performance Monitor specification, with RISC-V micro-benchmarks, Dhrystone, and CoreMark as the correlation workloads. Linux boot on an FPGA platform is anticipated as a further correctness validation and provides a natural environment for HPM counter verification. PPA characterization and silicon measurement remain open for future work.

# Summary
The dual assistant approach provides several structural advantages. The separation of concerns isolates strategic thinking from implementation details and lets each phase focus on its optimal mode of work. Context optimization means the PA maintains rich conversational context for design reasoning while the IA operates with minimal, focused context for each implementation task, preventing context pollution between different types of thinking. Tool leverage capitalizes on the fact that the PA excels at complex reasoning, planning, and evaluation, while the IA provides direct file system access and tool integration. Experimental rigor is enhanced because hypothesis formation happens separately from implementation bias, result evaluation proceeds independently of implementation effort, and knowledge capture and transfer are systematic. Finally, the pattern scales to complex multi-module designs, maintains design coherence across extended development periods, and supports iterative refinement of both methodology and implementation.
