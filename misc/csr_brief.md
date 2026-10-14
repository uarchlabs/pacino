# XiangShan CSR implementation report

**Source.** I read `xiangshan/scala/src/main/scala/xiangshan/` and checked
selected points against the generated SystemVerilog in `xiangshan/rtl/`. Paths
below are relative to `scala/src/main/scala/xiangshan/backend/fu/NewCSR/`
unless they name another directory. For the items I checked, the RTL matches
this Scala.

**Coverage.** I read these files in full:
- NewCSR.scala, CSRModule.scala, CSRFields.scala, CSRPermitModule.sv/.scala,
  TrapHandleModule.scala.
- Two background agents read the per-level CSR files, AIA, interrupts, PMP,
  debug and the pipeline integration.

Defects marked confirmed were traced in the RTL. Items marked unverified come
from source reading only.

---

## 1. Organization

**Live and legacy code.**
- The live CSR unit is `NewCSR`, about 8.2k lines of Chisel. It is created by
  `fu/wrapper/CSR.scala:55`.
- `fu/CSR.scala` is the old implementation and is almost entirely commented
  out. Only some IO bundles are still used: `CSRFileIO`, `PerfCounterIO`,
  `PFEvent`.
- `fu/util/DebugCSR.scala` is dead code.

**Framework.**
- **One module per CSR.** Each CSR is a `CSRModule[T <: CSRBundle]`
  (CSRModule.scala:10). Every field is a `CSREnumType` with a type: `RO`, `RW`,
  `WARL`, `WLRL`, or a `Ref*` form that makes it a view of another register.
- **WARL is per field and drops illegal writes.** A field updates only when
  `wen && wfield.isLegal` (CSRModule.scala:33). An illegal value leaves the old
  value in place; it is not mapped to a legal one. Some CSRs replace this with
  their own write function. For example, satp drops the whole write on an
  illegal MODE, while hgatp keeps the old MODE but still writes VMID and PPN.
- **Composition.** `NewCSR` is built by mixing in traits: MachineLevel,
  SupervisorLevel, HypervisorLevel, VirtualSupervisorLevel, Unprivileged,
  CSRAIA, DebugLevel, CSRCustom, CSRPMP. Each trait supplies an
  address-to-(write port, rdata) map. Reads are one `Mux1H` over all maps
  (NewCSR.scala:746).
- **Aliases and views.**
  - sstatus is a view of mstatus.
  - sip/sie/hip/hie/vsip/vsie and mvip/hvip are cross-connected alias ports
    (`IpIeAliasConnect`, NewCSR.scala:1201).
  - When V=1, S-mode addresses are redirected to the VS registers through
    `vsMapS`/`sMapVS` (NewCSR.scala:326-338).
- **Trap events.** Trap entry and return are separate "event" modules:
  TrapEntry{M,HS,VS,D}Event and Mret/Sret/DretEvent. Each produces per-CSR
  update bundles that the target CSR modules apply. PRVM, V and debugMode are
  registers updated from the events (NewCSR.scala:655-687).

## 2. Pipeline integration

**Execution unit.**
- There is one CSR FU, in BJU3, which it shares with Fence and the iterative
  divider.
- The issue queue is shared with ALU3. The writeback port has
  UncertainLatency.
- The FU is combinational: `out.valid = in.valid` in the same cycle. The
  exception is an indirect IMSIC read through mireg/sireg/vsireg, which waits
  in `s_waitIMSIC`.

**Full serialization.** All csrrw/rs/rc forms, ecall, ebreak, xret and wfi
decode as `waitForward + blockBackward`.
- Dispatch holds the instruction until the ROB is empty.
- `hasBlockBackward` then stops anything younger from entering the ROB until
  it retires.
- Interrupts are masked while it is in flight.
- As a result, the CSR op executes non-speculatively as the only instruction
  in the ROB. The state update happens at execute; there is no commit-time
  write buffer and no CSR renaming.

**Decode-time rewrites.**
- A read-only CSRR (rs1=x0) still waits for an empty ROB, but it clears
  blockBackward, so younger instructions can follow it.
- `csrr vl` reads the renamed vl physical register and executes speculatively
  in a vset unit.
