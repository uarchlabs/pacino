# PA brief: frontend release tags, and the demo scenarios in the regression

For a PA session. The task is to plan an IA task file (proposed category TOOLS or DOC; the PA
assigns the ID) from the problem and decisions below. Jeff has agreed the direction and the two
decisions in section 3; the open questions in section 5 are for the PA and Jeff to settle before
the task file is written.

---

## 1. Background

The frontend demo, `examples/fe_demo/`, is now published as Showcase release 01 in the Pacino
docs (`docs/showcase/`, built from `examples/fe_demo/docs/` through a symlink, B6-1 and B6-2).

- 24 scenarios, FD-1 to FD-24, listed in the `SCENARIOS` variable of `examples/fe_demo/Makefile`.
  Four run on the two-slot model (`SCEN_2S`); the rest on the one-slot model.
- Each scenario self-checks at the end of its run and prints a PASS/FAIL result line (FD-0c, the
  FDT-10 result line).
- Each scenario has a page, `examples/fe_demo/docs/fdNN_<name>.md`. The pages cite specific
  cycles and events in timeline tables. Example, `fd09_tage.md`: `uaon` first increments 0 to 1
  at cycle 225, provider T2 / alternate T1; `uaon` reaches 8 at 441; first prediction from T0
  by use_alt_on_na at 460; the back edge falls through at 1355; the run ends at 1364.
- Each scenario writes an FST waveform, `out/<scenario>/<scenario>.fst`, and has a Surfer signal
  setup, `waves/<scenario>.sucl`.
- `tools/publish_waves.py` runs all scenarios and force-pushes the FSTs and `.sucl` files, with a
  `manifest.json` recording the pacino commit, to the `uarchlabs/pacino-waves` repo on GitHub
  Pages. Each FD page has an "Open waveform" link that opens that scenario in Surfer's web build.
- All 24 scenarios pass. `make -k scenarios` takes about 33 s with ccache warm, including both
  model builds.

## 2. The problem

**A scenario can pass its self-check while the behavior its page describes has changed.** An
RTL change can shift a documented event by a few cycles, change which TAGE table provides, or
reorder a redirect, and the end-of-run proof still holds. The page and the published waveform
then describe something the RTL no longer does, and nothing reports it.

Two further gaps:

- **The scenarios are not in the regression.** `tools/regress.sh` scans only Makefiles under
  `rtl/`, so `examples/fe_demo/Makefile` is outside it. The regression's own rules (every
  defined target in `REGRESS_TARGETS` or `REGRESS_EXCLUDE`, failures waived only through
  `tools/known_failures.txt`, any Verilator `%Warning` line fails a target) would then need to
  apply to the demo's Makefile too.
- **Nothing ties a published release to an RTL state.** The showcase pages and the waveforms in
  `pacino-waves` should come from one identified state of the frontend RTL.

## 3. Decisions (Jeff, agreed)

1. **Tags.** Annotated git tags `fe-<major>.<minor>`. A tag marks an RTL state that the showcase
   documents, with waveforms built from it. `fe-1.0` is the frontend-RTL-complete milestone.
   - New minor: RTL changes that alter documented behavior, with the pages and expectations
     updated to match.
   - New major: new showcase scope.
   - A fix that changes no documented behavior needs no tag.
   - `publish_waves.py` publishes only from a commit at an `fe-*` tag (or with an explicit
     override), and records the tag in `manifest.json`. The Showcase landing page states which
     tag it documents.
   - Optionally, a GitHub Release per tag with a short changelog.
