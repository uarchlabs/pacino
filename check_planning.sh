#!/usr/bin/env bash
# Compare planning files against the delivered versions.
# Baseline: session-071, except the files updated in session-073
# (ftb_decisions.md, ftb_interfaces.md, ubtb_interfaces.md,
# ftq_bpu_interfaces.md, ftq_entry_formats.md,
# ittage_table_entry_formats.md, ftq_backend_interfaces.md)
# and the files updated in session-074 (PROJECT_CORE.md,
# PROJECT_STATUS.md, CLAUDE.md, dcd_decisions.md,
# cachegen_decisions.md (new), l1i_ifu_interfaces.md,
# fe_decisions.md, icache_decisions.md, ifu_decisions.md,
# ibuf_decisions.md, ftq_ifu_interfaces.md, itlb_ifu_interfaces.md,
# ftq_decisions.md, mmu_decisions.md,
# ifu_ibuf_interfaces.md), and the files updated in session-075
# (PROJECT_STATUS.md, ftq_decisions.md, ftq_entry_formats.md,
# ftq_ifu_interfaces.md, ifu_decisions.md, ifu_ibuf_interfaces.md,
# itlb_ifu_interfaces.md, ftq_bpu_interfaces.md, dcd_decisions.md,
# ibuf_decisions.md, itlb_decisions.md, mmu_decisions.md,
# fe_decisions.md, itlb_l2tlb_interfaces.md, ftq_backend_interfaces.md,
# bp_arb_spec.md, ftb_decisions.md, ras_decisions.md,
# ras_interfaces.md, ubtb_interfaces.md, ftb_interfaces.md), and the
# files updated in session-076 (PROJECT_STATUS.md, bp_arb_spec.md,
# bp_cluster.md, bp_history_decisions.md, bp_history_interfaces.md,
# fe_decisions.md,
# ftb_confidence_override_rules.md, ftb_decisions.md,
# ftb_interfaces.md, ftq_backend_interfaces.md,
# ftq_bpu_interfaces.md, ftq_decisions.md, ftq_entry_formats.md,
# ittage_interfaces.md, loop_pred_interfaces.md, ras_decisions.md,
# ras_interfaces.md, sc_interfaces.md, tage_interfaces.md,
# ubtb_interfaces.md, cachegen_decisions.md, icache_decisions.md,
# ifu_decisions.md, mmu_decisions.md, itlb_ifu_interfaces.md,
# l1i_ifu_interfaces.md), and the files updated in session-077
# (PROJECT_STATUS.md, PROJECT_CORE.md, mmu_decisions.md,
# itlb_decisions.md, ifu_decisions.md, dcd_decisions.md,
# fe_decisions.md, itlb_l2tlb_interfaces.md, itlb_ifu_interfaces.md,
# ifu_ibuf_interfaces.md, ptw_mem_interfaces.md (new)), and the
# files updated in session-077 after BP-123 (PROJECT_STATUS.md,
# dcd_decisions.md, mmu_decisions.md, itlb_decisions.md,
# ifu_decisions.md, icache_decisions.md, cachegen_decisions.md,
# fe_decisions.md, itlb_l2tlb_interfaces.md, itlb_ifu_interfaces.md,
# ifu_ibuf_interfaces.md, l1i_ifu_interfaces.md,
# ftq_ifu_interfaces.md, ftq_decisions.md), and the files updated in
# session-077 after BP-124 (PROJECT_STATUS.md, dcd_decisions.md,
# mmu_decisions.md, itlb_decisions.md, ifu_decisions.md,
# itlb_l2tlb_interfaces.md, itlb_ifu_interfaces.md,
# ifu_ibuf_interfaces.md, ftq_ifu_interfaces.md, ftq_decisions.md), and
# the files updated in session-077 after BP-125 (PROJECT_STATUS.md,
# dcd_decisions.md, ifu_decisions.md, ifu_ibuf_interfaces.md,
# icache_decisions.md, l1i_ifu_interfaces.md, cachegen_decisions.md,
# ftq_decisions.md, ftq_ifu_interfaces.md), and the file updated when
# BP-126 was written and after it ran (PROJECT_STATUS.md), and the
# files updated in session-077 after BP-126 (PROJECT_STATUS.md,
# tage_cntrl_decisions.md, tage_cntrl_ctr_update_rules.md,
# sram_init.md, ras_decisions.md, ras_interfaces.md,
# ftq_bpu_interfaces.md, bpu_port_inventory.md, bp_arb_spec.md,
# sc_interfaces.md, bp_history_interfaces.md, ftb_interfaces.md,
# tage_coverage_plan.md), and the files updated when BP-127 was
# written (PROJECT_STATUS.md, sc_table_hash_rules.md,
# sc_table_interfaces.md, bp_history_interfaces.md,
# tage_coverage_plan.md), and the files updated after BP-127
# (PROJECT_STATUS.md, sc_tb_decisions.md, sc_table_hash_rules.md),
# and the files updated in session-078 (PROJECT_STATUS.md,
# tage_table_interfaces.md), and the files updated in session-078
# after BP-130 (PROJECT_STATUS.md, bp_history_interfaces.md,
# bp_history_decisions.md, ftq_bpu_interfaces.md), and the files
# updated after BP-131 (PROJECT_STATUS.md, ftb_decisions.md,
# ubtb_interfaces.md), and the files updated after BP-132
# (PROJECT_STATUS.md, tage_interfaces.md, ittage_interfaces.md,
# bp_arb_spec.md), and the file updated in session-079
# (PROJECT_STATUS.md), and the files updated in session-079 after
# BP-134 (PROJECT_STATUS.md, tage_cntrl_ctr_update_rules.md,
# tage_cntrl_decisions.md, tage_interfaces.md, ras_decisions.md,
# ras_interfaces.md, sc_decisions.md, sc_interfaces.md,
# ubtb_interfaces.md, ras_theory_of_operation.md (new, location MISC)),
# and the file added in session-079 for TD#178 (csr_decisions.md),
# and the files updated in session-079 after SYS-001
# (PROJECT_STATUS.md, csr_decisions.md, mmu_decisions.md,
# l1i_ifu_interfaces.md, ras_theory_of_operation.md).
# CLAUDE.md is checked from the repo root (UNKN) since session-074.
# Usage: ./check_planning.sh [root]   (default: current directory)
#   root is the repo root, the directory that contains planning/.
# Exit status: 0 if every file matches, 1 otherwise.

