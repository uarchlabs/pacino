<!-- SPDX-License-Identifier: Apache-2.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                 -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com> -->
# New User Setup Decisions
```
 FILE:    new_user_decisions.md
 SOURCE:  interactive session, 2026-10-27, branch install_scripts
 STATUS:  DRAFT
 UPDATED: 2026-10-27
 CONTACT: Jeff Nye
```

Owns the NU-N registry.

How a new user gets from a clone to a passing regression and a push:
the tools the project needs, where each comes from, the scripts that
check and build them, and the git hook that runs the regression on a
push. Written for the PA, to scope a task that changes any of it. The
user-facing instructions are in README.md (Quick start); this document
records why.

---

## 1. Principles

NU-1   No Makefile or script finds a project tool on PATH. rtl/Vars.mk
       names every tool by full path, each with ?= so the environment or
       the make command line can override it. Scripts read a value from
       Vars.mk with
         make -s -f $RVA_ROOT/rtl/Vars.mk --eval '_print_var: ; \
           @echo $(NAME)' _print_var
       Base system programs (bash, make, gcc/g++, python3, perl, git)
       still come from PATH; Verilator itself runs g++ and make. Spike
       runs dtc from PATH, but only to simulate; the project runs only
       spike-dasm, which does not.
NU-2   Every tool is installed per clone under $RVA_ROOT/tools (bin, etc,
       share, lib, include), with no sudo. The one exception is the
       Embecosm toolchain, which may be a shared install (NU-14).
NU-3   The scripts never run sudo and never install a system package.
       When a package is missing they print the apt command and stop
       before building that tool (build_tools.sh also gathers them into
       one command, NU-10). Users are assumed to have sudo to run that
       command (decided 2026-10-27).
NU-4   Each tool is pinned to one version, and each check script tests
       the installed tool against that pin, before and after a build.
       A tool at the right version is not rebuilt.
NU-5   The setup is repeatable on another Ubuntu release because the
       versions come from the pins, not from the release's packages.
       This is why lcov and fst2vcd are built locally (NU-15, NU-16):
       Ubuntu 24.04 ships lcov 2.0, whose genhtml is stricter and can
       fail on data that 1.15 accepts.

---

## 2. Tool inventory

```
Tool               Pin              Vars.mk             Script
-----------------  ---------------  ------------------  ------------------
Verilator          5.048            VERILATOR           check_verilator.sh
verilator_coverage 5.048            VERILATOR_COVERAGE  check_verilator.sh
Spike, spike-dasm  1.1.1-dev        SPIKE               check_spike.sh
Surfer             v0.7.0           SURFER              check_surfer.sh
genhtml (lcov)     v1.15            GENHTML             check_lcov.sh
fst2vcd            GTKWave v3.3.104 FST2VCD             check_fst2vcd.sh
Embecosm GCC/Clang 20250309         EMBECOSM_BIN        check_embecosm.sh
```

Source and check, per tool:

- Verilator: submodule tools/verilator; configure --prefix tools.
  Correct when verilator and verilator_coverage --version both report
  5.048.
- Spike: submodule tools/spike (commit 20feb9c2); configure --prefix
  tools in tools/spike/build. Correct when the banner names 1.1.1-dev
  and spike-dasm decodes DASM(0505) as c.addi a0, 1.
- Surfer: gitlab.com/surfer-project/surfer at the tag, cloned into
  tools/surfer; cargo install --root tools --no-track --force --locked.
  Correct when every library resolves (ldd) and --version names the tag
  exactly ("git: v0.7.0)").
- lcov: github.com/linux-test-project/lcov at the tag, shallow clone in
  tools/lcov; make install PREFIX=tools. Perl only. Correct when genhtml
  --version reports 1.15 and tools/etc/lcovrc exists.
- fst2vcd: github.com/gtkwave/gtkwave at the tag, shallow clone in
  tools/gtkwave (NU-16).
- Embecosm: prebuilt release riscv-embecosm-embedded-ubuntu2204-20250309
  (GCC 15.0.1, Clang 21), buildbot.embecosm.com job
  riscv-embedded-ubuntu2204 build 76 (NU-14).

Users of each tool:

- VERILATOR: every unit Makefile under rtl/, examples/fe_demo.
- VERILATOR_COVERAGE, GENHTML: the bpu cov_* targets, which are in the
  regression.
