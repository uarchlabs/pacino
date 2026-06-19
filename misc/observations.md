<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->


# Observations: Prompt Detail and LLM Leverage

## User question

user: As experiment prompts become more detailed, does that diminish the 
leverage that Claude Code provides?

## The Short Answer

No -- but only if the detail in the prompts reflects your architectural
decisions, not Claude's.

## Two Kinds of Prompt Detail

### Good detail -- constraining decisions you have already made

Examples from this project:
- Separate vec_decode_t struct alongside decode_t -- your decision
- Stateless decoder, vtype as producer/consumer dependency -- your decision
- ASCII only in all RTL comments -- your decision
- funct6 values must come from rv_v tools file, not training data -- your decision

This kind of detail does not diminish Claude Code's leverage. It directs
that leverage toward your architecture rather than letting Claude invent one.
The implementation work -- reading the spec, writing correct SystemVerilog,
running Verilator, iterating on errors -- is still entirely Claude Code's job.

### Bad detail -- over-specifying implementation

Examples of what to avoid:
- Telling Claude exactly how to structure a case statement
- Dictating variable names at the signal level
- Specifying exactly which lines of code to write

If prompts start looking like pseudocode you are writing the RTL yourself
and using Claude as a syntax checker. That does diminish leverage.

## Where the Prompts in This Project Sit

The detail in these prompts is almost entirely architectural constraint and
scope management. The implementation remains open:

- How to structure the funct6 decode logic -- Claude decides
- How to organize the testbench -- Claude decides
- How to handle encoding edge cases -- Claude decides
- How to iterate on Verilator errors -- Claude handles autonomously

## The Real Leverage Metric

Prompt length is not the right metric. The better measure is the ratio of:

    lines of RTL Claude writes
    --------------------------
    lines of prompt you write

For a typical decoder experiment in this project that ratio is approximately
500:1 or better. That is still enormous leverage regardless of prompt length.

## One Genuine Risk to Watch

As prompts get more detailed there is a temptation to keep adding constraints
until the experiment is fully specified and nothing is left for Claude to
decide. That is the boundary to watch -- not prompt length itself.

A useful test: if you removed the constraints section from a prompt, would
Claude still produce something architecturally correct? If yes, the
constraints are probably over-specified. If no, they are earning their place.

## Summary

| Prompt detail type               | Effect on leverage |
|----------------------------------|--------------------|
| Architectural decisions          | Preserves leverage -- directs it |
| Scope boundaries                 | Preserves leverage -- focuses it |
| Implementation specification     | Reduces leverage   |
| Pseudocode-level instruction     | Eliminates leverage |

The goal is prompts that are architecturally precise and implementationally
open. Detail that reflects your design intent is an asset. Detail that
substitutes for Claude's judgment is a liability.