ROOT="${1:-.}"

PLAN="planning"
ARCH="planning/arch"
INTF="planning/interfaces"
TEST="planning/testbenches"
VERF="planning/verification"
MISC="misc"
UNKN="."

# One file per line: <location> <file> <md5 prefix, 12 chars>
# <location> is one of PLAN ARCH INTF TEST VERF MISC UNKN. Blank lines and # are ignored.
read -r -d '' FILES <<'EOF'
PLAN  PROJECT_CORE.md                   6ad2291625f2
PLAN  PROJECT_STATUS.md                 253c6997b061

UNKN  CLAUDE.md                         21a3681a7f6f

ARCH  bp_arb_spec.md                    2c98a9d4f798
ARCH  bp_cluster.md                     187952e94e30
ARCH  bp_history_decisions.md           cf35b25e9dfb
ARCH  cachegen_decisions.md             de8bfe4e9845
ARCH  csr_decisions.md                  1504051434a5
ARCH  dcd_decisions.md                  1134f749b0d9
ARCH  fe_decisions.md                   0ec67f83aa96
ARCH  ftb_decisions.md            5872deda6dc9
ARCH  ftq_decisions.md            4e77292e528d
ARCH  ftq_entry_formats.md        2301dd3f97e2
ARCH  ibuf_decisions.md                 34f9eb23bd4f
ARCH  icache_decisions.md               29d94d35d776
ARCH  ifu_decisions.md            23b78769459f
ARCH  itlb_decisions.md                 165b7936bf55
ARCH  ittage_cntrl_ctr_update_rules.md  1c49fda9242e
ARCH  ittage_cntrl_decisions.md         28a3b83f2f34
ARCH  mmu_decisions.md                  549749154c67
ARCH  ras_decisions.md                  d28627b187ed
ARCH  sc_decisions.md                   16f40a258f62
ARCH  sc_table_hash_rules.md            3954fc46bace
ARCH  sram_init.md                      d6cefefe7fc5
ARCH  tage_cntrl_uaon_update_rules.md   be55531dd5c0
ARCH  tage_cntrl_alloc_rules.md         3a22df5e85f3
ARCH  tage_cntrl_decisions.md           e75047b88350
ARCH  tage_table_entry_formats.md       bfd6ee8f1d3d
ARCH  tage_table_hash_rules.md          d829daf22e1c
ARCH  ittage_table_hash_rules.md        e9d7d77217dc

