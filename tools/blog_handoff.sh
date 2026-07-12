#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Blog-Gen" > ho
echo "which is part of RISC-V RVA23 Design"            >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "I have attached the following "        >> ho
echo "- planning/BLOG_GENERATION_PROCESS.md" >> ho
echo "- blog/BLOG_bpu_9_tage_coverage.md"    >> ho
echo "- blog/BLOG_bpu_10_ittage_planning.md" >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "This the session hand off file name is: " >> ho
echo "- blog_handoffs/blog_handoff-$1.md"       >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat planning/BLOG_GENERATION_PROCESS.md >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat blogs/BLOG_bpu_9_tage_coverage.md    >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat blogs/BLOG_bpu_10_ittage_planning.md >> ho
echo "# Separator ---------------------------------------------------" >> ho
cat blog_handoffs/blog_handoff-$1.md    >> ho
