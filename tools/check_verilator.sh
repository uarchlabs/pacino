#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_verilator.sh [--build] -- report Verilator and its
# packages; with --build, build Verilator when it is missing or the wrong
# version.
#
# Verilator is the tools/verilator submodule (v5.048), installed to
# $RVA_ROOT/tools/bin. It is correct when verilator --version reports
# 5.048; the version is checked again after a build. The verilator on
# PATH is not checked; it may be another version.
#
# Packages: the [verilator] group of tools/apt-requirements.txt. Options,
# exit status, RVA_ROOT and JOBS: see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

SRC="$RVA_ROOT/tools/verilator"
VERILATOR_VERSION="5.048"

verify_verilator() {
  if [ ! -x "$BIN/verilator" ]; then
    echo "MISSING verilator at $BIN/verilator"
    return 1
  fi
  local version
  version=$("$BIN/verilator" --version 2>&1 || true)
  if [[ "$version" != "Verilator $VERILATOR_VERSION "* ]]; then
    echo "BROKEN  verilator: expected $VERILATOR_VERSION, got: $version"
    return 1
  fi
  echo "OK      verilator: $version at $BIN/verilator"
}

check_pkgs verilator
verify_verilator; tool_ok=$?
[ -z "$MISSING_PKGS" ] && [ "$tool_ok" = 0 ] && exit 0
[ -n "$MISSING_PKGS" ] && apt_hint
[ "$tool_ok" = 0 ] && exit 1
if [ "$BUILD" = 0 ]; then
  echo "Build Verilator with: $0 --build"
  exit 1
fi
if [ -n "$MISSING_PKGS" ]; then
  echo "NOT BUILT verilator: install the packages first"
  exit 1
fi

# --- Build --------------------------------------------------------------
(
  set -e
  [ -f "$SRC/configure.ac" ] || \
    git -C "$RVA_ROOT" submodule update --init tools/verilator
  # Verilator's configure must not see a VERILATOR_ROOT from the
  # environment
  unset VERILATOR_ROOT
  cd "$SRC"
  # The build is in-tree; clear what an earlier configure left
  [ -f Makefile ] && make distclean || true
  autoconf
  ./configure --prefix="$RVA_ROOT/tools"
  make -j"$JOBS"
  make install
) || { echo "FAILED  verilator build"; exit 1; }

verify_verilator
