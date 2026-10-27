#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/build_tools.sh [--check] [TOOL...] -- check the project tools and
# build those missing or at the wrong version
#
# TOOL is any of verilator, spike, surfer, embecosm; default all four, in
# that order. Each runs tools/check_<TOOL>.sh --build, or without --build
# when --check is given (report only, nothing is built). Verilator, Spike
# and Surfer install to $RVA_ROOT/tools/bin. The Embecosm toolchain is a
# prebuilt release and is only checked; when it is missing the script
# prints the download and install commands.
#
# No system package is installed. Install them first with:
#   sudo apt install $(sed 's/#.*//' tools/apt-requirements.txt)
# A check script that finds one missing prints the command and does not
# build.
#
# Each tool is run even if an earlier one fails. Exit status is non-zero
# if any failed; the summary names them. RVA_ROOT and JOBS: see
# tools/check_lib.sh.
set -uo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
ALL_TOOLS="verilator spike surfer embecosm"

build_opt="--build"
if [ "${1:-}" = "--check" ]; then
  build_opt=""
  shift
fi

tools="${*:-$ALL_TOOLS}"
for t in $tools; do
  if [ ! -f "$TOOLS_DIR/check_$t.sh" ]; then
    echo "build_tools.sh: unknown tool '$t'; known: $ALL_TOOLS" >&2
    exit 2
  fi
done

failed=""
for t in $tools; do
  echo "=== $t"
  if ! bash "$TOOLS_DIR/check_$t.sh" $build_opt; then
    failed="$failed $t"
  fi
done

echo "=== summary"
for t in $tools; do
  case " $failed " in
    *" $t "*) echo "FAIL    $t" ;;
    *)        echo "OK      $t" ;;
  esac
done
[ -z "$failed" ]
