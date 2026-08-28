#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Co-Design" > ho
echo "which is part of RISC-V RVA23 Design"              >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "I have attached the following " >> ho
echo "- planning/PROJECT_CORE.md"     >> ho
echo "- planning/PROJECT_STATUS.md"   >> ho
echo "- CLAUDE.md"                    >> ho
echo "- templates/TASK_TEMPLATE.md"   >> ho
echo "All experiment files need to follow the task template exactly. " >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "The PA session hand off file path: " >> ho
echo "- pa_handoffs/session_handoff-$1.md"     >> ho
## -------------------------------------------------------------
#echo "" >> ho
#echo "Cache RTL has been developed using the external cgen tool. " >> ho
#echo "This is an overview"           >> ho
#echo "planning/arch/pacino_cache.md" >> ho
## -------------------------------------------------------------
echo "" >> ho
cat planning/PROJECT_CORE.md          >> ho
cat planning/PROJECT_STATUS.md        >> ho
cat CLAUDE.md                         >> ho
cat templates/TASK_TEMPLATE.md        >> ho
cat pa_handoffs/session_handoff-$1.md >> ho