- `csrr vlenb` becomes `addi rd, x0, VLEN/8`.
- There is no fast path for fflags, frm or vtype reads.

**Illegal and virtual-instruction detection is split.**
- Decode uses `CSRToDecode` (NewCSR.scala:1078-1091). It covers
  sfence/hfence/sinval under TVM/VTVM, HLV/HSV, FS/VS Off, WFI with TW/VTW,
  and reserved frm.
- The CSR FU checks address and privilege permission (`CSRPermitModule`),
  unimplemented addresses (`noCSRIllegal`), and stateen, counteren, AIA and
  Sstc gating.

**Selective flushPipe.** It is raised at execute only for:
- writes to satp, vsatp or hgatp;
- changes to frontend triggers;
- FS or VS moving between Off and non-Off;
- vstart moving between zero and non-zero;
- frm moving between reserved and non-reserved values.

**Traps.**
- Interrupts are sampled at the ROB head, gated by
  `intrBitSetReg && !hasWaitForward && interrupt_safe`.
- Trap information reaches NewCSR about 3 cycles after the head flush. The
  redirect target is selected at s5 of CtrlBlock.
- mret, sret and dret do not use the ROB flush. The CSR FU issues an
  execution-unit redirect (`flushAfter`, `isMisPred`) with the xret target.

**Interrupt pending path.** The pending vector is registered and then passed
through `DelayN(5)`, at least 6 cycles in total. The comment gives the reason
as keeping sret/mret atomic.

**fflags, vxsat, FS/VS dirty.** These are OR-reduced across the committing ROB
entries, registered, and accumulated into fcsr/vcsr. The status word is set to
Dirty at the same time.

**vtype and vl.**
- vtype is speculated in decode (`VTypeGen`) and checkpointed in a 64-entry
  VTypeBuffer. The CSR copy is written at commit.
- Architectural vl lives in a renamed physical register file. The CSR copy of
  vl is debug-only.

**CSR state distribution.**
- `TlbCsrBundle` and `CustomCSRCtrlIO` go out with 2-cycle `DelayN` toward the
  frontend and MemBlock.
- `distribute_csr` broadcasts every CSR write (address and data). PMP/PMA
  copies in the frontend, MemBlock and L2TLB snoop it, as do the per-block
  perf-event selectors.

**WFI.** WFI sets `hasWFI` in the ROB, which blocks commit. It clears on
`mie & mip`, a flush, a 2^20-cycle timeout, or `!srnctl.WFI_ENABLE`.
`cpu_halt` is tied to 0 (Backend.scala:669).

## 3. CSRs implemented

| Group | Contents | Notes |
|---|---|---|
| M | mstatus, misa (IMAFDCBVHSU, RO), medeleg, mideleg, mie, mip, mtvec (direct/vectored), mcounteren, mvien, mvip, menvcfg, mcountinhibit, mhpmevent3-31, mscratch, mepc, mcause, mtval, mtinst, mtval2, mseccfg, mcycle, minstret, mhpmcounter3-31, mvendorid=0, marchid=25, mimpid, mhartid (8 bits), mconfigptr, mstateen0 | Little-endian only; UXL/SXL hardwired to 64 |
| S | sstatus (view), sie, stvec, scounteren, senvcfg, sscratch, sepc, scause, stval, sip, stimecmp, satp, scountovf, sstateen0 | satp modes: Bare, Sv39, Sv48 |
| H | hstatus, hedeleg, hideleg, hie, htimedelta, hcounteren, hgeie, hvien, hvictl, henvcfg, htval, htinst, hip, hvip, hviprio1/2, hgatp, hgeip, hstateen0 | hgatp modes: Bare, Sv39x4, Sv48x4; VMID 14 bits, ASID 16 bits, GEILEN 63 |
| VS | vsstatus, vsie, vstvec, vsscratch, vsepc, vscause, vstval, vsip, vstimecmp, vsatp | |
| U | fflags/frm/fcsr, vstart, vxsat, vxrm, vcsr, vl, vtype, vlenb, cycle, time, instret, hpmcounter3-31 | VLEN 128 |
| AIA | miselect/mireg, mtopei, mtopi, siselect/sireg, stopei, stopi, vsiselect/vsireg, vstopei, vstopi; iprio array through *ireg | External IMSIC (`imsic_csr_top`) |
| Debug | tselect, tdata1/2, tinfo, tcontrol, dcsr, dpc, dscratch0/1 | mcontrol (type 2) only |
| PMP | pmpcfg (even indices), pmpaddr0..N-1 | OFF/TOR/NAPOT; NA4 not supported; no Smepmp |
| Custom | sbpctl 0x5C0, spfctl 0x5C1, slvpredctl 0x5C2, smblockctl 0x5C3, srnctl 0x5C4, sfetchctl 0x9E0 | Branch predictor, prefetch, load-violation predictor, sbuffer/misalign, fusion/WFI, icache parity |

