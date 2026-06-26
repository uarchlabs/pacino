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
echo "The the session hand off file name is: " >> ho
echo "- pa_handoffs/session_handoff-$1.md"     >> ho
# -------------------------------------------------------------
echo "" >> ho
echo "This session will address G20/G21/G22"  >> ho
echo "See project status for the description" >> ho
#echo "planning/arch/ftb_decisions.md"   >> ho
# -------------------------------------------------------------
#echo "" >> ho
#echo "This session will build the FTB"  >> ho
#echo "These are the FTB planning files" >> ho
#echo "planning/arch/ftb_decisions.md"   >> ho
#echo "planning/interfaces/ftb_interfaces.md" >> ho
#echo "planning/arch/ftb_confidence_override_rules.md" >> ho
# -------------------------------------------------------------
echo "" >> ho
cat planning/PROJECT_CORE.md           >> ho
cat planning/PROJECT_STATUS.md         >> ho
cat templates/TASK_TEMPLATE.md         >> ho
cat pa_handoffs/session_handoff-$1.md  >> ho
cat CLAUDE.md                          >> ho
#cat planning/arch/ftb_decisions.md     >> ho
#cat planning/interfaces/ftb_interfaces.md >> ho
#cat planning/arch/ftb_confidence_override_rules.md >> ho