- SPIKE (spike-dasm): decode oracle targets, tools/Makefile,
  tools/check_spike_decode.py.
- SURFER: examples/fe_demo make view, waves/chk_sucl.py,
  rtl/core/frontend/bpu/surf.sh.
- FST2VCD: examples/fe_demo/waves/fe_demo_sigs.py (and through it
  mk_sucl.py, chk_sucl.py). Not in the regression.
- EMBECOSM_BIN: asm_dec_words (decode, clang), oracle_ifu_rvc_exp (ifu,
  clang and llvm-objdump), tools/Makefile (riscv32-unknown-elf-gcc and
  -objdump, which build and read RV64 code; NU-14).

The regression (tools/regress.sh) needs Verilator, verilator_coverage,
spike-dasm, genhtml and the Embecosm toolchain. Surfer and fst2vcd are
not in it; a missing Surfer or fst2vcd does not block a push.

Prerequisites outside tools/:

- apt packages: tools/apt-requirements.txt, one group per check script
  (NU-6).
- Rust: rustup, per user, in ~/.cargo; needed to build Surfer only.
  Never installed by a script; check_surfer.sh prints the rustup
  command.
- Python packages: tools/requirements.txt (pip --user, or a virtual
  environment on Ubuntu 24.04 and later): mkdocs and its theme for the
  docs site, PyYAML, spacy and its English model for ticfinder. None is
  in the RTL flow or the regression.

---

## 3. Check and build scripts

NU-6   tools/apt-requirements.txt lists packages in groups headed
       "# [tool]". check_<tool>.sh checks its group with dpkg-query
       (${db:Status-Status} = installed; a removed package whose config
       files remain is not installed). Install all with
         sudo apt install $(sed 's/#.*//' tools/apt-requirements.txt)
       On 2026-10-27 the [other] group (leftovers of the former
       tools/prereqs.sh: riscv-gnu-toolchain build prerequisites, jq,
       zenity and others) and the lcov and gtkwave packages were removed
       from the list; nothing used them. Removing a line uninstalls
       nothing.
NU-7   tools/check_lib.sh is sourced by every check script. It sets
       RVA_ROOT from the script's own location (an RVA_ROOT in the
       environment naming another tree is overridden, with a warning, so
       a stale value cannot redirect a build), BIN, JOBS (nproc, capped
       at one job per 2 GB of memory, the most a Verilator compile job
       uses) and BUILD (--build).
NU-8   check_<tool>.sh with no option reports only and exits 1 when the
       tool or a package is missing. With --build it also builds or
       installs the tool, then checks it again.
NU-9   A build runs in a subshell with set -e that stands alone, with $?
       tested after it. set -e is ignored in a subshell tested by || or
       if, so the earlier form "( set -e ... ) || fail" ran every step
       after a failed one (found 2026-10-27; fixed in all scripts).
NU-10  tools/build_tools.sh [--check] [TOOL...] runs check_<tool>.sh for
       verilator, spike, surfer, lcov, fst2vcd and embecosm, in that
       order, continuing past a failure, then prints an OK/FAIL summary
       and exits non-zero if any failed. A check script's own apt
       command is easy to miss in a long run, so build_tools.sh exports
       PACINO_MISSING_PKGS, a temporary file to which check_pkgs
       (check_lib.sh) appends "<tool> <package>" for each package
       missing. After the summary it prints one sudo apt install command
       for all of them, without duplicates, and the tools that need them.
NU-11  Every build_tools.sh run is logged to
       $RVA_ROOT/logs/pacino_setup_YYYY-MM-DD_N.log, N the lowest number
       unused that day: a header (date, user, host, OS, git branch and
       commit, the command line), then all output as printed (tee). The
       last line printed names the log. logs/ is not tracked. A user
       reporting a setup problem sends this file.
NU-12  Source clones and build output in tools/ are not tracked
       (.gitignore): bin, include, lib, share, etc, surfer, lcov, gtkwave,
       local.mk, the Embecosm directory, tarball and temporary unpack
       directory.
NU-13  The cachegen and ticfinder submodules use https URLs, so a clone
       needs no GitHub SSH key.

---

## 4. Tool-specific decisions

