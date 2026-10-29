#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/regress.sh [-j N] [ROOT] -- run every test target in every rtl/
# Makefile
#
# ROOT defaults to the repo root (the parent of this script's directory).
# Pass a path to run against a scratch copy of the tree.
#
# Jobs: the targets of one Makefile run one after another in one job, so
# targets that share an object directory never run together; Makefiles
# run in parallel, at most N at once. Measured on 2026-10-28, no target
# writes a file under another Makefile's directory. N is, in order:
#   -j N            on the command line
#   REGRESS_JOBS=N  in the environment (the pre-push hook passes no
#                   arguments, so this is how to set it for a push)
#   the default     half the CPU threads, at most one job per 2 GB of
#                   memory, at least 1
# -j 1 runs every target in turn, as before. Each make runs under
# nice -n 10, and ionice -c 3 when available, so other work on the
# machine comes first; REGRESS_NICE=0 turns that off.
#
# For each Makefile found under ROOT/rtl:
#   - read its defined targets from make's rule database (make -pRrq)
#   - read its regression set from `make regress_list`, which prints
#     REGRESS_TARGETS (run) and REGRESS_EXCLUDE (never run)
#   - fail if any defined target is in neither list, if a listed name is
#     not defined, or if a name is in both lists. A target added to a
#     Makefile cannot be left out of the regression without this failing.
#   - run each REGRESS_TARGETS entry with its own `make -B -C <dir> <t>`,
#     continuing past failures. The summary lists Makefiles and targets in
#     path order, whatever order they finished in.
#
# A target FAILS when make exits non-zero or its log holds any Verilator
# %Warning line. Failures are compared with ROOT/tools/known_failures.txt
# (missing file = empty). Line format:
#   <makefile dir> <target> TD#<n> <description>
# with # comments and blank lines ignored. The third field must be
# TD#<n> or TD#? (BP-132, TD#130); a line without one, or with fewer
# than three fields, is reported as malformed and waives nothing.
#
# Progress: as each target finishes, one line shows the count done of
# the total, the time since the start (NNmNNs), the target's result,
# Makefile directory name, name and time, and an estimate of the time
# left:
#   [137/274]  4m12s PASS bpu cov_tage 38s | left ~5m10s
# The result there is make's exit and the log's %Warning lines only; the
# summary applies tools/known_failures.txt. The estimate comes from each
# target's time in earlier runs, kept in .git/regress_times (outside the
# tracked tree, so the pass record is unaffected): for each unfinished
# Makefile, the times of its targets not yet done, less the time the
# current one has run, and the largest of those; with fewer jobs than
# unfinished Makefiles, at least their sum shared over the jobs.
# A target with no earlier time counts at the mean of the known ones;
# with no history at all the estimate is shown as "left ?".
#
# Exit 0 only when every failing target is listed there, every listed
# target still fails, no listed line is malformed, and no Makefile has
# a regression-set error.
# Logs are kept in a temp directory whose path is printed at the end.
#
# Pass record: a passing run writes the full HEAD sha to
# .git/regress_pass, which tools/hooks/pre-push checks. It is written only
# when the run tested exactly that commit: at both the start and the end
# of the run, no tracked file differs from HEAD (changes inside submodule
# work trees, such as build output, are ignored) and rtl/ holds no
# untracked file. A failing run removes the record.

set -u

usage() {
  echo "usage: tools/regress.sh [-j N] [ROOT]" >&2
  exit 2
}

# -- jobs: -j N, then REGRESS_JOBS, then the default
JOBS_ARG=""
if [ "${1:-}" = "-j" ]; then
  JOBS_ARG=${2:-}
  shift 2 || usage
