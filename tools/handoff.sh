#! /usr/bin/env bash

rm -f ho
echo "We are resuming a session for the RVA23 Co-Design" > ho
echo "which is part of RISC-V RVA23 Design"              >> ho

echo "I have attached the following " >> ho
echo "- ANTIPATTERNS.md"       >> ho
echo "- PROJECT_CORE.md"       >> ho
echo "- PROJECT_STATUS.md"     >> ho
echo "- session_handoff-$1.md" >> ho
echo "- CLAUDE.md"             >> ho

echo "- ittage_table_hash_rules.md" >> ho
echo "- ittage_cntrl_decisions.md" >> ho
echo "- ittage_cntrl_uaon_update_rules.md" >> ho
echo "- ittage_table_hash_rules.md" >> ho
echo "- ittage_cntrl_alloc_rules.md" >> ho
echo "- ittage_cntrl_use_update_rules.md" >> ho
echo "- ittage_cntrl_ctr_update_rules.md" >> ho
echo "- ittage_table_interfaces.md" >> ho
echo "- ittage_interfaces.md" >> ho
echo "- bp_defines_pkg.sv" >> ho
echo "- bp_structs_pkg.sv" >> ho
echo "- ittage_table.sv" >> ho

echo "Process this and suggest the next steps when you are ready" >> ho
echo "" >> ho

cat planning/ANTIPATTERNS.md                        >> ho
cat planning/PROJECT_CORE.md                        >> ho
cat planning/PROJECT_STATUS.md                      >> ho
cat pa_handoffs/session_handoff-$1.md               >> ho
cat CLAUDE.md                                       >> ho
cat planning/interfaces/ittage_interfaces.md        >> ho
cat planning/interfaces/ittage_table_interfaces.md  >> ho
cat planning/arch/ittage_cntrl_decisions.md         >> ho
cat planning/arch/ittage_cntrl_alloc_rules.md       >> ho
cat planning/arch/ittage_cntrl_ctr_update_rules.md  >> ho
cat planning/arch/ittage_cntrl_uaon_update_rules.md >> ho
cat planning/arch/ittage_cntrl_use_update_rules.md  >> ho
cat planning/arch/ittage_table_hash_rules.md        >> ho
cat rtl/core/frontend/bpu/rtl/bp_defines_pkg.sv     >> ho 
cat rtl/core/frontend/bpu/rtl/bp_structs_pkg.sv     >> ho
cat rtl/core/frontend/bpu/rtl/ittage_table.sv     >> ho
