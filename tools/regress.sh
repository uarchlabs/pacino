#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/regress.sh [ROOT] -- run every test target in every rtl/ Makefile
#
# ROOT defaults to the repo root (the parent of this script's directory).
# Pass a path to run against a scratch copy of the tree.
#
# For each Makefile found under ROOT/rtl:
#   - read its defined targets from make's rule database (make -pRrq)
#   - read its regression set from `make regress_list`, which prints
#     REGRESS_TARGETS (run) and REGRESS_EXCLUDE (never run)
#   - fail if any defined target is in neither list, if a listed name is
#     not defined, or if a name is in both lists. A target added to a
#     Makefile cannot be left out of the regression without this failing.
#   - run each REGRESS_TARGETS entry with its own `make -B -C <dir> <t>`,
#     continuing past failures
#
# A target FAILS when make exits non-zero or its log holds any Verilator
# %Warning line. Failures are compared with ROOT/tools/known_failures.txt
# (missing file = empty). Line format:
#   <makefile dir> <target> TD#<n> <description>
# with # comments and blank lines ignored. The third field must be
# TD#<n> or TD#? (BP-132, TD#130); a line without one, or with fewer
# than three fields, is reported as malformed and waives nothing.
#
# Exit 0 only when every failing target is listed there, every listed
# target still fails, no listed line is malformed, and no Makefile has
# a regression-set error.
# Logs are kept in a temp directory whose path is printed at the end.

set -u

ROOT=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
if [ ! -d "$ROOT/rtl" ]; then
  echo "regress: no rtl/ directory under '$ROOT'" >&2
  exit 2
fi
ROOT=$(cd "$ROOT" && pwd)

# bpu and ftq include $(RVA_ROOT)/rtl/Vars.mk and take VERILATOR from
# $(RVA_ROOT)/tools/bin. Point it at the tree under test.
export RVA_ROOT=$ROOT

KNOWN_FILE=$ROOT/tools/known_failures.txt
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/regress.XXXXXX")

# -- tree identity for the summary header
if git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  GIT_SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)
  if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
    GIT_STATE=dirty
  else
    GIT_STATE=clean
  fi
else
  GIT_SHA=n/a
  GIT_STATE="not a git tree"
fi

