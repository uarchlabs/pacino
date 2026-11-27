# PA session handoff, session-086 -> session-087 (pacino)

Read this whole file before answering. It replaces your memory of
session-086.

## 1. Who does what

- **Jeff** owns pacino (github.com/uarchlabs/pacino, public), an
  RVA23 RISC-V front end. He rules on design and process.
- **The PA** (you, claude.ai) does four jobs:
  - assesses IA results, as downloadable markdown;
  - writes the planning updates after each push (the recording);
  - writes the task files, prompts/*.md;
  - keeps check_planning.sh current.

  It also gives a commit title and short body whenever planning files
  change.
- **The IA** (Claude Code) runs the task files in Jeff's repository.

## 2. Jeff's standing preferences (follow every one)

**Working style**
- Decide what you can. Do not ask permission for what you can decide.
- Verify against the source before you state a fact. Think harder
  before answering.
- No tolerances: every measurement is exact. Write in plain English.
- Fewer, larger tasks, with phases, a DONE checklist and gates.

**Quoting rulings**
- Never narrow a ruling with your own exceptions.
- Quote rulings verbatim and attributed.
- Label every PA addition as the PA's.
- **Never put your words inside a quoted ruling.**

**Before you answer**
- Do not repeat apologies or admissions Jeff has already heard.
  State the fix and move on.
- Wait for Jeff's push notice before you record a task.
- Never invent results you have not read.

## 3. THE MOST IMPORTANT RULE: there is no AREA

Jeff ruled, session-086: **the IA fixes what it finds, named in the
task or not.**

What went wrong:
- From BP-152 to PERF-005 the PA wrote "Within the AREA" into that
  ruling and attributed it to Jeff. That was false.
- The PA then gave every task file an AREA of its own. A narrow AREA
  cancelled the ruling.
- PERF-005's AREA covered only bpu and ftq (prompts/PERF-005.md:358-366).
  It ran for days, then ended IN-PROGRESS on two testbench fixes the
  AREA blocked.

Now:
- No task file gets an AREA or any other limit on what the IA may fix.
- The IA may change any file **except** planning files (it proposes
  the text), CLAUDE.md, examples/ (FDT-2a), tools/known_failures.txt
  (Jeff's) and tools/cbp2025 (the CBP submodule).
- The corrected standing blocks are in the claude.ai project at
  **claude/pa_standing_task_text.md**. Quote Blocks 1-4 from there,
  unchanged, into every task.
- Before you deliver a task, check it: every stop, limit or exception
  must trace to a ruling of Jeff's or to Block 4's exclusions.
  Remove anything else.

## 4. State at the end of session-086

**On origin/main**, at f88a61b:
- BP-154 is committed (e7002b7).
- PERF-004 is committed (2d1e330).
- The planning recording of both is committed (aceaa05).
- Then Jeff's Blog 23 commits.

**Delivered by the PA but not yet on origin.** Jeff may have them
locally.
- R1 to R13 accepted: perf_decisions.md, ftq_ifu_interfaces.md,
  CLOSED_TECH_DEBT.md.
- prompts/PERF-005.md.
- PROJECT_CORE.md: misc/ras_theory_of_operation.md was replaced by
  blogs/BLOG_bpu_23_ras_theory_of_op.md.
- check_planning.sh at 73 files.
- PROJECT_STATUS.md entries: "PERF-004 accepted; PERF-005 written" and
  "the AREA withdrawn".

The last set is attached with this handoff. Check origin first. If
the files are not there, they are pending a push.

**PERF-005 has run and ended IN-PROGRESS.**
- Jeff has its results. The PA has not seen them.
- The PA gave Jeff a paste for the IA's PERF-005 session. It withdraws
  the AREA and tells the IA to make the two testbench fixes, run the
  regression once, and set STATUS: COMPLETE if every DONE item holds.
- Expect Jeff to bring the results, finished or not.

## 5. First job of session-087: assess PERF-005

PERF-005 investigates TD#218: why pacino mispredicts so much more than
TAGE192. The task's phases:

| Phase | What it does |
|---|---|
| 0 | Confirm the digest is still the baseline's |
| 1 | Split every mispredict by the reason its predictor decided |
| 2 | Check the fast path's rules; run a study with it off |
| 3 | Re-derive TAGE's history, lookups, updates and allocation, and the SC, on every event; compare the SC with cbp2016 |
| 4 | Build a software twin of pacino's TAGE, in perf/src/twin |
| 5 | Measure each fix alone; run a new baseline if anything changed |
| 6 | Decompose the gap: TAGE192 -> twin -> fast path off -> pacino |

**The leads going in.** These are the PA's sums over baseline.csv:
- **The FTB decides most predictions.** The FTB supplies 542,337,218
  decisions, 3.250% wrong. TAGE supplies 71,005,607, 12.708% wrong.
- **SC's overrides are mostly wrong.** SC makes 10,010,619 overrides,
  and 54.530% of them are wrong.
- **The fast path is the likely cause.** It fires when the FTB's 3-bit
  confidence counter saturates, and one correct outcome after a
  mispredict re-saturates it.
- **PERF-004 Phase 4 (2e6 instructions):**

  | Trace | Baseline | Fast path off | SC off |
  |---|---|---|---|
  | int_6 | 10,290 | 7,605 | 10,491 |
  | web_11 | 45,332 | 46,929 | 43,321 |

**The baseline.**
- 210 runs (105 traces, plain and oracle), digest 0c66fed0.
- Jeff confirmed `make -C perf digest` at 2d1e330.
- pacino / TAGE192 conditional MPKI is 2.48 at 50Perc (8.4173 against
  3.3992).

**How to assess:**
1. Read the whole file, in chunks.
2. Check the arithmetic against the CSVs it names.
3. Check each phase against its requirement.
4. Check each fix's fail-before and pass-after at both slot counts.
5. Check the DONE checklist.
6. Recommend accept or reject for each rule change. Each one was
   measured alone.
7. Deliver the assessment with SendUserFile (attach) and a short reply.

Then wait for the push and record the task.

## 6. Pending for Jeff, in order

1. **PERF-005:** assessment, then the recording.
2. **The permission allow list.** Jeff is capturing the IA's permission
   prompts. PERF-005 also lists them in its Other Notes. Write the
   permissions block for the repository's `.claude/settings.json` from
   that list.
3. **INFRA-017, the Stop hook** (discussed, not written). A Claude
   Code Stop hook blocks the IA from stopping early:
   - it returns exit 2, or decision "block";
   - stop_hook_active prevents loops.
4. **After PERF-005: enlarging TAGE's tables and histories.** This is
   Jeff's next step, on PERF-005's decomposition.
5. **Open debt, see PROJECT_STATUS:**
   - TD#215, predecode M3 keeps a taken no predictor gave;
   - TD#216, cai = jimenez;
   - TD#217, a baseline comparison tool;
   - TD#218, which is PERF-005;
   - TD#212, TD#213 and TD#214, FTB;
   - TD#209, tb_fe_top's backend;
   - TD#190 to TD#193;
   - TD#197's aging options;
   - TD#202 and TD#133.

**Rulings from session-086 to keep:**
- No further RAS task. RAS-2 is closed at 16 entries.
- The BOS jump is a known limitation, not scheduled.
- R2 (BP-154) is committed as built.
- PERF-004's R1 to R13 are accepted.
- PF-18: the immediate backend is the default.
- Jeff's trap-after-branch ruling is built.

## 7. How the PA works with the files

**The working copy**
- Clone or fetch uarchlabs/pacino into a scratch directory. git through
  the proxy works.
- Edit planning files with exact-string Python replacements that
  assert one match.
- Keep each file's line width: 72 in most planning files, 76 in
  perf_decisions.md.

**Each change**
- Add a dated history entry at the end of each changed planning file,
  inside its closing code fence where the file has one.
- Update its `UPDATED:` date.

**PROJECT_STATUS.md**
- A new session entry goes above the previous one.
- The entry ends with a "Documents changed" line and a "Next free"
  line.
- Next free now: BP-155, SYS-003, DOC-017, INFRA-017, TOOLS-008,
  PERF-006, TD#219.

**Debt tables**
- Rows are 77 characters, with the text in 56-column cells. This helper
  writes them:

```python
import textwrap
def row(num, unit, text, w=56):
    lines=textwrap.wrap(text, w, break_long_words=False,
                        break_on_hyphens=False)
    out=[]
    for i,l in enumerate(lines):
        n=f"{num:<3}" if i==0 else "   "
        u=f"{unit:<8}" if i==0 else "        "
        out.append(f"| {n} | {u} | {l:<{w}} |")
    return "\n".join(out)+"\n"
```

- Closed rows move to CLOSED_TECH_DEBT.md, in the same table type.

**check_planning.sh**
- It holds an md5, the first 12 hex characters, for each of 73 files.
  The lines look like `PLAN  PROJECT_STATUS.md  <12 hex>`.
- After any edit, recompute the changed files' lines, add a dated
  comment line near the top, and run the script. It must print
  "73 match, 0 differ, 0 missing".

**Task files**
- They must pass `python3 tools/validate_and_extract.py <file>`, run
  from the repo root. Delete .claude/tmp/current-prompt.md afterwards.
- Background facts are checked against the tree before delivery.
- Never use the RESULTS markers in guidance text.

**Delivering**
- Send every changed file with SendUserFile (attach).
- Say where each one goes.
- Give a commit title and a brief body.

## 8. Process lessons from session-086 (do not repeat)

- **The AREA** (section 3).
- **The oracle check was not required in BP-153 and BP-154**, so it
  lapsed unnoticed. Require all three PF-11 checks whenever a task
  touches the predictors or the harness.
- **Tasks grew past what Jeff asked for.** BP-154 became a revert plus
  a study plus a trace. Tell Jeff the scope in plain words before
  delivering a task.
- **"Trace every count that moves" plus "fix what you find"** produces
  endless follow-ups. Bound the tracing:
  - a timing move is accounted for by its first divergence;
  - the gap to R is a result, not a case.
- **Do not tell Jeff numbers are trustworthy before the checks have
  run.**
- **Do not make Jeff repeat himself.** When he says something is
  settled, it is settled.