elif [[ "${1:-}" == -j* ]]; then
  JOBS_ARG=${1#-j}
  shift
fi
N_THREADS=$(nproc)
MEM_GB=$(awk '/^MemTotal:/ { print int($2 / 1048576) }' /proc/meminfo)
if [ -n "$JOBS_ARG" ]; then
  N_JOBS=$JOBS_ARG
  JOBS_FROM="-j"
elif [ -n "${REGRESS_JOBS:-}" ]; then
  N_JOBS=$REGRESS_JOBS
  JOBS_FROM="REGRESS_JOBS"
else
  N_JOBS=$(( N_THREADS / 2 ))
  [ "$N_JOBS" -gt $(( MEM_GB / 2 )) ] && N_JOBS=$(( MEM_GB / 2 ))
  [ "$N_JOBS" -lt 1 ] && N_JOBS=1
  JOBS_FROM="default: $N_THREADS threads / 2, $MEM_GB GB / 2"
fi
if ! [[ "$N_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "regress: jobs must be a positive integer, got '$N_JOBS'" >&2
  usage
fi

# -- priority: nice, and ionice when present, unless REGRESS_NICE=0
NICE=()
NICE_STATE=off
if [ "${REGRESS_NICE:-1}" != 0 ]; then
  NICE=(nice -n 10)
  NICE_STATE="nice -n 10"
  if command -v ionice > /dev/null 2>&1 && ionice -c 3 true 2>/dev/null
  then
    NICE+=(ionice -c 3)
    NICE_STATE+=", ionice -c 3"
  fi
fi

[ $# -le 1 ] || usage
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

# -- pass record. Prints the full HEAD sha when the tree is exactly that
# commit as far as the regression can see; prints nothing otherwise.
tested_commit() {
  git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1 || return 0
  git -C "$ROOT" diff --quiet --ignore-submodules=dirty HEAD 2>/dev/null \
    || return 0
  [ -z "$(git -C "$ROOT" status --porcelain -- rtl 2>/dev/null)" ] \
    || return 0
  git -C "$ROOT" rev-parse HEAD 2>/dev/null
}
PASS_SHA0=$(tested_commit)

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

# -- earlier target times, "<makefile dir> <target> <seconds>" per line
TIMES_FILE=""
if git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  TIMES_FILE=$(cd "$ROOT" && realpath -m "$(git rev-parse --git-path \
    regress_times)")
fi
declare -A EXP=()
EXP_SUM=0; EXP_N=0
if [ -n "$TIMES_FILE" ] && [ -f "$TIMES_FILE" ]; then
  while read -r edir etgt esec; do
    [[ "$esec" =~ ^[0-9]+$ ]] || continue
    EXP["$edir $etgt"]=$esec
    EXP_SUM=$((EXP_SUM + esec)); EXP_N=$((EXP_N + 1))
  done < "$TIMES_FILE"
fi
EXP_MEAN=""
[ "$EXP_N" -gt 0 ] && EXP_MEAN=$(( (EXP_SUM + EXP_N / 2) / EXP_N ))

SUMMARY=()      # printed lines
FAIL_NEW=()     # failing, not listed
FAIL_KNOWN=()   # failing, listed
NOW_PASSES=()   # listed, passing
SET_ERRORS=()   # regression-set errors
N_RUN=0
T_ALL0=$(date +%s)

# -- 1. regression-set checks, one Makefile at a time (fast). Per Makefile
# i: MF_REL, MF_TAG, MF_DIR, MF_TESTS (space separated) and MF_HEAD (its
# summary lines before the targets, newline separated).
MF_REL=(); MF_TAG=(); MF_DIR=(); MF_TESTS=(); MF_HEAD=()
for mf in "${MAKEFILES[@]}"; do
  dir=$(dirname "$mf")
  rel=${dir#$ROOT/}
  head=""

  mapfile -t defined < <(defined_targets "$dir")
  list_out=$(make -s --no-print-directory -C "$dir" regress_list 2>&1)
  if [ $? -ne 0 ]; then
    SET_ERRORS+=("$rel: no regress_list target (regression plumbing missing)")
    head+="  REGRESS-SET ERROR  no regress_list target"$'\n'
    tests=()
  else
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
        head+="  REGRESS-SET ERROR  $t: defined, not in the regression set"$'\n'
      fi
    done
    for t in "${tests[@]}" "${exclude[@]}"; do
      if [ -z "${IS_DEF[$t]:-}" ]; then
        SET_ERRORS+=("$rel: '$t' is listed but not defined")
        head+="  REGRESS-SET ERROR  $t: listed but not defined"$'\n'
      fi
    done
    for t in "${tests[@]}"; do
      if [ -n "${IN_X[$t]:-}" ]; then
        msg="$rel: '$t' is in both REGRESS_TARGETS"
        SET_ERRORS+=("$msg and REGRESS_EXCLUDE")
        head+="  REGRESS-SET ERROR  $t: in both lists"$'\n'
      fi
    done
    unset IN_T IN_X IS_DEF
  fi
  MF_REL+=("$rel"); MF_TAG+=("${rel//\//_}"); MF_DIR+=("$dir")
  MF_TESTS+=("${tests[*]}"); MF_HEAD+=("$head")
done

# -- 2. run. One job per Makefile runs its targets in turn and writes, per
# target, "<rc> <seconds>" to <tag>.<target>.res and its total time to
# <tag>.time; <tag>.cur holds "<target> <start>" of the target running.
# Jobs with the most targets start first, so the longest run is not left
# until last.
N_TOTAL=0
for i in "${!MF_TESTS[@]}"; do
  set -- ${MF_TESTS[$i]}; N_TOTAL=$((N_TOTAL + $#))
done
set --

# 125 -> 2m5s
dur() {
  local s=$1
  if [ "$s" -ge 60 ]; then echo "$((s / 60))m$((s % 60))s"
  else echo "${s}s"; fi
}

# 125 -> " 2m05s": the elapsed column, six wide up to 99m59s
stamp() {
  printf '%2dm%02ds' $(($1 / 60)) $(($1 % 60))
}

# One progress line, after target $2 of Makefile $1 finished with rc $3
# in $4 seconds. Reads only the files the jobs write in LOG_DIR, so it is
# safe to call from any job; the line is printed with one printf.
progress() {
  local i=$1 t=$2 rc=$3 secs=$4 now ndone res j left mf_left n nd
  local tt start ran e unknown=0 total=0 n_mf=0
  now=$(date +%s)
  ndone=$(find "$LOG_DIR" -maxdepth 1 -name '*.res' | wc -l)
  if [ "$rc" -eq 0 ] && ! grep -q '^%Warning' \
       "$LOG_DIR/${MF_TAG[$i]}.$t.log"; then
    res=PASS
  else
    res=FAIL
  fi
  left=0
  for j in "${!MF_TESTS[@]}"; do
    [ -n "${MF_TESTS[$j]}" ] || continue
    [ -f "$LOG_DIR/${MF_TAG[$j]}.time" ] && continue
    n=0; nd=0; mf_left=0
    for tt in ${MF_TESTS[$j]}; do
      n=$((n + 1))
      if [ -f "$LOG_DIR/${MF_TAG[$j]}.$tt.res" ]; then
        nd=$((nd + 1)); continue
      fi
      e=${EXP["${MF_REL[$j]} $tt"]:-$EXP_MEAN}
      if [ -z "$e" ]; then unknown=1; continue; fi
      mf_left=$((mf_left + e))
    done
    [ "$nd" -eq "$n" ] && continue
    if [ -f "$LOG_DIR/${MF_TAG[$j]}.cur" ]; then
      read -r _ start < "$LOG_DIR/${MF_TAG[$j]}.cur"
      ran=$((now - start))
      mf_left=$((mf_left - ran)); [ "$mf_left" -lt 0 ] && mf_left=0
    fi
    [ "$mf_left" -gt "$left" ] && left=$mf_left
    total=$((total + mf_left)); n_mf=$((n_mf + 1))
  done
  # With fewer jobs than unfinished Makefiles, the work left shared over
  # the jobs can exceed the longest Makefile.
  [ "$n_mf" -gt "$N_JOBS" ] && [ $((total / N_JOBS)) -gt "$left" ] && \
    left=$((total / N_JOBS))
  if [ "$unknown" -eq 1 ]; then left="?"; else left="~$(dur "$left")"; fi
  printf '[%d/%d] %s %s %s %s %s | left %s\n' "$ndone" "$N_TOTAL" \
    "$(stamp $((now - T_ALL0)))" "$res" "${MF_REL[$i]##*/}" "$t" \
    "$(dur "$secs")" "$left"
}

run_makefile() {
  local i=$1 t rc T0 T_MF0 secs
  T_MF0=$(date +%s)
  for t in ${MF_TESTS[$i]}; do
    T0=$(date +%s)
    echo "$t $T0" > "$LOG_DIR/${MF_TAG[$i]}.cur"
    "${NICE[@]}" make -B -C "${MF_DIR[$i]}" "$t" \
      > "$LOG_DIR/${MF_TAG[$i]}.$t.log" 2>&1
    rc=$?
    secs=$(( $(date +%s) - T0 ))
    rm -f "$LOG_DIR/${MF_TAG[$i]}.cur"
    echo "$rc $secs" > "$LOG_DIR/${MF_TAG[$i]}.$t.res"
    progress "$i" "$t" "$rc" "$secs"
  done
  echo $(( $(date +%s) - T_MF0 )) > "$LOG_DIR/${MF_TAG[$i]}.time"
}

echo "regress: $N_JOBS job(s) at once ($JOBS_FROM); priority: $NICE_STATE"
mapfile -t ORDER < <(for i in "${!MF_TESTS[@]}"; do
  set -- ${MF_TESTS[$i]}; echo "$# $i"; done | sort -k1,1nr | cut -d' ' -f2)
for i in "${ORDER[@]}"; do
  [ -n "${MF_TESTS[$i]}" ] || continue
  while [ "$(jobs -rp | wc -l)" -ge "$N_JOBS" ]; do wait -n; done
  run_makefile "$i" &
done
wait

# -- 3. results, in path order
for i in "${!MF_REL[@]}"; do
  rel=${MF_REL[$i]}
  SUMMARY+=("== $rel")
  while IFS= read -r line; do
    [ -n "$line" ] && SUMMARY+=("$line")
  done <<< "${MF_HEAD[$i]}"
  for t in ${MF_TESTS[$i]}; do
    log=$LOG_DIR/${MF_TAG[$i]}.$t.log
    read -r rc secs < "$LOG_DIR/${MF_TAG[$i]}.$t.res"
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
  mf_time=0
  [ -f "$LOG_DIR/${MF_TAG[$i]}.time" ] && \
    mf_time=$(cat "$LOG_DIR/${MF_TAG[$i]}.time")
  SUMMARY+=("  time ${mf_time}s")
done

# A listed entry whose target was never run is stale as well.
STALE_KNOWN=()
for key in "${!KNOWN_TD[@]}"; do
  [ -z "${KNOWN_SEEN[$key]:-}" ] && \
    STALE_KNOWN+=("$key ${KNOWN_TD[$key]}: listed but no such target was run")
done

T_ALL=$(( $(date +%s) - T_ALL0 ))

# Save this run's target times for the next run's estimate. Targets not
# run this time keep their earlier time.
if [ -n "$TIMES_FILE" ]; then
  for i in "${!MF_REL[@]}"; do
    for t in ${MF_TESTS[$i]}; do
      [ -f "$LOG_DIR/${MF_TAG[$i]}.$t.res" ] || continue
      read -r _ secs < "$LOG_DIR/${MF_TAG[$i]}.$t.res"
      EXP["${MF_REL[$i]} $t"]=$secs
    done
  done
  for key in "${!EXP[@]}"; do echo "$key ${EXP[$key]}"; done | sort \
    > "$TIMES_FILE.tmp" && mv "$TIMES_FILE.tmp" "$TIMES_FILE"
fi

echo
echo "=================================================================="
echo "REGRESSION SUMMARY  git $GIT_SHA ($GIT_STATE)"
echo "root $ROOT"
echo "jobs $N_JOBS ($JOBS_FROM); priority: $NICE_STATE"
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

PASS_FILE=""
if git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  PASS_FILE=$(cd "$ROOT" && realpath -m "$(git rev-parse --git-path \
    regress_pass)")
fi

if [ ${#SET_ERRORS[@]} -ne 0 ] || [ ${#FAIL_NEW[@]} -ne 0 ] || \
   [ ${#NOW_PASSES[@]} -ne 0 ] || [ ${#STALE_KNOWN[@]} -ne 0 ] || \
   [ ${#BAD_KNOWN[@]} -ne 0 ]; then
  [ -n "$PASS_FILE" ] && rm -f "$PASS_FILE"
  echo "RESULT: FAIL"
  exit 1
fi

# Record the pass only if the tree was the same clean commit throughout
PASS_SHA1=$(tested_commit)
if [ -n "$PASS_FILE" ] && [ -n "$PASS_SHA0" ] && \
   [ "$PASS_SHA0" = "$PASS_SHA1" ]; then
  echo "$PASS_SHA0" > "$PASS_FILE"
  echo "pass recorded for $PASS_SHA0 (push allowed)"
elif [ -n "$PASS_FILE" ]; then
  rm -f "$PASS_FILE"
  echo "pass NOT recorded: tracked changes or untracked rtl/ files, or" \
       "HEAD moved during the run (push will be refused)"
fi
echo "RESULT: PASS"
exit 0
