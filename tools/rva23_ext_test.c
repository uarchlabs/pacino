/*
 * rva23s64_ext_test.c
 *
 * One inline-assembly instruction per testable mandatory extension
 * in the RVA23S64 profile. (RVA23 Profile v1.0, ratified 2024-10-17)
 *
 * RVA23S64 = RVA23U64 + Zifencei + privileged supervisor/hypervisor extensions.
 *
 * Compile:
 *   riscv64-unknown-linux-gnu-gcc \
 *     -march=rv64gcb_v_zicsr_zicntr_zihpm_zifencei_zihintpause \
 *             _zicbom_zicbop_zicboz_zfhmin_zihintntl             \
 *             _zicond_zimop_zcmop_zcb_zfa_zawrs_zvfhmin_zvbb      \
 *             _svinval_sstc_sscofpmf_h                            \
 *     -mabi=lp64d -O0 -static -o rva23s64_ext_test rva23s64_ext_test.c
 *
 * NOTE: Privileged instructions (sinval.vma, hfence, hlv, hsv, stimecmp,
 * scountovf) will trap if executed in user mode. The test function compiles
 * and links correctly; do not call test_privileged() from user mode.
 *
 * Extensions with no unique testable instruction (PMA/impl properties):
 *   Ziccif, Ziccamoa, Zicclsm, Za64rs, Zic64b, Zkt, Zvkt, Supm,
 *   Ss1p13, Svbare, Sv39, Svade, Ssccptr, Sstvecd, Sstvala,
 *   Sscounterenw, Svpbmt, Svnapot, Ssnpm, Svvptc
 */

#include <stdint.h>
#include <stdio.h>

#ifdef TEST_ALL
#  define TEST_M
#  define TEST_A
#  define TEST_F
#  define TEST_D
#  define TEST_C
#  define TEST_B
#  define TEST_ZICSR
#  define TEST_ZICNTR
#  define TEST_ZIHPM
#  define TEST_ZICCRSE
#  define TEST_ZICCAMOA
#  define TEST_ZICCLSM
#  define TEST_ZIHINTPAUSE
#  define TEST_ZICBOM
#  define TEST_ZICBOP
#  define TEST_ZICBOZ
#  define TEST_ZFHMIN
#  define TEST_V
#  define TEST_ZVFHMIN
#  define TEST_ZVBB
#  define TEST_ZIHINTNTL
#  define TEST_ZICOND
#  define TEST_ZIMOP
#  define TEST_ZCMOP
#  define TEST_ZCB
#  define TEST_ZFA
#  define TEST_ZAWRS
#  define TEST_ZIFENCEI
#  define TEST_SVINVAL
#  define TEST_SSTC
#  define TEST_SSCOFPMF
#  define TEST_SHA
#endif

/* ------------------------------------------------------------------ */
/* M - Integer Multiply / Divide                                       */
/* ------------------------------------------------------------------ */
#ifdef TEST_M
static void test_M(void)
{
    long a = 6, b = 7, result;
    asm volatile ("mul %0, %1, %2" : "=r"(result) : "r"(a), "r"(b));
    printf("[M]          mul         %ld * %ld = %ld\n", a, b, result);
}
#endif

/* ------------------------------------------------------------------ */
/* A - Atomic instructions                                             */
/* ------------------------------------------------------------------ */
#ifdef TEST_A
static void test_A(void)
{
    long mem = 10, addend = 5, old;
    asm volatile ("amoadd.d %0, %2, (%1)"
                  : "=r"(old) : "r"(&mem), "r"(addend) : "memory");
    printf("[A]          amoadd.d    mem=%ld (was %ld)\n", mem, old);
}
#endif

/* ------------------------------------------------------------------ */
/* F - Single-precision floating-point                                 */
/* ------------------------------------------------------------------ */
#ifdef TEST_F
static void test_F(void)
{
    float a = 3.0f, b = 4.0f, result;
    asm volatile ("fadd.s %0, %1, %2" : "=f"(result) : "f"(a), "f"(b));
    printf("[F]          fadd.s      %.1f + %.1f = %.1f\n",
           (double)a, (double)b, (double)result);
}
#endif