**Performance counters.**
- 29 HPM counters: frontend 8, backend 8, MemBlock 8, L2 5.
- Sscofpmf is present: OF, MINH/SINH/UINH/VSINH/VUINH, scountovf and LCOFI.
- Event selection is distributed. Each block has an `HPerfMonitor` that
  combines 4 event indices with AND/XOR/ADD/OR.
- There is no Smcntrpmf: mcycle and minstret have no mode filtering.

**Triggers (Sdtrig).**
- Only mcontrol (type 2) is supported.
- Match modes: EQ, GE and LT only; no NAPOT or mask matching.
- TIMING and HIT are forced to 0, and there is no data-value match.
- There are no VS/VU enables, so triggers never fire in V-mode.
- Action is breakpoint, or debug-mode entry when DMODE=1.
- Chain length is bounded by `TriggerChainMaxLength`. tdata updates reach the
  frontend and MemBlock 2 cycles later.

**Interrupt selection.**
- `InterruptFilter` builds the M/HS/VS enabled-pending vectors.
- `TrapHandleModule` picks the cause by fixed group priority and applies
  mideleg/hideleg plus mvien/hvien (TrapHandleModule.scala:75-77).
- The AIA iprio values only affect the `*topi` read values, not which trap is
  taken.
- mtopi and stopi only consider the 11 standard causes; local interrupts 14-63
  never appear in them.
- There is no NMI path.

## 4. RVA23 gaps (CSR level)

| Item | Status | Evidence |
|---|---|---|
| **Svpbmt** (mandatory) | `menvcfg.PBMTE` and `henvcfg.PBMTE` are RO 0, so Svpbmt cannot be enabled | CSRBundles.scala:48 (base class all RO); `MEnvCfg` overrides only STCE (MachineLevel.scala:585-589) |
| **Zicbom/Zicboz enables** | CBIE, CBCFE, CBZE are RO 0 in menvcfg, senvcfg and henvcfg; S/U cannot be granted CBO access | CSRBundles.scala:51-53 |
| **Ssnpm / Smnpm / Supm** | PMM fields RO 0 and HUPMM absent; pointer masking not implemented | CSRBundles.scala:50, HypervisorLevel.scala:193-206 |
| **Sha / H-extension tinst** | mtinst and htinst are always written 0 on trap (allowed by the spec) | CSREvents/TrapEntryMEvent.scala:131 |
| **vstart on vector memory faults** | The ROB exception path has `vstartEn := false.B`, and MemBlock's vstart is not connected to the backend. vstart is not set to the faulting element. | rob/Rob.scala:1085,1110; XSCore.scala:155-156 |
| Ssstateen | Only index 0 exists; xstateen1-3 absent | MachineLevel.scala:354 |
| Smrnmi, Smcntrpmf, Smcsrind ireg2-6, Smepmp, Zkr seed, Zcmt jvt, Zicfilp/Zicfiss | Absent | Agent inventory; mseccfg is all RO |
| Met | Sstc, Sscofpmf, Ssu64xl, Sscounterenw/Shcounterenw, Shvsatpa, Shgatpa (Sv39x4/Sv48x4), Shvstvecd, Svinval (ROB tracks the sequence), Zicntr, Zihpm | |

Svadu is absent (`ADUE` RO 0). This matches the project note that Svadu is the
one intended optional extension.

## 5. Defects found

**Confirmed (Scala and generated RTL agree):**