NU-14  Embecosm toolchain.
       - The variable is EMBECOSM_BIN (it replaced RVA_EXT_TOOLS; the
         old name implied any external tool). EMBECOSM_RELEASE holds the
         release name, which is Embecosm's own.
       - rtl/Vars.mk reads tools/local.mk (-include, not tracked).
         Without it the default is $RVA_ROOT/tools/<release>/bin.
       - When the toolchain is not found, check_embecosm.sh --build at a
         terminal asks: 1) the bin directory of an existing install,
         checked and then saved; 2) download (2.3 GB) and install into
         tools/ (7.1 GB unpacked; about 10 GB free is checked first);
         3) skip. The answer is written to tools/local.mk as
         "EMBECOSM_BIN ?= <path>", so it is asked once per clone and the
         environment still wins.
       - The install unpacks into a temporary directory and renames it
         when complete. A failed download is kept and resumed (curl
         -C -); a tarball that does not unpack is deleted.
       - Without a terminal, or without --build, it prints the
         equivalent commands. An EMBECOSM_BIN set in the environment is
         never replaced; when it is wrong the script says so and stops.
       - Rejected: a default of /usr/local/<release> (not a standard
         location); searching PATH for the compiler (the toolchain need
         not be on PATH).
       - It is correct when clang, llvm-objdump, riscv32-unknown-elf-gcc
         and riscv32-unknown-elf-objdump are executable and gcc and
         clang name the release in --version.
       - The riscv32- tools are RV64 tools too. The release ships only
         riscv32- names; its gcc has RV64 multilibs and builds RV64 code
         with -march=rv64... -mabi=lp64d, as tools/Makefile does. The
         project uses the riscv32- names and adds no riscv64- links, so
         an existing install the user names (option 1) needs no change.
         Decided 2026-10-27, after the new-user test: the check had
         required riscv64- names, which existed only as links added by
         hand to one shared install, so a fresh download failed it.
         Output with the riscv32- names is byte-identical.
NU-15  lcov. v1.15, installed per clone. GENHTML passes --config-file
       tools/etc/lcovrc, so genhtml ignores ~/.lcovrc and /etc/lcovrc.
       Compared with the Ubuntu 22.04 package (whose genhtml reports
       1.14): the same coverage figures, HTML differing only in the
       version string and date.
NU-16  fst2vcd. Only fst2vcd is built, not GTKWave: fst2vcd.c and the
       FST library (fstapi.c, lz4.c, fastlz.c) compiled with gcc against
       zlib. GTKWave's configure needs GTK and is not run; a config.h
       with HAVE_GETOPT_H, HAVE_ALLOCA_H, HAVE_SETENV, HAVE_UNSETENV and
       PACKAGE_BUGREPORT is written instead. fst2vcd has no version
       option, so the build writes "gtkwave v3.3.104" to
       tools/share/fst2vcd/VERSION and the check compares it. Output is
       byte-identical to the Ubuntu 22.04 package's fst2vcd on two
       fe_demo FST files.
       - Rejected: replacing fst2vcd with the pywellen Python package (a
         larger change to fe_demo_sigs.py, to be checked against
         chk_sucl.py).
NU-17  Surfer is installed as tools/bin/surfer. rtl/core/frontend/bpu/
       surf.sh read tools/surfer/target/release/surfer; it now reads
       SURFER from Vars.mk.

---

## 5. Environment and push

NU-18  tools/setup.sh, sourced from the repo root in every terminal, sets
       RVA_ROOT (from pwd), CLAUDE_CODE_MAX_OUTPUT_TOKENS, and two git
       settings for the clone:
         core.hooksPath tools/hooks
         core.sshCommand "ssh -o ServerAliveInterval=30 \
           -o ServerAliveCountMax=10"
       A clone never inherits git config (a repository cannot set it for
       the user), so setup.sh sets it on every run; setting it again is
       harmless. Before this, core.hooksPath was documented only in the
       hook's header and a new clone ran no hook.
NU-19  tools/regress.sh records a pass. A passing run writes the HEAD
       sha to .git/regress_pass only when, at both the start and the end
       of the run, no tracked file differs from HEAD (submodule build
       output ignored), rtl/ has no untracked file, and HEAD is the same
       commit. Otherwise it prints "pass NOT recorded" and the reason. A
       failing run deletes the record.
