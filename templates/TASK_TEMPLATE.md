=============================================================
# Task Header 
=============================================================
:: HEADER:START ::

| Field        | Value                   | Notes                    |
|--------------|-------------------------|--------------------------|
| Task ID      | <BLOCK-NUMBER>          | as needed                |
| Date         | YYYY.MM.DD              |                          |
| Module       | <module>                |                          |
| Run time     |                         |                          |
| Ctx %        |                         |                          |
| Model        | Sonnet 4.6 medium       |                          |
| Resume sha   | <sha>                   |                          |

Task:   [ ] experiment  [ ] implementation  [ ] debug
        [ ] cleanup     [ ] testbench       [ ] verification
Status: [ ] in-progress [ ] complete        [ ] abandoned

# Overview of task

:: HEADER:END ::
=============================================================
# Paste c.code console output and c.ai discussion
=============================================================
:: DISCUSSION:START ::

# Results Discussion 

## Claude.code Console Output

## My Assessment

## Claude.ai Assessment

## Follow-on Actions
- [ ] As needed document here

## CLAUDE.md Updates
TBD as needed document here

## Other Planning File Updates
TBD as needed document here
:: DISCUSSION:END ::
=============================================================
# Claude.code Prompt 
=============================================================
:: PROMPT:START ::

## Task ID
Replace this with the task ID

## Context Loaded
@File-Name replace with any files needed, duplicate as needed or delete

## Hypothesis

## Background

## Binding Previous Decisions

## Specific Requirements

## Constraints

## Deliverables
Note: If a new module is to be created ensure that claude.code is allowed
or told to modify the Makefile for lint checking at the minimum.

:: PROMPT:END ::
=============================================================
# Results Capture
=============================================================
:: RESULTS:START ::

## Summary
RESULTS NOT YET WRITTEN -- replace this line when filling in.

## Test Matrix (testbench sessions only, omit otherwise
For each test case document:
- Test name
- Rule or rules exercised (reference rule doc and row/table)
- Setup: initial RAM state, struct fields driven
- Stimulus: which signals asserted and values
- Expected outcome: which RAM entries change and how
- Pass/fail criterion

## What was delivered

## Test Case Results

## Assumptions made not explicit in the prompt

## Decisions made not explicit in the prompt

## RVA23 compliance risks and gaps noticed

## Deferred Work

## Other Notes

:: RESULTS:END ::
