#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/regress_weekly.sh [-j N] [ROOT] -- run every weekly target of every
# rtl/ Makefile under every paging mode (BP-149)
#
# PROJECT_CORE.md, TRANSLATION MODES: tools/regress.sh runs the translated
# tests under Sv57 (Sv57x4 at the G-stage), the testbenches' default. This
# script runs the same tests under every mode, by hand. It gates nothing:
# it runs no hook, records no pass and has no waiver list.
#
# ROOT defaults to the repo root (the parent of this script's directory).
# Pass a path to run against a scratch copy of the tree.
#
# THE WEEKLY TARGETS. Each Makefile with targets that translate under the
# knob prints a third regress_list line, "weekly: <targets>" (regress.sh
# reads only the test: and exclude: lines). A Makefile without one has no
# weekly target. Each weekly target must also be in the Makefile's test:
# line, or the script reports a set error.
#
# THE RUN. For each weekly target t, for each mode m of sv39, sv48 and
# sv57, in turn:
#   make -B -C <dir> <t> PT_MODE=<m>
# A run FAILS when make exits non-zero or its log holds any Verilator
# %Warning line. The script continues past failures and exits non-zero if
# any run failed or there was a set error.
#
# Jobs, as regress.sh: the runs of one Makefile go one after another in
# one job, so runs that share an object directory never overlap; Makefiles
# run in parallel, at most N at once. N is, in order: -j N on the command
# line, REGRESS_JOBS=N in the environment, or half the CPU threads, at most
# one job per 2 GB of memory, at least 1. Each make runs under nice -n 10,
# and ionice -c 3 when available; REGRESS_NICE=0 turns that off.
#
# The summary has the form of regress.sh's: the git sha line, one line per
# Makefile, one line per target and mode, the totals and RESULT. Logs are
# kept in a temp directory whose path is printed at the end.

set -u

MODES=(sv39 sv48 sv57)

usage() {
  echo "usage: tools/regress_weekly.sh [-j N] [ROOT]" >&2
  exit 2
}

# -- jobs: -j N, then REGRESS_JOBS, then the default (as regress.sh)
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
  echo "regress_weekly: jobs must be a positive integer, got '$N_JOBS'" >&2
  usage
fi

# -- priority, as regress.sh
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
  echo "regress_weekly: no rtl/ directory under '$ROOT'" >&2
  exit 2
fi
ROOT=$(cd "$ROOT" && pwd)

# The Makefiles take VERILATOR from $(RVA_ROOT)/tools/bin. Point it at
# the tree under test.
export RVA_ROOT=$ROOT

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/regress_weekly.XXXXXX")

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

# Best-effort check counts from a log, as regress.sh's check_counts for
# the summary formats the weekly targets print: "pass/fail" or "-".
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
  echo "-"
}

mapfile -t MAKEFILES < <(find "$ROOT/rtl" \
  \( -name Makefile -o -name makefile -o -name GNUmakefile \) \
  -type f | sort)

echo "regress_weekly: root $ROOT"
echo "regress_weekly: ${#MAKEFILES[@]} Makefile(s) found; modes ${MODES[*]}"
echo