1. **PMP writes are not permission-gated.** `cfgs`/`pmpaddr` use the raw
   `wen`, not `wenLegal` (NewCSR.scala:407,412; RTL `NewCSR.sv:8841`
   `.w_wen(wen & ...)`).
   - Effect: an S- or U-mode `csrw pmpcfg0` raises illegal instruction, but
     the PMP register is still written.
   - The same unqualified `csrWen` drives `distribute_csr`
     (wrapper/CSR.scala:279), so the PMP copies in the frontend, MemBlock and
     L2TLB are updated too.
   - There is no decode-side CSR permission check to prevent this.
2. **iprio array write enable has no valid, wen or permission term.** It is
   `addr === mireg && miselect === idx` and nothing else (NewCSR.scala:395,400;
   RTL `NewCSR.sv:8156`).
   - Wrapper wdata for set/clear forms is computed from `regOut`. For mireg,
     `regOut` is mireg's own placeholder register, not the selected iprio.
   - Effect: a plain `csrr rd, mireg` writes a stale value into the selected
     iprio byte.
   - Unverified further risk: a cycle with `io.in.valid=0` and stale operand
     bits matching 0x351/0x151 could also write.
3. **Custom-CSR stateen decode is wrong.**
   `csrIsUCustom = addr[11:8] != 8 || addr[11:6] != 0b100011`
   (CSRPermitModule.scala:210; RTL line 179).
   - Intended: `== 8 || addr[11:6] == 0b110011`. Both the operator and the
     constant are wrong.
   - As written, almost every address counts as "custom". If M-mode clears
     `mstateen0.C` (reset is 1), nearly every non-M CSR access traps.
4. **vstopi tests the wrong bit for its external-interrupt candidates.**
   `vsip.asTypeOf(new VSipBundle)` uses Chisel's declaration-order layout, not
   the CSR field bit positions. In the RTL, Candidates 1-3 test
   `vsip[53] & vsie[53]` (InterruptFilter.sv:800-806). VS external interrupts
   never appear in vstopi, and local interrupt 53 is reported in their place.
5. **minstret is truncated.** `RobCSRIO.perfinfo.retiredInstr` is `UInt(3.W)`
   (RobBundles.scala:232; CtrlBlock.sv:1666), but CommitWidth is 8 and ROB
   entries can be compressed. Any cycle that retires 8 or more instructions
   loses the high bits.
6. **HLV/HSV check is inverted.** `illegalInst.hlsv := isModeHU && hstatus.HU`
   (NewCSR.scala:1085). The spec and the wrapper's own comment
   (wrapper/CSR.scala:328) require `!HU`.
7. **Write to mip.SEIP is gated by the wrong mvien bit.** It uses `mvien.SSIE`
   instead of `mvien.SEIE` (MachineLevel.scala:246; the comment two lines
   below states the SEIE rule).

**Unverified:**

- **Stale decode-time checks.** Writes to TVM, TW, VTVM or HU do not raise
  flushPipe. Younger instructions already decoded behind the serialized CSR
  write may carry stale `CSRToDecode` results.
- **Sstc timer pending is late after a stimecmp write.** STIP is recomputed
  only on a time update (SstcInterruptGen.scala:21). The new STIP takes effect
  on the next time tick rather than immediately.
- **mtopi/stopi gather masks.** The gather for mtopi is not masked by
  `~mideleg`, and the gather for stopi is not masked by `~hideleg`
  (InterruptFilter.scala:66-67). Their non-zero tests are masked.
- **vsatp illegal-MODE write with V=0.** PPN and ASID are written even when
  MODE is illegal, which contradicts the code comment
  (VirtualSupervisorLevel.scala:197-204).
- **vsireg reads sireg data.** The IMSIC path is a TODO (CSRAIA.scala:79,191).

## 6. Points relevant to an 8-wide design

- XiangShan keeps CSR handling simple by fully serializing it. The cost is an
  ROB drain on every CSR write and on every non-vl/vlenb CSR read, including
  fflags, frm, vxrm and vtype.
- The only paths it optimizes are vl and vtype (renamed or speculated) and
  vlenb (constant).
- The trap path is long: about 6 cycles from head flush to frontend redirect,
  plus at least 6 cycles of interrupt-pending delay.
- Distributing CSR state by broadcasting writes is simple, but defect 1 shows
  the risk. Every snooped copy must be qualified by the same legality check
  as the master register, and here none are.
