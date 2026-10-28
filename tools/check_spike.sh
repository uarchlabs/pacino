#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_spike.sh [--build] -- report Spike and its packages; with
# --build, build Spike when it is missing or the wrong version.
#
# Spike is the tools/spike submodule (riscv-isa-sim 1.1.1-dev), installed
# to $RVA_ROOT/tools/bin, the path rtl/Vars.mk (SPIKE) and
# tools/check_spike_decode.py expect. It is correct when spike reports
# the expected version and spike-dasm decodes a known instruction. The
# version is checked again after a build.
#
# Packages: the [spike] group of tools/apt-requirements.txt. Options,
# exit status, RVA_ROOT and JOBS: see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

SRC="$RVA_ROOT/tools/spike"
SPIKE_VERSION="1.1.1-dev"

verify_spike() {
  if [ ! -x "$BIN/spike" ] || [ ! -x "$BIN/spike-dasm" ]; then
    echo "MISSING spike at $BIN/spike"
    return 1
  fi
  local banner dasm
  # spike --help exits non-zero; only its first line matters
  banner=$("$BIN/spike" --help 2>&1 | head -1 || true)
  # DASM(0505) is c.addi a0, 1
  dasm=$(echo "DASM(0505)" | "$BIN/spike-dasm" --isa=rv64gc 2>&1 || true)
  if [[ "$banner" != *"$SPIKE_VERSION"* ]]; then
    echo "BROKEN  spike:  expected $SPIKE_VERSION, got: $banner"
    return 1
  fi
  if [[ "$dasm" != *"c.addi"*"a0"*"1"* ]]; then
    echo "BROKEN  spike-dasm: DASM(0505) decoded as: $dasm"
    return 1
  fi
  echo "OK      spike:  $banner at $BIN/spike"
}

check_pkgs spike
verify_spike; tool_ok=$?
[ -z "$MISSING_PKGS" ] && [ "$tool_ok" = 0 ] && exit 0
[ -n "$MISSING_PKGS" ] && apt_hint
[ "$tool_ok" = 0 ] && exit 1
if [ "$BUILD" = 0 ]; then
  build_hint "Build Spike"
  exit 1
fi
if [ -n "$MISSING_PKGS" ]; then
  echo "NOT BUILT spike: install the packages first"
  exit 1
fi

# --- Build --------------------------------------------------------------
# The subshell stands alone and $? is tested after: set -e is ignored in a
# subshell tested by || or if, so a failed step would not stop the build.
(
  set -e
  [ -f "$SRC/configure" ] || \
    git -C "$RVA_ROOT" submodule update --init tools/spike
  # A build directory from an earlier configure is not reused
  rm -rf "$SRC/build"
  mkdir "$SRC/build"
  cd "$SRC/build"
  ../configure --prefix="$RVA_ROOT/tools"
  make -j"$JOBS"
  make install
)
if [ $? -ne 0 ]; then
  echo "FAILED  spike build"
  exit 1
fi

verify_spike
