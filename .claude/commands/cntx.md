Purpose: You are report how much context used in the current session 
as a single percentage and write a file with context usage information

This output file will be manually inserted into the correct prompt.

Therefore standard header/meta data is not required.

- Do not write the standard SPDX-License header section.
- Do not write the conventional file meta data, FILE/SOURCE
- Do not write the session info.

The slash context command should have been issued before issuing this command.

If there are errors you are to report them and stop waiting for user 
interaction.

These are the explicit steps, in order :

1. Answer the question how much context was used ? and report in the console

2. write context usage to new file context-report.md to the root of the repo

3. Overwrite any previous context-report.md file.

4. Execute the prompt exactly as written.