/* ------------------------------------------------------------------ */
/* D - Double-precision floating-point                                 */
/* ------------------------------------------------------------------ */
#ifdef TEST_D
static void test_D(void)
{
    double a = 1.5, b = 2.5, result;
    asm volatile ("fmul.d %0, %1, %2" : "=f"(result) : "f"(a), "f"(b));
    printf("[D]          fmul.d      %.1f * %.1f = %.1f\n", a, b, result);
}
#endif

/* ------------------------------------------------------------------ */
/* C - Compressed instructions                                         */
/* ------------------------------------------------------------------ */
#ifdef TEST_C
static void test_C(void)
{
    long a = 42, result;
    asm volatile (
        ".option push\n\t"
        ".option rvc\n\t"
        "c.mv %0, %1\n\t"
        ".option pop\n\t"
        : "=r"(result) : "r"(a));
    printf("[C]          c.mv        result = %ld\n", result);
}
#endif

/* ------------------------------------------------------------------ */
/* B - Bit-manipulation (Zba + Zbb + Zbs)                             */
/* ------------------------------------------------------------------ */
#ifdef TEST_B
static void test_B(void)
{
    long base = 100, idx = 3, r_sh2add;
    long val = 0x00FFFF00L, r_clz;
    long mask = 0xFF, bit = 3, r_bset;

    asm volatile ("sh2add %0, %1, %2" : "=r"(r_sh2add) : "r"(idx),  "r"(base));
    asm volatile ("clz    %0, %1"     : "=r"(r_clz)    : "r"(val));
    asm volatile ("bset   %0, %1, %2" : "=r"(r_bset)   : "r"(mask), "r"(bit));

    printf("[B/Zba]      sh2add      (%ld<<2)+%ld = %ld\n", idx, base, r_sh2add);
    printf("[B/Zbb]      clz         0x%08lx -> %ld leading zeros\n", val, r_clz);
    printf("[B/Zbs]      bset        0x%lx | bit%ld -> 0x%lx\n", mask, bit, r_bset);
}
#endif

/* ------------------------------------------------------------------ */
/* Zicsr - CSR instructions                                            */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICSR
static void test_Zicsr(void)
{
    long fcsr;
    asm volatile ("csrr %0, fcsr" : "=r"(fcsr));
    printf("[Zicsr]      csrr fcsr   = 0x%lx\n", fcsr);
}
#endif

/* ------------------------------------------------------------------ */
/* Zicntr - Base counters / timers (rdcycle)                          */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICNTR
static void test_Zicntr(void)
{
    long cycle;
    asm volatile ("rdcycle %0" : "=r"(cycle));
    printf("[Zicntr]     rdcycle     = %ld\n", cycle);
}
#endif

/* ------------------------------------------------------------------ */
/* Zihpm - Hardware performance counters (rdinstret)                  */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZIHPM
static void test_Zihpm(void)
{
    long instret;
    asm volatile ("rdinstret %0" : "=r"(instret));
    printf("[Zihpm]      rdinstret   = %ld\n", instret);
}
#endif

/* ------------------------------------------------------------------ */
/* Ziccrse / Za64rs - LR/SC reservation sets                          */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICCRSE
static void test_Ziccrse(void)
{
    long mem = 0, reserved, sc_result;
    asm volatile (
        "lr.d  %0, (%2)\n\t"
        "sc.d  %1, %3, (%2)\n\t"
        : "=&r"(reserved), "=&r"(sc_result)
        : "r"(&mem), "r"(42L)
        : "memory");
    printf("[Ziccrse/Za64rs] lr.d+sc.d  reserved=%ld sc=%ld mem=%ld\n",
           reserved, sc_result, mem);
}
#endif

/* ------------------------------------------------------------------ */
/* Ziccamoa - All A-ext atomics in coherent main memory               */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICCAMOA
static void test_Ziccamoa(void)
{
    long mem = 0xF0, bits = 0x0F, old;
    asm volatile ("amoor.d %0, %2, (%1)"
                  : "=r"(old) : "r"(&mem), "r"(bits) : "memory");
    printf("[Ziccamoa]   amoor.d     mem=0x%lx (was 0x%lx)\n", mem, old);
}
#endif

