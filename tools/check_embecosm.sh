#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# tools/check_embecosm.sh [--build] -- report the Embecosm RISC-V
# toolchain
#
# The toolchain is a prebuilt release, EMBECOSM_RELEASE, from Embecosm's
# RISC-V Embedded top-of-tree builds (GCC and Clang). It is too large for
# the repository. Its bin directory is RVA_EXT_TOOLS, read from
# rtl/Vars.mk (an RVA_EXT_TOOLS in the environment overrides it, as for
# make). The tools the project uses:
#   - clang, llvm-objdump     asm_dec_words (decode), oracle_ifu_rvc_exp
#                             (ifu)
#   - riscv64-unknown-elf-gcc, riscv64-unknown-elf-objdump
#                             tools/Makefile
# It is correct when each is executable and gcc and clang name
# EMBECOSM_RELEASE in their version.
#
# Nothing is installed: the default location is under /usr/local and
# needs sudo. With or without --build, a missing or wrong toolchain
# prints the download and install commands and exits 1. RVA_ROOT: see
# tools/check_lib.sh.
set -uo pipefail
source "$(dirname "$0")/check_lib.sh" "$@"

EMBECOSM_RELEASE="riscv-embecosm-embedded-ubuntu2204-20250309"
EMBECOSM_URL="https://buildbot.embecosm.com/job/riscv-embedded-ubuntu2204/76\
/artifact/$EMBECOSM_RELEASE.tar.gz"
TOOLS="clang llvm-objdump riscv64-unknown-elf-gcc riscv64-unknown-elf-objdump"

EXT=$(make -s -f "$RVA_ROOT/rtl/Vars.mk" \
        --eval '_print_ext: ; @echo $(RVA_EXT_TOOLS)' _print_ext)

ok=1
for t in $TOOLS; do
  if [ -x "$EXT/$t" ]; then
    echo "OK      embecosm: $t"
  else
    echo "MISSING embecosm: $t in RVA_EXT_TOOLS=$EXT"
    ok=0
  fi
done

if [ "$ok" = 1 ]; then
  for t in riscv64-unknown-elf-gcc clang; do
    version=$("$EXT/$t" --version 2>&1 | head -1 || true)
    if [[ "$version" != *"$EMBECOSM_RELEASE"* ]]; then
      echo "BROKEN  embecosm: $t is not $EMBECOSM_RELEASE: $version"
      ok=0
    fi
  done
fi

if [ "$ok" = 1 ]; then
  echo "OK      embecosm: $EMBECOSM_RELEASE at $EXT"
  exit 0
fi

# The tarball (2.3 GB) unpacks to $EMBECOSM_RELEASE/
echo "Install the toolchain with:"
echo "  curl -LO $EMBECOSM_URL"
echo "  sudo tar -xzf $EMBECOSM_RELEASE.tar.gz -C /usr/local"
echo "or unpack it elsewhere and set RVA_EXT_TOOLS to its bin directory."
exit 1
