
mkdir -p pkg
rm -f pkg/*
mkdir -p pkg/rtl/lib/rtl
mkdir -p pkg/rtl/lib/tb

mkdir -p pkg/rtl/core/frontend/bpu/rtl
mkdir -p pkg/rtl/core/frontend/bpu/tb
mkdir -p pkg/rtl/core/frontend/decode/rtl
mkdir -p pkg/rtl/core/frontend/decode/tb
mkdir -p pkg/rtl/core/frontend/decode/tests

mkdir -p pkg/planning/arch

mkdir -p pkg/tools

cp $RVA_ROOT/rtl/lib/Makefile pkg/rtl/lib
cp $RVA_ROOT/rtl/lib/rtl/*    pkg/rtl/lib/rtl
cp $RVA_ROOT/rtl/lib/tb/*     pkg/rtl/lib/tb


cp $RVA_ROOT/rtl/core/frontend/bpu/Makefile  pkg/rtl/core/frontend/bpu
cp $RVA_ROOT/rtl/core/frontend/bpu/rtl/*     pkg/rtl/core/frontend/bpu/rtl
cp $RVA_ROOT/rtl/core/frontend/bpu/tb/*      pkg/rtl/core/frontend/bpu/tb

cp $RVA_ROOT/rtl/core/frontend/decode/Makefile   pkg/rtl/core/frontend/decode
cp $RVA_ROOT/rtl/core/frontend/decode/README.md  pkg/rtl/core/frontend/decode
cp $RVA_ROOT/rtl/core/frontend/decode/rtl/*      pkg/rtl/core/frontend/decode/rtl
cp $RVA_ROOT/rtl/core/frontend/decode/tb/*       pkg/rtl/core/frontend/decode/tb

cp planning/arch/bp_arb_spec.md pkg/planning/arch

cp tools/check_rva23_coverage.py pkg/tools
cp tools/check_spike_decode.py   pkg/tools
cp tools/gen_spike_oracle.py     pkg/tools

tar jcvf pkg.bz2 pkg
