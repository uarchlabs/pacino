Purpose: You are to find a prompt file and execute it, if
there are errors you are to report them and stop
waiting for user interaction.

These are the explicit steps, in order :

1. Seach ./prompts/ for a file named <ID>.md where <ID> is the argument given

2. If not found report the error and stop. Do not proceed

3. Run the validation tool:
   ./tools/validate_and_extract.py <path to found file>

   If the tool returns a non-zero exit code, report the
   validation errors and stop. Do not proceed.

4. If validation passes, read the extracted prompt from:
   .claude/tmp/current-prompt.md

5. Execute the prompt exactly as written.