# -- 1. the weekly sets. Per Makefile i with a weekly line: MF_REL,
# MF_TAG, MF_DIR, MF_WEEKLY (space separated).
MF_REL=(); MF_TAG=(); MF_DIR=(); MF_WEEKLY=()
SET_ERRORS=()
for mf in "${MAKEFILES[@]}"; do
  dir=$(dirname "$mf")
  rel=${dir#$ROOT/}
  list_out=$(make -s --no-print-directory -C "$dir" regress_list 2>&1) \
    || continue
  read -r -a weekly <<< "$(sed -n 's/^weekly://p' <<< "$list_out")"
  [ ${#weekly[@]} -gt 0 ] || continue
  read -r -a tests <<< "$(sed -n 's/^test://p' <<< "$list_out")"
  declare -A IN_T=()
  for t in "${tests[@]}"; do IN_T[$t]=1; done
  for t in "${weekly[@]}"; do
    if [ -z "${IN_T[$t]:-}" ]; then
      SET_ERRORS+=("$rel: weekly target '$t' is not in REGRESS_TARGETS")
    fi
  done
  unset IN_T
  echo "  $rel: ${weekly[*]}"
  MF_REL+=("$rel"); MF_TAG+=("${rel//\//_}"); MF_DIR+=("$dir")
  MF_WEEKLY+=("${weekly[*]}")
done
echo

N_TOTAL=0
for i in "${!MF_WEEKLY[@]}"; do
  set -- ${MF_WEEKLY[$i]}; N_TOTAL=$((N_TOTAL + $# * ${#MODES[@]}))
done
set --

dur() {
  local s=$1
  if [ "$s" -ge 60 ]; then echo "$((s / 60))m$((s % 60))s"
  else echo "${s}s"; fi
}

T_ALL0=$(date +%s)

# -- 2. run. One job per Makefile runs its targets, each under every mode
# in turn, and writes "<rc> <seconds>" to <tag>.<target>.<mode>.res and
# its total time to <tag>.time.
run_makefile() {
  local i=$1 t m rc T0 T_MF0 secs res ndone log
  T_MF0=$(date +%s)
  for t in ${MF_WEEKLY[$i]}; do
    for m in "${MODES[@]}"; do
      T0=$(date +%s)
      log="$LOG_DIR/${MF_TAG[$i]}.$t.$m.log"
      "${NICE[@]}" make -B -C "${MF_DIR[$i]}" "$t" PT_MODE="$m" \
        > "$log" 2>&1
      rc=$?
      secs=$(( $(date +%s) - T0 ))
      echo "$rc $secs" > "$LOG_DIR/${MF_TAG[$i]}.$t.$m.res"
      if [ "$rc" -eq 0 ] && ! grep -q '^%Warning' "$log"; then
        res=PASS
      else
        res=FAIL
      fi
      ndone=$(find "$LOG_DIR" -maxdepth 1 -name '*.res' | wc -l)
      printf '[%d/%d] %s %s %s %s %s\n' "$ndone" "$N_TOTAL" \
        "$(dur $(( $(date +%s) - T_ALL0 )))" "$res" "${MF_REL[$i]##*/}" \
        "$t $m" "$(dur "$secs")"
    done
  done
  echo $(( $(date +%s) - T_MF0 )) > "$LOG_DIR/${MF_TAG[$i]}.time"
}

echo "regress_weekly: $N_JOBS job(s) at once ($JOBS_FROM); priority:" \
     "$NICE_STATE"
mapfile -t ORDER < <(for i in "${!MF_WEEKLY[@]}"; do
  set -- ${MF_WEEKLY[$i]}; echo "$# $i"; done | sort -k1,1nr | cut -d' ' -f2)
for i in "${ORDER[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$N_JOBS" ]; do wait -n; done
  run_makefile "$i" &
done
wait

# -- 3. results, in path order
SUMMARY=()
FAILS=()
N_RUN=0
FMT='  %-10s %-22s %-5s rc=%-3s warn=%-2s err=%-2s %-11s %4ss'
for i in "${!MF_REL[@]}"; do
  SUMMARY+=("== ${MF_REL[$i]}")
  for t in ${MF_WEEKLY[$i]}; do
    for m in "${MODES[@]}"; do
      log=$LOG_DIR/${MF_TAG[$i]}.$t.$m.log
      read -r rc secs < "$LOG_DIR/${MF_TAG[$i]}.$t.$m.res"
      warns=$(grep -c '^%Warning' "$log")
      errs=$(grep -c '^%Error' "$log")
      checks=$(check_counts "$log")
      N_RUN=$((N_RUN + 1))
      if [ "$rc" -eq 0 ] && [ "$warns" -eq 0 ]; then
        result=PASS
      else
        result=FAIL
        msg="${MF_REL[$i]} $t PT_MODE=$m (exit $rc, $warns warning(s))"
        FAILS+=("$msg log $log")
      fi
      SUMMARY+=("$(printf "$FMT" "$result" "$t" "$m" "$rc" "$warns" \
        "$errs" "$checks" "$secs")")
    done
  done
  mf_time=0
  [ -f "$LOG_DIR/${MF_TAG[$i]}.time" ] && \
    mf_time=$(cat "$LOG_DIR/${MF_TAG[$i]}.time")
  SUMMARY+=("  time ${mf_time}s")
done

T_ALL=$(( $(date +%s) - T_ALL0 ))

echo
echo "=================================================================="
echo "WEEKLY REGRESSION SUMMARY  git $GIT_SHA ($GIT_STATE)"
echo "root $ROOT"
echo "modes ${MODES[*]}"
echo "jobs $N_JOBS ($JOBS_FROM); priority: $NICE_STATE"
echo "=================================================================="
for line in "${SUMMARY[@]}"; do echo "$line"; done
echo "------------------------------------------------------------------"
echo "runs: $N_RUN   total time: ${T_ALL}s"
echo "failures: ${#FAILS[@]}   set errors: ${#SET_ERRORS[@]}"
for x in "${SET_ERRORS[@]}"; do echo "WEEKLY-SET ERROR: $x"; done
for x in "${FAILS[@]}";      do echo "FAIL: $x"; done
echo "logs: $LOG_DIR"

if [ ${#FAILS[@]} -ne 0 ] || [ ${#SET_ERRORS[@]} -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