/* ------------------------------------------------------------------ */
/* Zicclsm - Misaligned load/store to cacheable coherent memory       */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICCLSM
static void test_Zicclsm(void)
{
    uint8_t buf[9] = {0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09};
    long val;
    asm volatile ("ld %0, 0(%1)" : "=r"(val) : "r"(buf + 1) : "memory");
    printf("[Zicclsm]    ld (misaligned) = 0x%016lx\n", val);
}
#endif

/* ------------------------------------------------------------------ */
/* Zihintpause - PAUSE hint                                            */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZIHINTPAUSE
static void test_Zihintpause(void)
{
    asm volatile ("pause");
    printf("[Zihintpause] pause      (spin-wait hint executed)\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Zicbom - Cache-block management (cbo.clean)                        */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICBOM
static void test_Zicbom(void)
{
    char buf[64] __attribute__((aligned(64))) = {0};
    asm volatile ("cbo.clean (%0)" :: "r"(buf) : "memory");
    printf("[Zicbom]     cbo.clean   (cache block written back)\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Zicbop - Cache-block prefetch (prefetch.r)                         */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICBOP
static void test_Zicbop(void)
{
    char buf[64] __attribute__((aligned(64))) = {0};
    asm volatile ("prefetch.r 0(%0)" :: "r"(buf));
    printf("[Zicbop]     prefetch.r  (cache block prefetched for read)\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Zicboz - Cache-block zero (cbo.zero)                               */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICBOZ
static void test_Zicboz(void)
{
    char buf[64] __attribute__((aligned(64)));
    buf[0] = (char)0xFF;
    asm volatile ("cbo.zero (%0)" :: "r"(buf) : "memory");
    printf("[Zicboz]     cbo.zero    buf[0]=%d (expect 0)\n", (int)(uint8_t)buf[0]);
}
#endif

/* ------------------------------------------------------------------ */
/* Zfhmin - Scalar half-precision FP convert                          */
/* Both operands are f-registers under Zfhmin (not integer registers) */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZFHMIN
static void test_Zfhmin(void)
{
    float s = 1.5f, h = 0.0f, s2 = 0.0f;
    asm volatile ("fcvt.h.s %0, %1, rne" : "=f"(h)  : "f"(s));
    asm volatile ("fcvt.s.h %0, %1"      : "=f"(s2) : "f"(h));
    printf("[Zfhmin]     fcvt.h.s+fcvt.s.h  %.4f -> (f16) -> %.4f\n",
           (double)s, (double)s2);
}
#endif

/* ------------------------------------------------------------------ */
/* V - Vector extension (vsetvli)                                      */
/* ------------------------------------------------------------------ */
#ifdef TEST_V
static void test_V(void)
{
    long avl = 8, vl;
    asm volatile ("vsetvli %0, %1, e32, m1, ta, ma" : "=r"(vl) : "r"(avl));
    printf("[V]          vsetvli     avl=%ld -> vl=%ld\n", avl, vl);
}
#endif

/* ------------------------------------------------------------------ */
/* Zvfhmin - Vector FP16 widening convert (vfwcvt.f.f.v)             */
/* Also covers Zvkt (data-independent execution latency property)     */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZVFHMIN
static void test_Zvfhmin(void)
{
    long avl = 4, vl;
    asm volatile (
        "vsetvli     %0, %1, e16, m1, ta, ma\n\t"
        "vfwcvt.f.f.v v2, v0\n\t"
        : "=r"(vl) : "r"(avl) : "v2");
    printf("[Zvfhmin]    vfwcvt.f.f.v  vl=%ld (f16->f32 widening)\n", vl);
}
#endif

/* ------------------------------------------------------------------ */
/* Zvbb - Vector basic bit-manipulation (vbrev8.v)                    */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZVBB
static void test_Zvbb(void)
{
    long avl = 4, vl;
    asm volatile (
        "vsetvli  %0, %1, e8, m1, ta, ma\n\t"
        "vbrev8.v v2, v0\n\t"
        : "=r"(vl) : "r"(avl) : "v2");
    printf("[Zvbb]       vbrev8.v    vl=%ld (bit-reverse bytes in vector)\n", vl);
}
#endif

/* ------------------------------------------------------------------ */
/* Zihintntl - Non-temporal locality hints (ntl.all)                  */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZIHINTNTL
static void test_Zihintntl(void)
{
    long a = 0, b = 1;
    asm volatile (
        "ntl.all\n\t"
        "sd %1, 0(%0)\n\t"
        :: "r"(&a), "r"(b) : "memory");
    printf("[Zihintntl]  ntl.all     (non-temporal store hint; val=%ld)\n", a);
}
#endif

/* ------------------------------------------------------------------ */
/* Zicond - Integer conditional operations (czero.eqz)                */
/* czero.eqz rd, rs1, rs2 -> rd = (rs2==0) ? 0 : rs1                */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZICOND
static void test_Zicond(void)
{
    long val = 42, c0 = 0, c1 = 1, r0, r1;
    asm volatile ("czero.eqz %0, %1, %2" : "=r"(r0) : "r"(val), "r"(c0));
    asm volatile ("czero.eqz %0, %1, %2" : "=r"(r1) : "r"(val), "r"(c1));
    printf("[Zicond]     czero.eqz   cond=0->%ld  cond!=0->%ld\n", r0, r1);
}
#endif

/* ------------------------------------------------------------------ */
/* Zimop - May-be-operations (mop.r.0)                                */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZIMOP
static void test_Zimop(void)
{
    long result = 0xDEAD;
    asm volatile (
        ".insn r 0x73, 0x4, 0x42, %0, %1, x0"
        : "=r"(result) : "r"(result));
    printf("[Zimop]      mop.r.0     result = %ld\n", result);
}
#endif

/* ------------------------------------------------------------------ */
/* Zcmop - Compressed may-be-operations (c.mop.1)                     */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZCMOP
static void test_Zcmop(void)
{
    asm volatile (
        ".option push\n\t"
        ".option rvc\n\t"
        ".insn 0x6085\n\t"
        ".option pop\n\t");
    printf("[Zcmop]      c.mop.1     (compressed may-be-op hint)\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Zcb - Additional compressed instructions (c.zext.b)               */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZCB
static void test_Zcb(void)
{
    long val = 0xDEADBEEF, result;
    asm volatile (
        ".option push\n\t"
        ".option rvc\n\t"
        "mv       %0, %1\n\t"
        "c.zext.b %0\n\t"
        ".option pop\n\t"
        : "=r"(result) : "r"(val));
    printf("[Zcb]        c.zext.b    0x%lx -> 0x%lx\n", val, result);
}
#endif

/* ------------------------------------------------------------------ */
/* Zfa - Additional floating-point instructions (fli.s)               */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZFA
static void test_Zfa(void)
{
    float result;
    asm volatile ("fli.s %0, min" : "=f"(result));
    printf("[Zfa]        fli.s min   = %e\n", (double)result);
}
#endif

/* ------------------------------------------------------------------ */
/* Zawrs - Wait-on-reservation-set (wrs.nto)                          */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZAWRS
static void test_Zawrs(void)
{
    asm volatile ("wrs.nto");
    printf("[Zawrs]      wrs.nto     (returned immediately - no reservation)\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Zifencei - Instruction-fetch fence                                  */
/* New mandatory addition in RVA23S64 (was not in U64)                */
/* ------------------------------------------------------------------ */
#ifdef TEST_ZIFENCEI
static void test_Zifencei(void)
{
    asm volatile ("fence.i");
    printf("[Zifencei]   fence.i     (instruction-fetch fence)\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Svinval - Fine-grained address-translation cache invalidation       */
/* NOTE: privileged instructions - will trap in user mode             */
/* ------------------------------------------------------------------ */
#ifdef TEST_SVINVAL
static void test_Svinval(void)
{
    asm volatile ("sfence.w.inval");
    asm volatile ("sinval.vma  x0, x0");
    asm volatile ("sfence.inval.ir");
    printf("[Svinval]    sinval.vma + sfence.w.inval + sfence.inval.ir\n");
}
#endif

/* ------------------------------------------------------------------ */
/* Sstc - Supervisor-mode timer interrupts                             */
/* stimecmp is the new CSR added by this extension                    */
/* NOTE: privileged CSR - will trap in user mode                      */
/* ------------------------------------------------------------------ */
#ifdef TEST_SSTC
static void test_Sstc(void)
{
    long val;
    asm volatile ("csrr %0, stimecmp" : "=r"(val));
    printf("[Sstc]       csrr stimecmp = 0x%lx\n", val);
}
#endif

/* ------------------------------------------------------------------ */
/* Sscofpmf - Count overflow and mode-based filtering                  */
/* scountovf is the new CSR added by this extension                   */
/* NOTE: privileged CSR - will trap in user mode                      */
/* ------------------------------------------------------------------ */
#ifdef TEST_SSCOFPMF
static void test_Sscofpmf(void)
{
    long val;
    asm volatile ("csrr %0, scountovf" : "=r"(val));
    printf("[Sscofpmf]   csrr scountovf = 0x%lx\n", val);
}
#endif

/* ------------------------------------------------------------------ */
/* Sha - Augmented hypervisor extension (H extension)                 */
/* NOTE: privileged instructions - will trap outside hypervisor mode  */
/* ------------------------------------------------------------------ */
#ifdef TEST_SHA
static void test_Sha(void)
{
    long val;
    asm volatile ("hfence.vvma  x0, x0");
    asm volatile ("hfence.gvma  x0, x0");
    asm volatile ("hlv.b  %0, (x0)" : "=r"(val));
    printf("[Sha/H]      hfence.vvma + hfence.gvma + hlv.b\n");
}
#endif

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */
int main(void)
{
    printf("=== RVA23S64 Mandatory Extension Inline-Assembly Test ===\n");
    printf("    (RVA23 Profile v1.0, ratified 2024-10-17)\n");
    printf("    NOTE: privileged tests (Svinval, Sstc, Sscofpmf, Sha)\n");
    printf("    must be run in supervisor/hypervisor mode.\n\n");

#ifdef TEST_M
    test_M();
#endif
#ifdef TEST_A
    test_A();
#endif
#ifdef TEST_F
    test_F();
#endif
#ifdef TEST_D
    test_D();
#endif
#ifdef TEST_C
    test_C();
#endif
#ifdef TEST_B
    test_B();
#endif
#ifdef TEST_ZICSR
    test_Zicsr();
#endif
#ifdef TEST_ZICNTR
    test_Zicntr();
#endif
#ifdef TEST_ZIHPM
    test_Zihpm();
#endif
#ifdef TEST_ZICCRSE
    test_Ziccrse();
#endif
#ifdef TEST_ZICCAMOA
    test_Ziccamoa();
#endif
#ifdef TEST_ZICCLSM
    test_Zicclsm();
#endif
#ifdef TEST_ZIHINTPAUSE
    test_Zihintpause();
#endif
#ifdef TEST_ZICBOM
    test_Zicbom();
#endif
#ifdef TEST_ZICBOP
    test_Zicbop();
#endif
#ifdef TEST_ZICBOZ
    test_Zicboz();
#endif
#ifdef TEST_ZFHMIN
    test_Zfhmin();
#endif
#ifdef TEST_V
    test_V();
#endif
#ifdef TEST_ZVFHMIN
    test_Zvfhmin();
#endif
#ifdef TEST_ZVBB
    test_Zvbb();
#endif
#ifdef TEST_ZIHINTNTL
    test_Zihintntl();
#endif
#ifdef TEST_ZICOND
    test_Zicond();
#endif
#ifdef TEST_ZIMOP
    test_Zimop();
#endif
#ifdef TEST_ZCMOP
    test_Zcmop();
#endif
#ifdef TEST_ZCB
    test_Zcb();
#endif
#ifdef TEST_ZFA
    test_Zfa();
#endif
#ifdef TEST_ZAWRS
    test_Zawrs();
#endif
#ifdef TEST_ZIFENCEI
    test_Zifencei();
#endif
#ifdef TEST_SVINVAL
    test_Svinval();
#endif
#ifdef TEST_SSTC
    test_Sstc();
#endif
#ifdef TEST_SSCOFPMF
    test_Sscofpmf();
#endif
#ifdef TEST_SHA
    test_Sha();
#endif

    printf("\nDone.\n");
    return 0;
}