NU-20  tools/hooks/pre-push runs the regression on every push, so a plain
       git push is the whole operation. A push of a commit with a
       recorded pass goes through at once; otherwise the hook runs
       ./tools/regress.sh (stdin from /dev/null; git's ref list is read
       first) and allows the push on a recorded pass. It refuses a push
       when the regression fails, when no pass was recorded, or when a
       commit pushed is not HEAD (the regression tests the working
       tree). A push that only deletes branches is not checked.
NU-21  Why the SSH keepalive. git opens the connection to the remote
       before it runs pre-push. Over SSH to GitHub the connection is
       idle while the hook runs, and GitHub drops it; the push then
       fails after the regression passes, with no output. This happened
       on 2026-10-27 (913 s regression, PASS, branch never reached
       GitHub). It is reported elsewhere, e.g. GitHub community
       discussion 31675 and several projects' issues. Keepalives are the
       common fix. One report saw resets under heavy load even with
       keepalives.
       - Rejected: running the regression only before the push and
         having the hook check the record (the regression must run on
         push); the hook pushing again itself on a new connection and
         cancelling the original (git prints "error: failed to push some
         refs", not acceptable); pushing over HTTPS.

---

## 6. Operations

New user (README.md Quick start):
  1. git clone --recurse-submodules https://github.com/uarchlabs/pacino
  2. sudo apt install $(sed 's/#.*//' tools/apt-requirements.txt)
  3. rustup; pip install --user -r tools/requirements.txt
  4. . tools/setup.sh                 (repo root, every terminal)
  5. tools/build_tools.sh             (answer the Embecosm prompt; on a
                                       missing package run the apt
                                       command it ends with, then again)
  6. ./tools/regress.sh
  7. git push                         (runs the regression unless step 6
                                       recorded a pass for HEAD)

Short path (README.md Quick start, decided 2026-10-27): steps 2 and 3
can be skipped. build_tools.sh finds what is missing and prints the
command to install it (NU-3, NU-10):
  1. git clone --recurse-submodules https://github.com/uarchlabs/pacino
  2. . tools/setup.sh
  3. tools/build_tools.sh             (run any sudo apt install or rustup
                                       command it prints, then again)
  4. ./tools/regress.sh
A tool whose packages are missing is not built; the others are. Rust is
needed only for Surfer, and the regression does not use Surfer. The
pip packages (tools/requirements.txt) are checked by no script and are
needed only for the docs site, tools/gen_doc_placeholders.py and
ticfinder; nothing under rtl/, examples/ or tools/regress.sh imports
them. A user who skips them is not told when they are later needed.

Adding a tool:
  - a pin and a [tool] group in tools/apt-requirements.txt for its build
    prerequisites
  - tools/check_<tool>.sh on the pattern of the others (NU-7 to NU-9)
  - the name in ALL_TOOLS in tools/build_tools.sh
  - a full-path variable in rtl/Vars.mk; every user reads it
  - .gitignore for its source clone and outputs
  - README.md (Build the tools table), tools/README.md, and this
    document's inventory

Changing a pin: the version constant in the check script (and the
release name in rtl/Vars.mk for Embecosm), README.md, this document.
Reports and outputs produced by the old version may differ.

Files:
  rtl/Vars.mk, tools/local.mk (not tracked), tools/setup.sh,
  tools/build_tools.sh, tools/check_lib.sh, tools/check_<tool>.sh,
  tools/apt-requirements.txt, tools/requirements.txt, tools/regress.sh,
  tools/hooks/pre-push, .gitignore, README.md, tools/README.md

---

## 7. Open items

NU-UN-1  planning/PROJECT_CORE.md still names RVA_EXT_TOOLS; it should
         say EMBECOSM_BIN (NU-14). docs/sessions.json and a blog post
         also mention the old name, as history.
NU-UN-2  The SSH keepalive (NU-21) is not yet proven on a push of
         15 minutes to GitHub.
NU-UN-3  Surfer v0.7.0 has not been run against the fe_demo .sucl files
         (waves/chk_sucl.py).
NU-UN-4  The new-user test on a fresh account (new_user.md, account
         randy) has not been run to completion.
NU-UN-5  The full regression has not been run since VERILATOR_COVERAGE,
         GENHTML and FST2VCD moved to tools/bin. Coverage reports now
         come from verilator_coverage 5.048; they came from a 5.020 on
         PATH before, so figures may differ slightly from older reports.