# -- known failures: key "<dir> <target>" -> TD field
declare -A KNOWN_TD=()
declare -A KNOWN_SEEN=()
BAD_KNOWN=()    # malformed known_failures.txt lines
if [ -f "$KNOWN_FILE" ]; then
  kline=0
  while read -r kdir ktgt ktd _; do
    kline=$((kline + 1))
    case "$kdir" in ''|\#*) continue ;; esac
    if [ -z "$ktgt" ] || ! [[ "$ktd" =~ ^TD#([0-9]+|\?)$ ]]; then
      msg="line $kline: '$kdir ${ktgt:-<no target>} ${ktd:-<no TD>}'"
      BAD_KNOWN+=("$msg: the third field must be TD#<n> or TD#?")
      continue
    fi
    KNOWN_TD["$kdir $ktgt"]=$ktd
  done < "$KNOWN_FILE"
fi

# Defined targets of one Makefile, from make's database. Entries flagged
# "# Not a target:" (source files, implicit lookups) and special targets
# beginning with '.' are dropped.
defined_targets() {
  make -pRrq -C "$1" : 2>/dev/null | awk '
    /^# Files/                      { f = 1 }
    /^# Finished Make data base/    { f = 0 }
    f && /^# Not a target:/         { skip = 1; next }
    f && /^[^#\t .=][^=]*:([^=]|$)/ {
      if (!skip) { split($0, a, ":"); print a[1] }
    }
    { skip = 0 }' | sort -u
}

# Best-effort check counts from a sim log: prints "pass/fail" or "-".
# Testbenches print one of several summary formats; the last match wins.
check_counts() {
  local log=$1 m p f
  m=$(grep -oP 'PASS=\d+\s+FAIL=\d+' "$log" | tail -1)
  if [ -n "$m" ]; then
    p=${m#PASS=}; p=${p%%[!0-9]*}; f=${m##*FAIL=}; echo "$p/$f"; return
  fi
  m=$(grep -oP '\d+ PASS,?\s+\d+ FAIL' "$log" | tail -1)
  if [ -n "$m" ]; then
    read -r p _ f _ <<< "${m//,/}"; echo "$p/$f"; return
  fi
  m=$(grep -oP 'PASS: \d+\s+FAIL: \d+' "$log" | tail -1)
  if [ -n "$m" ]; then
    read -r _ p _ f <<< "$m"; echo "$p/$f"; return
  fi
  m=$(grep -oP '\d+ passed, \d+ failed' "$log" | tail -1)
  if [ -n "$m" ]; then
    read -r p _ f _ <<< "${m//,/}"; echo "$p/$f"; return
  fi
  m=$(grep -oP '\d+/\d+ PASSED' "$log" | tail -1)
  if [ -n "$m" ]; then
    p=${m%%/*}; f=${m#*/}; f=${f%% *}; echo "$p/$((f - p))"; return
  fi
  m=$(grep -oP '\d+ checks passed' "$log" | tail -1)
  if [ -n "$m" ]; then echo "${m%% *}/0"; return; fi
  m=$(grep -oP 'RESULTS: \d+ error\(s\)' "$log" | tail -1)
  if [ -n "$m" ]; then m=${m#RESULTS: }; echo "-/${m%% *}"; return; fi
  # BP-132 (TD#130): three testbenches print no total of their own.
  # tb_bp_history (sim_history, cov_history) prints three counts of
  # passed checks and stops at the first failure ($fatal), so the
  # total is their sum with no failure count.
  local hist_re='^BP-07[23]: \d+ (directed test cases|golden fold '
  hist_re+='comparisons|external anchor checks) passed'
  m=$(grep -oP "$hist_re" "$log" | grep -oP ': \d+' | tr -d ': ')
  if [ -n "$m" ]; then
    p=0; for x in $m; do p=$((p + x)); done; echo "$p/0"; return
  fi
  # tb_tage (sim_tage, sim_tage_fast, cov_tage) prints one result per
  # test, "[PASS] <name>_tst: 0 failures" or "[FAIL] <name>_tst: <n>
  # failures": the figure is tests passed / tests failed.
  p=$(grep -cP '^\[PASS\] \w+_tst: 0 failures' "$log")
  f=$(grep -cP '^\[FAIL\] \w+_tst: \d+ failures' "$log")
  if [ $((p + f)) -gt 0 ]; then echo "$p/$f"; return; fi
  # tb_tage_tasks prints one result per test, "<name>: PASS" through
  # its tb_info, "<name>: FAIL" through its tb_error.
  p=$(grep -cP '^\[INFO\]\s+t=\d+ \w+: PASS$' "$log")
  f=$(grep -cP '^\[ERROR\]\s+t=\d+ \w+: FAIL$' "$log")
  if [ $((p + f)) -gt 0 ]; then echo "$p/$f"; return; fi
  echo "-"
}

# Check counts of a log that holds several cov_* sub-runs (cov_bpu runs
# five as prerequisites and then merges them). Each sub-run starts at a
# "[compiling]  cov tb_<name>" line. Prints "<sum> <name>=<p/f> ..." or
# nothing when the log has fewer than two sub-runs. A sub-run with no
# count adds nothing to the sum and is listed as "-".
sub_counts() {
  local log=$1 dir n i nm c p f sp=0 sf=0 subs=""
  [ "$(grep -c '^\[compiling\]  cov ' "$log")" -ge 2 ] || return 0
  dir=$(mktemp -d "${TMPDIR:-/tmp}/regress_sub.XXXXXX")
  awk -v d="$dir" '/^\[compiling\]  cov /{n++; print $NF > (d "/name." n)}
    n {print > (d "/part." n)}' "$log"
  n=$(ls "$dir"/part.* | wc -l)
  for ((i = 1; i <= n; i++)); do
    nm=$(cat "$dir/name.$i")
    c=$(check_counts "$dir/part.$i")
    subs+=" ${nm#tb_}=$c"
    if [ "$c" != "-" ]; then
      p=${c%/*}; f=${c#*/}
      [ "$p" != "-" ] && sp=$((sp + p))
      sf=$((sf + f))
    fi
  done
  rm -rf "$dir"
  echo "$sp/$sf$subs"
}

mapfile -t MAKEFILES < <(find "$ROOT/rtl" \
  \( -name Makefile -o -name makefile -o -name GNUmakefile \) \
  -type f | sort)

echo "regress: root $ROOT"
echo "regress: ${#MAKEFILES[@]} Makefile(s) found"
for mf in "${MAKEFILES[@]}"; do echo "  ${mf#$ROOT/}"; done
echo

SUMMARY=()      # printed lines
FAIL_NEW=()     # failing, not listed
FAIL_KNOWN=()   # failing, listed
NOW_PASSES=()   # listed, passing
SET_ERRORS=()   # regression-set errors
N_RUN=0
T_ALL0=$(date +%s)

for mf in "${MAKEFILES[@]}"; do
  dir=$(dirname "$mf")
  rel=${dir#$ROOT/}
  tag=${rel//\//_}
  T_MF0=$(date +%s)
  SUMMARY+=("== $rel")

  mapfile -t defined < <(defined_targets "$dir")
  list_out=$(make -s --no-print-directory -C "$dir" regress_list 2>&1)
  if [ $? -ne 0 ]; then
    SET_ERRORS+=("$rel: no regress_list target (regression plumbing missing)")
    SUMMARY+=("  REGRESS-SET ERROR  no regress_list target")
    SUMMARY+=("  time $(( $(date +%s) - T_MF0 ))s")
    continue
  fi
  read -r -a tests   <<< "$(sed -n 's/^test://p'    <<< "$list_out")"
  read -r -a exclude <<< "$(sed -n 's/^exclude://p' <<< "$list_out")"

  declare -A IN_T=() IN_X=() IS_DEF=()
  for t in "${tests[@]}";   do IN_T[$t]=1; done
  for t in "${exclude[@]}"; do IN_X[$t]=1; done
  for t in "${defined[@]}"; do IS_DEF[$t]=1; done

  for t in "${defined[@]}"; do
    if [ -z "${IN_T[$t]:-}" ] && [ -z "${IN_X[$t]:-}" ]; then
      msg="$rel: target '$t' is in neither REGRESS_TARGETS"
      SET_ERRORS+=("$msg nor REGRESS_EXCLUDE")
      SUMMARY+=("  REGRESS-SET ERROR  $t: defined, not in the regression set")
    fi
  done
  for t in "${tests[@]}" "${exclude[@]}"; do
    if [ -z "${IS_DEF[$t]:-}" ]; then
      SET_ERRORS+=("$rel: '$t' is listed but not defined")
      SUMMARY+=("  REGRESS-SET ERROR  $t: listed but not defined")
    fi
  done
  for t in "${tests[@]}"; do
    if [ -n "${IN_X[$t]:-}" ]; then
      msg="$rel: '$t' is in both REGRESS_TARGETS"
      SET_ERRORS+=("$msg and REGRESS_EXCLUDE")
      SUMMARY+=("  REGRESS-SET ERROR  $t: in both lists")
    fi
  done
  unset IN_T IN_X IS_DEF

  for t in "${tests[@]}"; do
    log=$LOG_DIR/$tag.$t.log
    echo "[regress] $rel $t"
    T0=$(date +%s)
    make -B -C "$dir" "$t" > "$log" 2>&1
    rc=$?
    secs=$(( $(date +%s) - T0 ))
    warns=$(grep -c '^%Warning' "$log")
    errs=$(grep -c '^%Error' "$log")
    checks=$(check_counts "$log")
    subs=$(sub_counts "$log")
    if [ -n "$subs" ]; then
      checks=${subs%% *}
      subs=${subs#* }
    fi
    N_RUN=$((N_RUN + 1))

    key="$rel $t"
    if [ $rc -eq 0 ] && [ "$warns" -eq 0 ]; then
      if [ -n "${KNOWN_TD[$key]:-}" ]; then
        result="NOW-PASSES"
        NOW_PASSES+=("$key ${KNOWN_TD[$key]}: known failure now passes")
      else
        result="PASS"
      fi
    else
      if [ -n "${KNOWN_TD[$key]:-}" ]; then
        result="KNOWN-FAIL"
        FAIL_KNOWN+=("$key ${KNOWN_TD[$key]}")
      else
        result="FAIL"
        FAIL_NEW+=("$key (exit $rc, $warns warning(s)) log $log")
      fi
    fi
    [ -n "${KNOWN_TD[$key]:-}" ] && KNOWN_SEEN[$key]=1
    SUMMARY+=("$(printf '  %-10s %-22s rc=%-3s warn=%-2s err=%-2s %-11s %4ss' \
      "$result" "$t" "$rc" "$warns" "$errs" "$checks" "$secs")")
    [ -n "$subs" ] && SUMMARY+=("             sum of sub-runs:$subs")
  done
  SUMMARY+=("  time $(( $(date +%s) - T_MF0 ))s")
done

# A listed entry whose target was never run is stale as well.
STALE_KNOWN=()
for key in "${!KNOWN_TD[@]}"; do
  [ -z "${KNOWN_SEEN[$key]:-}" ] && \
    STALE_KNOWN+=("$key ${KNOWN_TD[$key]}: listed but no such target was run")
done

T_ALL=$(( $(date +%s) - T_ALL0 ))

echo
echo "=================================================================="
echo "REGRESSION SUMMARY  git $GIT_SHA ($GIT_STATE)"
echo "root $ROOT"
echo "=================================================================="
for line in "${SUMMARY[@]}"; do echo "$line"; done
echo "------------------------------------------------------------------"
echo "targets run: $N_RUN   total time: ${T_ALL}s"
echo "new failures: ${#FAIL_NEW[@]}   known failures: ${#FAIL_KNOWN[@]}" \
     "  now passing: ${#NOW_PASSES[@]}   stale entries: ${#STALE_KNOWN[@]}" \
     "  malformed entries: ${#BAD_KNOWN[@]}   set errors: ${#SET_ERRORS[@]}"
for x in "${SET_ERRORS[@]}";  do echo "REGRESS-SET ERROR: $x"; done
for x in "${BAD_KNOWN[@]}";   do echo "MALFORMED KNOWN-FAILURE ENTRY: $x"; done
for x in "${FAIL_NEW[@]}";    do echo "FAIL: $x"; done
for x in "${FAIL_KNOWN[@]}";  do echo "known failure: $x"; done
for x in "${NOW_PASSES[@]}";  do echo "KNOWN FAILURE NOW PASSES: $x"; done
for x in "${STALE_KNOWN[@]}"; do echo "STALE KNOWN-FAILURE ENTRY: $x"; done
echo "logs: $LOG_DIR"

if [ ${#SET_ERRORS[@]} -ne 0 ] || [ ${#FAIL_NEW[@]} -ne 0 ] || \
   [ ${#NOW_PASSES[@]} -ne 0 ] || [ ${#STALE_KNOWN[@]} -ne 0 ] || \
   [ ${#BAD_KNOWN[@]} -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