ARCH  ittage_cntrl_alloc_rules.md       a61a19c81fa5
ARCH  ittage_cntrl_use_update_rules.md  b729da8f6a79
ARCH  ittage_table_entry_formats.md  abee67476ca8
ARCH  tage_cntrl_ctr_update_rules.md    da3e4ab414b6
ARCH  tage_cntrl_use_update_rules.md    d1dc910897a2
ARCH  ftb_confidence_override_rules.md  34362cfb6dd7
ARCH  pacino_cache.md                   f871e6288ecf
TEST  tage_tb_decisions.md              ae2979a6d9f0
TEST  tage_mtb_decisions.md             33a02ac0df2c
TEST  sc_tb_decisions.md                85577a58ad65
TEST  manual_tb_decisions.md            9ac8ad00f83e
VERF  tage_coverage_plan.md             497bc9a790a3

INTF  ittage_table_interfaces.md        152940fce590
INTF  tage_table_interfaces.md          adfbd02af482
INTF  bp_history_interfaces.md          b7cb5aa4c164
INTF  bpu_port_inventory.md             d6d9e24420b3
INTF  ftb_interfaces.md           12d47fb5ddbc
INTF  ftq_backend_interfaces.md   1c425156a6e7
INTF  ftq_bpu_interfaces.md       004c794a38ff
INTF  ftq_ifu_interfaces.md       2cecf4e55ced
INTF  ifu_ibuf_interfaces.md      ab4d4051748b
INTF  itlb_ifu_interfaces.md            ab489f6db489
INTF  itlb_l2tlb_interfaces.md          bed8d1ddacae
INTF  ptw_mem_interfaces.md            053eb7faf457
INTF  ittage_interfaces.md              14f901826cca
INTF  l1i_ifu_interfaces.md             3fb484b495e3
INTF  loop_pred_interfaces.md           f1eb16c7ce58
INTF  ras_interfaces.md                 63affca67938
INTF  sc_interfaces.md                  8c7c5b2851ff
INTF  sc_table_interfaces.md            b442b10dab0f
INTF  tage_interfaces.md                8c352e5411ea
INTF  ubtb_interfaces.md          7f692dd5a124

MISC  ras_theory_of_operation.md      70934d94b58a

EOF

match=0; differ=0; missing=0; bad=0; total=0

while read -r loc file want; do
  [[ -z "$loc" || "$loc" == \#* ]] && continue
  total=$((total + 1))

  case "$loc" in
    PLAN|ARCH|INTF|TEST|VERF|MISC|UNKN) rel="${!loc}/$file" ;;
    *) printf 'BADLOC   %s  (location "%s")\n' "$file" "$loc"
       bad=$((bad + 1)); continue ;;
  esac
  rel="${rel#./}"
  path="$ROOT/$rel"

  if [[ ! -f "$path" ]]; then
    printf 'MISSING  %s\n' "$rel"
    missing=$((missing + 1))
    continue
  fi
  got=$(md5sum "$path" | cut -c1-12)
  if [[ "$got" == "$want" ]]; then
    printf 'MATCH    %s\n' "$rel"
    match=$((match + 1))
  else
    printf 'DIFFER   %s  (got %s, want %s)\n' "$rel" "$got" "$want"
    differ=$((differ + 1))
  fi
done <<< "$FILES"

printf '\n%d match, %d differ, %d missing, %d bad location, of %d\n' \
  "$match" "$differ" "$missing" "$bad" "$total"

[[ $differ -eq 0 && $missing -eq 0 && $bad -eq 0 ]]
