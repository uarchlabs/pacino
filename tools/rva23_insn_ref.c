/*
 * rva23s64_insn_ref.c
 *
 * One instruction per testable mandatory extension in the RVA23S64 profile.
 * (RVA23 Profile v1.0, ratified 2024-10-17)
 *
 * Compile only, never link or execute.
 *
 *   riscv64-unknown-linux-gnu-gcc \
 *     -march=rv64gcb_v_zicsr_zicntr_zihpm_zifencei_zihintpause \
 *             _zicbom_zicbop_zicboz_zfhmin_zihintntl             \
 *             _zicond_zimop_zcmop_zcb_zfa_zawrs_zvfhmin_zvbb      \
 *             _svinval_svnapot_sstc_sscofpmf_h                    \
 *     -mabi=lp64d -O0 -c -o rva23s64_insn_ref.o rva23s64_insn_ref.c
 *
 * Extensions with no unique testable instruction are noted but omitted:
 *   Ziccif, Ziccamoa, Zicclsm, Za64rs, Zic64b, Zkt, Zvkt, Supm,
 *   Ss1p13, Svbare, Sv39, Svade, Ssccptr, Sstvecd, Sstvala,
 *   Sscounterenw, Svpbmt, Svnapot, Ssnpm, Svvptc
 */

void rva23s64_insn_ref(void)
{
    /* ---------------------------------------------------------------- */
    /* RVA23U64 mandatory unprivileged extensions                        */
    /* ---------------------------------------------------------------- */
    asm volatile ("mul       x1,  x2,  x3");              /* M        - integer multiply */
    asm volatile ("amoadd.d  x1,  x2,  (x3)");            /* A        - atomic add doubleword */
    asm volatile ("fadd.s    f1,  f2,  f3");               /* F        - single-precision add */
    asm volatile ("fmul.d    f1,  f2,  f3");               /* D        - double-precision multiply */
    asm volatile ("c.mv      x8,  x9");                    /* C        - compressed register move */
    asm volatile ("sh2add    x1,  x2,  x3");               /* B/Zba    - shift-left-2 and add */
    asm volatile ("clz       x1,  x2");                    /* B/Zbb    - count leading zeros */
    asm volatile ("bset      x1,  x2,  x3");               /* B/Zbs    - set single bit */
    asm volatile ("csrr      x1,  fcsr");                  /* Zicsr    - CSR read */
    asm volatile ("rdcycle   x1");                         /* Zicntr   - read cycle counter */
    asm volatile ("rdinstret x1");                         /* Zihpm    - read instret counter */
    asm volatile ("lr.d      x1,  (x2)");                  /* Ziccrse/Za64rs - load-reserved */
    asm volatile ("amoor.d   x1,  x2,  (x3)");            /* Ziccamoa - atomic OR doubleword */
    asm volatile ("ld        x1,  1(x2)");                 /* Zicclsm  - misaligned load */
    asm volatile ("pause");                                /* Zihintpause - spin-wait hint */
    asm volatile ("cbo.clean (x1)");                       /* Zicbom   - cache block clean */
    asm volatile ("prefetch.r 0(x1)");                     /* Zicbop   - cache block prefetch read */
    asm volatile ("cbo.zero  (x1)");                       /* Zicboz   - cache block zero */
    asm volatile ("fcvt.h.s  f1,  f2,  rne");              /* Zfhmin   - convert f32 to f16 */
    asm volatile ("fcvt.s.h  f1,  f2");                    /* Zfhmin   - convert f16 to f32 */
    asm volatile ("vsetvli   x1,  x2,  e32, m1, ta, ma");  /* V        - set vector length */
    asm volatile ("vfwcvt.f.f.v v2, v0");                  /* Zvfhmin  - vector f16 to f32 widen */
    asm volatile ("vbrev8.v  v2,  v0");                    /* Zvbb     - vector bit-reverse bytes */
    asm volatile ("ntl.all");                              /* Zihintntl - non-temporal locality hint */
    asm volatile ("czero.eqz x1,  x2,  x3");              /* Zicond   - conditional zero if equal */
    asm volatile (".insn r 0x73, 0x4, 0x42, x1, x2, x0"); /* Zimop    - may-be-op mop.r.0 */
    asm volatile (".insn 0x6085");                         /* Zcmop    - compressed may-be-op c.mop.1 */
    asm volatile ("c.zext.b  x8");                         /* Zcb      - zero-extend byte */
    asm volatile ("fli.s     f1,  min");                   /* Zfa      - load float immediate */
    asm volatile ("wrs.nto");                              /* Zawrs    - wait on reservation set */

    /* ---------------------------------------------------------------- */
    /* RVA23S64 mandatory privileged/supervisor additions               */
    /* ---------------------------------------------------------------- */
    asm volatile ("fence.i");                              /* Zifencei - instruction-fetch fence */
    asm volatile ("sinval.vma    x1,  x2");                /* Svinval  - fine-grained TLB invalidation */
    asm volatile ("sfence.w.inval");                       /* Svinval  - order stores before sinval */
    asm volatile ("sfence.inval.ir");                      /* Svinval  - order sinval before ifetches */
    asm volatile ("csrr      x1,  stimecmp");              /* Sstc     - supervisor timer compare CSR */
    asm volatile ("csrr      x1,  scountovf");             /* Sscofpmf - counter overflow CSR */
    asm volatile ("hfence.vvma  x0,  x0");                 /* Sha/H    - hypervisor virt guest TLB fence */
    asm volatile ("hfence.gvma  x0,  x0");                 /* Sha/H    - hypervisor guest-phys TLB fence */
    asm volatile ("hlv.b     x1,  (x2)");                  /* Sha/H    - hypervisor virtual load byte */
    asm volatile ("hsv.b     x1,  (x2)");                  /* Sha/H    - hypervisor virtual store byte */
    asm volatile ("csrr      x1,  sstateen0");             /* Ssstateen - supervisor state enable CSR */
}

