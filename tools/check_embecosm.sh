#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_embecosm.sh [--build] -- check the Embecosm RISC-V
# toolchain, and locate or install it
#
# The toolchain is a prebuilt release, EMBECOSM_RELEASE, from Embecosm's
# RISC-V Embedded top-of-tree builds (GCC and Clang). It is too large for
# the repository. Its bin directory is EMBECOSM_BIN, read from rtl/Vars.mk
# (an EMBECOSM_BIN in the environment overrides it, as for make). The
# tools the project uses:
#   - clang, llvm-objdump     asm_dec_words (decode), oracle_ifu_rvc_exp
#                             (ifu)
#   - riscv64-unknown-elf-gcc, riscv64-unknown-elf-objdump
#                             tools/Makefile
# It is correct when each is executable and gcc and clang name
# EMBECOSM_RELEASE in their version.
#
# With --build, when the toolchain is not found and the script runs at a
# terminal, it asks for one of:
#   1) the bin directory of an existing install
#   2) a download (2.3 GB) and install into $RVA_ROOT/tools/ (7.1 GB
#      unpacked), no sudo
#   3) skip
# The chosen path is saved in tools/local.mk, which rtl/Vars.mk reads.
# Without a terminal, or without --build, it prints the commands for 1)
# and 2) and exits 1. An EMBECOSM_BIN in the environment is never
# replaced: when it is wrong the script says so and exits 1. RVA_ROOT:
# see tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

LOCAL_MK="$RVA_ROOT/tools/local.mk"
TOOLS="clang llvm-objdump riscv64-unknown-elf-gcc riscv64-unknown-elf-objdump"

# A variable as rtl/Vars.mk sets it
vars_mk() {
  make -s -f "$RVA_ROOT/rtl/Vars.mk" \
    --eval "_print_var: ; @echo \$($1)" _print_var
}
EMBECOSM_RELEASE=$(vars_mk EMBECOSM_RELEASE)
EMBECOSM_URL="https://buildbot.embecosm.com/job/riscv-embedded-ubuntu2204/76\
/artifact/$EMBECOSM_RELEASE.tar.gz"
EMBECOSM_GB=10    # free space the install needs: tarball plus unpacked
LOCAL_BIN="$RVA_ROOT/tools/$EMBECOSM_RELEASE/bin"

# Check the toolchain in bin directory $1; return 0 when it is correct
verify_embecosm() {
  local dir="$1" t version ok=1
  for t in $TOOLS; do
    if [ -x "$dir/$t" ]; then
      echo "OK      embecosm: $t"
    else
      echo "MISSING embecosm: $t in $dir"
      ok=0
    fi
  done
  [ "$ok" = 1 ] || return 1
  for t in riscv64-unknown-elf-gcc clang; do
    version=$("$dir/$t" --version 2>&1 | head -1 || true)
    if [[ "$version" != *"$EMBECOSM_RELEASE"* ]]; then
      echo "BROKEN  embecosm: $t is not $EMBECOSM_RELEASE: $version"
      return 1
    fi
  done
  echo "OK      embecosm: $EMBECOSM_RELEASE at $dir"
}

# Save bin directory $1 in tools/local.mk; ?= keeps the environment first
save_path() {
  printf '%s\n' \
    "# Written by tools/check_embecosm.sh; read by rtl/Vars.mk." \
    "EMBECOSM_BIN ?= $1" > "$LOCAL_MK"
  echo "Saved EMBECOSM_BIN=$1 in $LOCAL_MK"
}

# Download and unpack into tools/. The unpack goes to a temporary
# directory that is renamed when complete, so an interrupted install
# leaves no partial toolchain at the final path.
install_local() {
  local tarball="$RVA_ROOT/tools/$EMBECOSM_RELEASE.tar.gz"
  local tmp="$RVA_ROOT/tools/.$EMBECOSM_RELEASE.tmp"
  local free_gb
  free_gb=$(df -P -BG "$RVA_ROOT/tools" | awk 'NR == 2 { print $4 + 0 }')
  if [ "$free_gb" -lt "$EMBECOSM_GB" ]; then
    echo "NOT INSTALLED embecosm: ${free_gb} GB free in $RVA_ROOT/tools;"
    echo "  the install needs about $EMBECOSM_GB GB."
    return 1
  fi
  # -C - resumes an interrupted download, so a partial tarball is kept
  if ! curl -fL -C - -o "$tarball" "$EMBECOSM_URL"; then
    echo "NOT INSTALLED embecosm: the download failed; run again to resume"
    return 1
  fi
  # One && chain: set -e is ignored in a subshell tested by || or if.
  # A tarball that does not unpack is removed so the next run downloads
  # it again.
  rm -rf "$tmp" "$RVA_ROOT/tools/$EMBECOSM_RELEASE" &&
    mkdir -p "$tmp" &&
    echo "Unpacking $tarball" &&
    tar -xzf "$tarball" -C "$tmp" &&
    mv "$tmp/$EMBECOSM_RELEASE" "$RVA_ROOT/tools/$EMBECOSM_RELEASE" &&
    rmdir "$tmp"
  if [ $? -ne 0 ]; then
    echo "NOT INSTALLED embecosm: the unpack failed"
    rm -rf "$tmp" "$tarball"
    return 1
  fi
  rm -f "$tarball"
  verify_embecosm "$LOCAL_BIN" && save_path "$LOCAL_BIN"
}

print_options() {
  echo "Choose one:"
  echo "  - an existing install: tools/check_embecosm.sh --build at a"
  echo "    terminal, or write its bin directory to tools/local.mk:"
  echo "      echo 'EMBECOSM_BIN ?= <path>/bin' > tools/local.mk"
  echo "  - install into tools/ (no sudo): tools/check_embecosm.sh --build"
  echo "    at a terminal, or by hand:"
  echo "      curl -LO $EMBECOSM_URL"
  echo "      tar -xzf $EMBECOSM_RELEASE.tar.gz -C tools"
}

EXT=$(vars_mk EMBECOSM_BIN)
verify_embecosm "$EXT" && exit 0

if [ -n "${EMBECOSM_BIN:-}" ]; then
  echo "EMBECOSM_BIN=$EMBECOSM_BIN is set in the environment and is not"
  echo "the toolchain. Correct it or unset it."
  exit 1
fi
if [ "$BUILD" = 0 ] || [ ! -t 0 ]; then
  print_options
  exit 1
fi

echo
echo "Embecosm toolchain $EMBECOSM_RELEASE not found."
while true; do
  echo "  1) enter the bin directory of an existing install"
  echo "  2) download (2.3 GB) and install into $RVA_ROOT/tools/"
  echo "  3) skip"
  read -r -p "Choice [1-3]: " choice || exit 1
  case "$choice" in
    1)
      read -r -p "bin directory: " dir || exit 1
      dir="${dir/#\~/$HOME}"
      dir="${dir%/}"
      if verify_embecosm "$dir"; then
        save_path "$dir"
        exit 0
      fi
      echo "That is not $EMBECOSM_RELEASE; try again."
      ;;
    2)
      install_local
      exit $?
      ;;
    3)
      echo "Skipped."
      exit 1
      ;;
    *)
      echo "Enter 1, 2 or 3."
      ;;
  esac
done
