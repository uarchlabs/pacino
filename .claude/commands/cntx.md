Purpose: You are to report how much context was used in the current
session as a single percentage, the number of compactions, and the
run time of the last /run task, write a file with context usage
information, and record those figures in the task file of that /run
task.

The task file is $ARGUMENTS, a task ID such as DOC-009, whose file is
prompts/<task ID>.md. If no argument is given, use the task ID of the
last /run in this session's transcript. If neither gives a task ID,
or prompts/<task ID>.md does not exist, report the error and stop.

The context report is not a standalone document, so standard
header/meta data is not required.

- Do not write the standard SPDX-License header section.
- Do not write the conventional file meta data, FILE/SOURCE
- Do not write the session info.

The slash context command should have been issued before issuing this
command.

If there are errors you are to report them and stop waiting for user
interaction.

These are the explicit steps, in order :

1. Answer the question how much context was used ? and report in the
   console
2. Count the compactions in the current session: the number of
   "compact_boundary" entries in this session's transcript file
   (~/.claude/projects/<project-dir>/<session-id>.jsonl). Report the
   count in the console. If the transcript cannot be found or read,
   report the error and stop. Do not estimate the count from the
   conversation.
3. Measure the run time of the last /run task in the same transcript
   file by running:
     ./tools/run_time.py <transcript path>
   Report its output line in the console. If the tool exits non-zero,
   report its error and stop. Do not estimate the run time from the
   conversation or from file timestamps.
4. write context usage to new file context-report.md to the root of
   the repo. The first lines after the heading are:
     Compactions: <integer>
     Run time: <output of step 3>
   followed by the usage from /context.
5. Overwrite any previous context-report.md file.
6. In the task file, between :: HEADER:START :: and :: HEADER:END ::,
   replace the Value cell of exactly three rows and nothing else:
     Run time    the active duration from step 3 only, the first
                 field, as 2h.15m.41s; not the wall time, the times or
                 the /run name that follow it
     Ctx %       the percentage from step 1, as 19%
     Resume sha  the session id, the file name of the transcript of
                 step 2 without .jsonl
   Keep each row's Field and Notes cells. If a row is missing, report
   it and stop.
7. In the task file, replace everything between the line
   :: CONTEXT:START :: and the line :: CONTEXT:END :: with the contents
   of context-report.md. Keep both marker lines. If either marker is
   missing, or appears more than once, report it and stop.
8. Change nothing else in the task file. Report in the console the
   three header values written and the number of lines written between
   the CONTEXT markers.
9. Execute the prompt exactly as written.
