#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Blog-Gen" > ho
echo "which is part of RISC-V RVA23 Design"            >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "I have attached the following "        >> ho
echo "- planning/PROJECT_CORE.md"            >> ho
echo "- planning/PROJECT_STATUS.md"          >> ho
echo "- planning/BLOG_GENERATION_PROCESS.md" >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "This the session hand off file name is: " >> ho
echo "- blog_handoffs/blog_handoff-$1.md"       >> ho
# -------------------------------------------------------------

echo "# Separator ---------------------------------------------------" >> ho
cat planning/PROJECT_CORE.md >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat planning/PROJECT_STATUS.md >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat planning/BLOG_GENERATION_PROCESS.md >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat blog_handoffs/blog_handoff-$1.md    >> ho
