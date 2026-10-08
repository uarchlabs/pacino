Purpose: You are to report how much context was used in the current
session as a single percentage, and the number of compactions, and
write a file with context usage information.

This output file will be manually inserted into the correct prompt.

Therefore standard header/meta data is not required.

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
3. write context usage to new file context-report.md to the root of
   the repo. The first line after the heading is:
     Compactions: <integer>
   followed by the usage from /context.
4. Overwrite any previous context-report.md file.
5. Execute the prompt exactly as written.
