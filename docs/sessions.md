---
hide:
  - navigation
  - toc
title: "IA task browser"
---

??? note "Anatomy of a task file"

    **Written before the run**, by the designer and the PA:

    - **Header**: task ID, date, module, model, runtime, context used,
      PA session, task type, mode and status
    - **Overview**: a short summary
    - **Context**: the files the IA loads, kept deliberately small
    - **Hypothesis**: the question the task is asking
    - **Background**: what the IA, or a human reader, needs to know
    - **Binding previous decisions**: earlier decisions that apply, which
      the IA can use to check that the task makes sense
    - **Requirements**: what the run must deliver
    - **Constraints**: the limits of the run

    **Written by the IA, in Results Capture:**

    - What was delivered, the test matrix and the test results
    - Assumptions and decisions the IA made where the prompt gave no
      guidance
    - RVA23 compliance risks and edge behavior
    - Deferred work and other notes
    - Files modified, and a context usage report

    **Written after the run**, in the results discussion: the IA's console
    output, my assessment and the PA's assessment.

<iframe
  src="../sessions.html"
  title="Pacino IA task browser"
  style="width:100%; height:calc(100vh - 60px); border:none; display:block;"
></iframe>