2. **"Works as described" is checked at two levels:**
   - **Level 1, documented events: FAILS the regression.** Each scenario gets a
     machine-readable expectations file (for example `examples/fe_demo/expect/fdNN_<name>.json`)
     listing each documented event: cycle, signal condition, and the page section it supports. A
     checker evaluates them against the run. A mismatch is reported as doc drift: either the RTL
     change is wrong, or the page and its expectations must be updated deliberately, with a new
     tag.
   - **Level 2, waveform fingerprint: WARNS only.** A digest of the decoded values of each
     scenario's `.sucl` signals over the whole run. A change with Level 1 passing means the
     published waveforms are stale: "waveforms changed; review and republish". The digest must
     be computed from decoded signal values, not from the FST file's bytes (the FST header holds
     tool and version data, and compression can vary).
   - **Page-to-expectations cross-check.** Every cycle number in a page's timeline table must
     appear in that scenario's expectations file, so a page edit can't drift from its checks.
3. **The scenarios join the regression**, through the same `REGRESS_TARGETS` mechanism, so the
   existing pre-push hook (`tools/hooks/pre-push`, which runs `tools/regress.sh`) catches drift
   before a push.

## 4. Constraints the task must respect

From `pacino/CLAUDE.md` and the demo's existing structure:

- `planning/`, `pa_handoffs/` and `docs/` are read-only for the IA unless the task file carries a
  waiver from Jeff naming the files and the task ID.
- A new lint, sim or cov target goes in `REGRESS_TARGETS` or in `REGRESS_EXCLUDE` with a reason;
  `regress.sh` fails on a target in neither. The IA never edits `tools/known_failures.txt`.
- `regress.sh` runs each target with `make -B`, which forces the demo's model builds every time.
  The run-time cost of that, cold, needs measuring.
- The IA proposes the first expectations from the current pages and runs; Jeff reviews them.
  Expected values must not be derived only from the IA's own reading of the current RTL output:
  the page is the reference, and a disagreement between page and run is reported, not resolved
  by the IA.
- `RVA_ROOT` may point at a different clone; the task must build the tree it is run in.
- The demo pages are the source of truth for the documented behavior. Their text changes only
  with Jeff's approval.
- American English. "IA task" and "PA session" terminology.

## 5. Open questions for the PA

1. **What the Level 1 checker reads.** The FST through a reader (Python `pylibfst`, `fst2vcd`, or
   Verilator's own API), or the frontend text trace of `planning/observ/fe_trace_decisions.md`
   (DRAFT, session-080) if it is built and emitted by the demo runs. Which is simpler, and which
   is more robust as signal names change?
2. **The expectation format.** How a "signal condition" is written: signal path and value at a
   cycle; an event that must occur within a cycle window; ordering constraints only. Exact cycles
   are strict and will churn on harmless timing changes; windows are looser. Which events need
   exact cycles?
3. **How `regress.sh` reaches `examples/`.** Extend its scan to `examples/*/Makefile`, or add a
   list of extra Makefile directories. The demo's Makefile must then define `regress_list` and
   classify every target (`help`, `build`, `clean`, `view` and each scenario).
4. **Where the Level 2 digest is stored** (a committed file per scenario, or one manifest) and
   how a deliberate waveform change updates it.
5. **The publish gate.** Refuse to publish from an untagged commit, or warn; and whether to
   refuse when Level 1 fails.
6. **Ordering.** Whether tagging and the publish-script change come in the same task as the
   checker, or as a separate, smaller task first.
7. **Waiver.** Whether the task needs to touch `docs/` (for example, the Showcase landing page
   naming the tag) or the FD pages beyond their headers. If so, the task file needs Jeff's
   waiver naming those files.

## 6. Files involved

- `examples/fe_demo/Makefile`, `examples/fe_demo/docs/*.md`, `examples/fe_demo/waves/*.sucl`,
  `examples/fe_demo/out/` (generated)
- `tools/regress.sh`, `tools/hooks/pre-push`, `tools/known_failures.txt` (read only)
- `tools/publish_waves.py`, `tools/mkdocs_showcase.py`
- `planning/showcase/fe_demo_scenarios.md` (the FD-N registry), `planning/observ/fe_trace_decisions.md`
- `docs/showcase/index.md` (only with a waiver)
