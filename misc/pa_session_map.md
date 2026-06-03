
RVA23 Co-Design Part N
```
|Part|Description                | Documents
|----|---------------------------|-------------------------------------------|
| 0  | Investigative, no prompts | none                                      |
| 1  | development of PA/IA      | prompt template,dir structure             |
|    |                           | project setup and status files            |
|                                | DECODE-001/002/003/004/005/006            |
|                                | DECODE-007/008/009/010/011                |
|                                | TOOLS-001/002                             |
|                                | rtl defines/packages                      |
|                                | main README.md                            |
|                                | session_handoff-001.md                    |
| 2  | Spike as oracle           | TOOL2.md, trouble with ISA string         |
|    |                   |  |
| 3  | BP cluster architecture   | bp_cluster.md                             |
|    | A planning session for BPU| xiangshan_ras_design.md                   |
|    | BP element parameters     | BP-001 executed                           |
|    |                           | CLAUDE.md updated                         |
|    |                           | session_handoff-003                       |
|    |                           | PROJECT_STATE.md emitted                  |
|    |                           | STATUS.md        emitted                  |
|    |                           | BP-002 emitted not run                    |
|    |                           | session_handoff-004                       |
|    | ? two handoffs in 1 session  | seems sh-003 not used                  |
|    |                   |  |
| 4  | bp_history        | BP-002 run                                |
|    |                   | session_handoff-005                       |
|    |                   |  |
| 5  | uBTB              | BP-003 run                                |
|    |                   | BP-003-fix run                            |
|    |                   | ubtb_interfaces.md                        |
|    |                   | bp_history_interfaces.md                  |
|    |                   | session_handoff-006                       |
|    |                   |  |
| 6  | loop_pred         | BP-004 run                                |
|    |                   | loop_pred_interfaces.md                   |
|    |                   | hit  response output token limits         |
|    |                   | hit  usage limits, c.code off the rails   |
|    |                   | BP-004 split into a and b                 |
|    |                   | BP-004a run                               |
|    |                   | BP-004b emitted not run                   |
|    |                   | CLAUDE.md exact prompt name added to rules|
|    |                   | REPORT_TEMPLATE same thing                |
|    |                   | session_handoff-007                       |
|    |                   |  |
| 7  | loop_pred         | BP-004b failed to run context limit       |
|    |                   | Decision to split into c/d/e              |
|    |                   | BP-004c: loop_pred.sv RTL only
|    |                   | BP-004d: tb_loop_pred.sv TC1-TC7          |
|    |                   |              + Makefile sim_loop target   |
|    |                   | BP-004e: tb_loop_pred.sv TC8-TC13 appended|
|    |                   | PROJECT_CORE.md created                   |
|    |                   | PROJECT_STATUS.md repartitioned           |
|    |                   | PROJECT_STATE.md repartitioned            |
|    |                   | package and defines restructure           |
|    |                   | session_handoff-008                       |
|    |                   |  |
| 8  | loop_pred         | BP-004c run                               |
|    |                   | BP-004d run ?                             |
|    |                   | Issues with context in PA                 |
|    |                   | session_handoff-009                       |
|    |                   |  |
| 9  | loop_pred         | BP-004e run                               |
|    |                   | BP-004f emitted                           |
|    |                   | attempted slash command run-prompt        |
|    |                   |   slash command eventually abandoned      |
|    |                   | validate_and_extract.py written to pull   |
|    |                   |   prompt from task file                   |
|    |                   | session_handoff-010                       |
|    |                   |  |
| 10 | loop_pred         | BP-004f run attempted finally run         |
|    |                   |  The response generation timed out after  |
|    |                   |  reading all context files                |
|    |                   | split 004f into 004f-1 thru N             |
|    |                   | Very frustrating session with PA due to   |
|    |                   |   hidden limits, timeouts and other PA    |
|    |                   |   fading out not following/understanding  |
|    |                   |   requests.                               |
|    |                   | This session probably needs it's own blog |
|    |                   | session_handoff-011                       |
| 11 | tage              | BP-005  |
|    |                   | input bp_cluster.md |
|    |                   | created tage_interfaces.md |
|    |                   | updated bp_defines_pkg.sv |
|    |                   | updated bp_structs_pkg.sv |
|    |                   | a port naming convention was implemented |
|    |                   | output session_handoff-012 |
|    |                   |  |
| 12 | tage components   | this session implemented components      |
|    |                   | needed by tage |
|    |                   |  |
|    |                   | COMP-001 |
|    |                   |  |
|    |                   | mods to prompt task file markers |
|    |                   | mods to validate_and_extract.ps |
|    |                   | output session_handoff-012 |
|    |                   |  |
|    |                   |  |
| 13 | tage components   | COMP-002 |
|    |                   | COMP-003 |
|    |                   | output session_handoff-013 |
|    |                   | i think the numbering for the session  |
|    |                   | handoffs may have been incorrect |
|    |                   | pa session says -014 I think it's -013 |
|    |                   | pa session handoff -013 exists unclear |
|    |                   | where the off by one error was introduced |
|    |                   |  |
| 14 | tage              | BP-006 tage_hash    completed |
|    |                   | BP-007 tage_table  adandoned draft |
|    |                   | BP-008 tage        adandoned draft |
|    |                   | BP-009             adandoned draft |
|    |                   | hashing functions |
|    |                   | session_handoff-015 |
|    |                   |  |
| 15 | tage              | BP-007a unknown |
|    |                   | BP-007b emitted |
|    |                   | session_handoff-016 |
|    |                   | un clear what was accomplished |
|    |                   |  |
| 16 | tage              | largely clean up session ? |
|    |                   | tech debt table udpated |
|    |                   | merged PROJECT_STATE into PROJECT_STATUS |
|    |                   | PROJECT_STATUS |
|    |                   | session_handoff-017 |
|    |                   |  |
| 17 | tage              | |
|    |                   | tage_cntrl_decisions.md |
|    |                   | tage_cntrl_ctr_update_rules.md |
|    |                   | tage_cntrl_useful_update_rules |
|    |                   | tage_cntrl_alloc_rules.md  |
|    |                   | session_handoff-018 |
|    |                   |  |
| 18 | tage              | |
|    |                   | BP-008a.md hit limit split into a1/a2 |
|    |                   | BP-008a-1.md tage shell ran |
|    |                   | BP-008a-2.md prediction logic ran |
|    |                   | BP-008b.md update logic emitted  |
|    |                   | BP-008c.md wire tage_cntrl emitted  |
|    |                   | slot nomenclature change using arrays [] |
|    |                   | session_handoff-019 |
|    |                   |  |
| 19 | tage              | BP-007d ran |
|    |                   | BP-007e ran  |
|    |                   | BP-007f ran |
|    |                   | BP-008b emitted |
|    |                   | BP-007c number skipped i think? |
|    |                   | session_handoff-019 |
|    |                   |  |
| 20 | tage              | BP-008b ran |
|    |                   | validate_and_extract.py modified   |
|    |                   | BP-009 ran |
|    |                   | BP-009a ran |
|    |                   | BP-009a-1 emitted |
|    |                   | session_handoff-021 note numbering change |
|    |                   |  |
| 21 | tage              | BP-09a-1 ran |
|    |                   | BP-09b ran |
|    |                   | BP-010 ran testbench |
|    |                   | BP-010a ran |
|    |                   | BP-010b ran |
|    |                   | BP-010c emitted |
|    |                   | fast init issues |
|    |                   | tage_tb_decisions.md |
|    |                   | session_handoff-022 |
|    |                   |  |
| 22 | tage              | BP-010c ran |
|    |                   | tage_cntrl_use_update_rules.md |
|    |                   | BP-010d ran  |
|    |                   | BP-010e ran  |
|    |                   | BP-010f emitted |
|    |                   | session_handoff-023 |
|    |                   |  |
| 23 | tage              | BP-010f ran |
|    |                   | BP-011  ran  testbench |
|    |                   | BP-012  ran  |
|    |                   | BP-013  ran |
|    |                   | BP-014a emitted testbench |
|    |                   | session_handoff-024 |
|    |                   |  |
| 24 | tage              | BP-014a ran  |
|    |                   | BP-014b ran   |
|    |                   | BP-014c ran  |
|    |                   | BP-014d ran |
|    |                   | BP-014e ran |
|    |                   | BP-014f ran  |
|    |                   | BP-014g ran |
|    |                   | BP-014h ran |
|    |                   | session_handoff-025 |
|    |                   |  |
| 25 | tage              | BP-015  ran |
|    |                   | BP-016  ran |
|    |                   | BP-017a ran |
|    |                   | BP-017b ran |
|    |                   | BP-018  ran |
|    |                   | BP-019  ran |
|    |                   | BP-019a ran |
|    |                   | BP-019b emitted ?? |
|    |                   | session_handoff-026 |
|    |                   |  |
| 26 | tage              | |
|    |                   | confusion user in chat says : "019b was a  |
|    |                   | context mistake, it does not exist" |
|    |                   | BP-020  ran |
|    |                   | BP-021  ran |
|    |                   | session_handoff-027 |
|    |                   |  |
| 27 | tage              | BP-022  ran |
|    |                   | BP-022a ran |
|    |                   | BP-022b ran |
|    |                   | session_handoff-028 |
|    |                   |  |
| 28 | tage              | BP-022c ran |
|    |                   | BP-023a ran |
|    |                   | BP-023b ran |
|    |                   | session_handoff-029 |
|    |                   |  |
| 29 | clean up          | INFRA-001-006 complete |
|    | coverage          | BP-023c complete 54 tests |
|    | tage              | BP-024 allocation root cause |
|    |                   | BP-025 written not executed |
|    |                   | tage_coverage_plan.md written |
|    |                   | new /run command, simple |
|    |                   | new directory tree |
| 30 | ???               | BP-026 BP-027 BP-028(emitted)|
|    |                   |  |
| 31 | ???               | BP-028(run)     |
|    |                   | BP-029(emitted) |
|    |                   | BP-030(emitted) |
|    |                   |  |
| 32 | ???               | BP-029(run)     |
|    |                   | BP-030(run)     |
|    |                   | session_handoff-033 |
| 33 | ???               | planning only  |
|    |                   | session_handoff-034 |
| 34 | ???               | planning only  |
|    |                   | session_handoff-035 |
| 35 | ???               | planning only  |
|    |                   | session_handoff-036 |
| 36 | ???               | planning only  |
|    |                   | session_handoff-037 |
| 37 | ???               | BP-031         |
|    |                   | BP-032         |
|    |                   | session_handoff-038 |
| 38 | ???               | planning       |
|    |                   | session_handoff-039 |
| 39 | ???               | BP-033         |
|    |                   | BP-033-fix-1        |
|    |                   | session_handoff-040 |
| 40 | ???               | BP-034 |
|    |                   | BP-034a  ???|
|    |                   | BP-035 |
|    |                   | BP-036 |
|    |                   | session_handoff-041 |
| 41 | ???               | BP-037  |
|    |                   | BP-037a |
|    |                   | BP-037b |
|    |                   | BP-038  |
|    |                   | BP-038a |
|    |                   | session_handoff-042 |
| 42 | ittage            | input session_handoff-042   |
|    |                   | TD #47 completed            |
|    |                   | RB removal from ittage      |
|    |                   | BP-038b                     |
|    |                   | BP-039                      |
|    |                   | added TD 50/51              |
|    |                   | reopen TD 46                |
|    |                   | session_handoff-043 |
|    |                   |                             |
| 43 | sram init cleanup | input session_handoff-043   |
|    | ittage clean up   | TB-001/2                    |
|    | manual testbenches| BP-040                      |
|    |                   | BP-041 partially written    |
|    |                   | manual_tb_decisions.md      |
|    |                   | sram_fast_init.md           |
|    |                   | session_handoff-044 |
| 44 | ???               | BP-041 manually generated and run |
|    |                   | HAND-FIX-003 (mislabled as 001)
|    |                   | asserts and 1st ADR |
|    |                   | session_handoff-045 |
| 45 | ???               | web/session management |
|    |                   | IN PROJGRESS        |

