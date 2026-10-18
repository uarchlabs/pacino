# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# fe_demo_sigs.py -- the signal lists of the scenario waveforms, read by
# mk_sucl.py, which writes the Surfer command files (FDT-12a), and
# chk_sucl.py, which checks them (fe_demo_tb_decisions.md FDT-1).
# DOC-001 wrote the lists in mk_gtkw.py; DOC-002 moved them here
# unchanged. Every scenario's first group, clock, holds the cycle
# counter tb.cyc (FDT-12b). DOC-003 added the signals the descriptions
# cite that the lists lacked: LP_PRED (fd06), F3_STRAD (fd17), FETCH_UC
# (fd18), mt_busy_line and u_maint.r_st in MAINT (fd19), u_ibuf.r_count
# in IBUF_OCC (fd02, fd20), and the fd09 groups TAGE_UPD, UPD_PC and
# BE_REDIR. DOC-004 dropped GTKWave (FDT-12): fst_names no longer forms
# GTKWave's names and gives each signal's enum type; fst_values reads
# the value changes the event markers are placed from (FDT-12c).
# DOC-006: two models, at one and two prediction slots (Makefile
# SCEN_2S). The lists are built for the slot count of the model that
# wrote the FST (scenarios(n), n from nslots), and every format comes
# from one table, FORMATS, through fmt(); radix() is gone.
#
# fst_names(fst) reads an FST's names; fst_values(fst, paths) the value
# changes of a few signals; nslots(names) the slot count of the model
# that wrote it; scenarios(n) the scenarios and their groups at n slots;
# fmt() the display format of one signal, from FORMATS.
import re
import subprocess


# ---------------------------------------------------------------------
# The FST's names: path without range -> (width, Surfer name, enum
# type).
#
# The names are read from the FST header (fst2vcd -e, from the GTKWave
# distribution; -e keeps the FST extensions, among them the enum
# tables). The path is the scope path joined by '.', without the range;
# it is the key used in the lists below.
#
# Surfer (wellen) forms the same path, except for an element of an
# unpacked array: Verilator writes it as a scope named after the array
# holding variables <array>[i], and wellen names each variable [i], so
# the path a.a[0] is Surfer's a.[0].
#
# The enum type is None for a signal that is not enum-typed. Verilator
# declares each enum type once, as a table at the top of the header
#   $attrbegin misc 07 <type> <n> <n names> <n values> <table> $end
# and writes '$attrbegin misc 07 "" <table> $end' before the $var of
# each signal of that type. Surfer shows such a signal's value names
# with the format Enum (FDT-12a).
# ---------------------------------------------------------------------
# The header only: fst2vcd is stopped at $enddefinitions rather than
# left to write the whole dump (DOC-006).
def fst_header(fst):
    lines = []
    with subprocess.Popen(['fst2vcd', '-e', '-f', fst], stdout=subprocess.PIPE,
                          text=True) as proc:
        for line in proc.stdout:
            if line.startswith('$enddefinitions'):
                break
            lines.append(line)
        proc.kill()
    if not lines:
        raise OSError('fst2vcd read no header from ' + fst)
    return ''.join(lines)


def fst_names(fst):
    names = {}
    scope = []
    tables = {}
    enum = None
    for line in fst_header(fst).split('\n'):
        w = line.split()
        if not w:
            continue
        if w[0] == '$attrbegin' and w[1:3] == ['misc', '07']:
            if w[3] == '""':
                enum = tables[w[4]]
            else:
                tables[w[-2]] = w[3]
        elif w[0] == '$scope':
            scope.append(w[2])
        elif w[0] == '$upscope':
            scope.pop()
        elif w[0] == '$var':
            snm = w[4]
            if scope:
                m = re.fullmatch(re.escape(scope[-1]) + r'(\[\d+\])', snm)
                if m:
                    snm = m.group(1)
            names.setdefault('.'.join(scope + [w[4]]),
                             (int(w[2]), '.'.join(scope + [snm]), enum))
            enum = None
    return names


# ---------------------------------------------------------------------
# The value changes of a few signals: path -> [(time, value)] in time
# order, the value an int, None while it has an x or z bit. Read from
# the whole dump (fst2vcd), keeping only the given paths.
# ---------------------------------------------------------------------
def fst_values(fst, paths):
    want = set(paths)
    code = {}
    seen = set()
    scope = []
    vals = {p: [] for p in paths}
    t = 0
    with subprocess.Popen(['fst2vcd', '-f', fst], stdout=subprocess.PIPE,
                          text=True) as proc:
        for line in proc.stdout:
            w = line.split()
            if not w:
                continue
            if w[0] == '$scope':
                scope.append(w[2])
            elif w[0] == '$upscope':
                scope.pop()
            elif w[0] == '$var':
                p = '.'.join(scope + [w[4]])
                if p in want and p not in seen:
                    seen.add(p)
                    code.setdefault(w[3], []).append(p)
            elif w[0] == '$enddefinitions':
                break
        for line in proc.stdout:
            if line[0] == '#':
                t = int(line[1:])
                continue
            if line[0] in 'bB':
                v, c = line[1:].split()
            elif line[0] in '01xzXZ':
                v, c = line[0], line[1:].strip()
            else:
                continue
            if c in code:
                n = None if re.search('[xzXZ]', v) else int(v, 2)
                for p in code[c]:
                    vals[p].append((t, n))
    missing = want - seen
    if missing:
        raise KeyError('not in the FST: ' + ', '.join(sorted(missing)))
    return vals


# ---------------------------------------------------------------------
# THE FORMAT TABLE (DOC-006, Jeff session-081, FDT-12a). Each row is
# (match, format, reason), tried in order; the first that matches gives
# the signal's Surfer format:
#   - a match starting 'tb.' is a full path, exactly;
#   - ENUM matches an enum-typed field (its FST enum table, fst_names);
#   - BIT matches a 1-bit signal;
#   - any other match is a regular expression for the whole of the last
#     name component, without its unpacked index ([i]).
# The rules: clk Clock, rstn Bit, cyc Unsigned, an enum Enum; the
# encoded fields Unsigned, their encodings in the descriptions; a 1-bit
# signal Bit, so a per-slot mask is Bit at one slot; a per-slot or
# per-lane mask Binary; a count or iteration number Unsigned at any
# width; the SRAM init write addresses Unsigned; an address, target, PC
# or data Hexadecimal. Rows marked PROVISIONAL are the IA's (DOC-006):
# no rule names them. A signal no row matches stops mk_sucl.py and
# fails chk_sucl.py; add it here.
# ---------------------------------------------------------------------
ENUM = 'enum-typed'
BIT = '1 bit'
FORMATS = [
    ('tb.clk', 'Clock', 'FDT-12a'),
    ('tb.rstn', 'Bit', 'FDT-12a'),
    ('tb.cyc', 'Unsigned', 'FDT-12a'),
    (ENUM, 'Enum', 'an enum-typed field, FDT-12a'),
    # The encoded fields: Unsigned, by name, ahead of BIT (trx_type is
    # one bit).
    (r'itlb_ifu_status|itlb_ifu_cause|l2t_itlb_status|l2t_itlb_cause|'
     r'itlb_l2t_priv|trx_type', 'Unsigned', 'an encoded field'),
    (BIT, 'Bit', 'a 1-bit signal'),
    # Per-slot and per-lane masks.
    (r'w_(tage|ittage)_pred_rdy_p2|w_sc_pred_rdy_p3|'
     r'(w_)?(tage|ittage|sc)_upd_val_u0|w_lp_upd_val_p0|'
     r'bkend_ftq_rsv_val|ftq_bkend_rsv_rdy|bpu_tage_upd_rdy',
     'Binary', 'a per-slot mask'),
    (r'ifu_ibuf_en', 'Binary', 'a per-lane mask'),
    # PROVISIONAL: TAGE's 3-bit direction counter, Binary as the
    # descriptions and the glossary write it (3'b100).
    (r'tage_prm_ctr', 'Binary', 'a direction counter, PROVISIONAL'),
    # Counts and iteration numbers.
    (r'r_count|w_n_pres|w_n_pop|spec_rctr|uaon|lp_conf|lp_past_itr|'
     r'lp_curs', 'Unsigned', 'a count or iteration number'),
    (r'waddr', 'Unsigned', 'an SRAM init write address'),
    # PROVISIONAL: indices, pointers, positions, ids and table numbers.
    (r'.*_idx(_p\d)?|.*_ptr|(.*_)?pos|tosr|tosw|bos|csp|.*_id|.*_source|'
     r'.*_comp', 'Unsigned', 'an index, pointer, position or table '
     'number, PROVISIONAL'),
    # Addresses, targets, PCs and data.
    (r'(.*_)?pc(_[pu]\d)?|.*_pft_p\d|(.*_)?(target|tgt)|.*addr(ess)?|'
     r'.*_[vp]pn\d?|fault_va|instr|.*_(data|cmp|swap)', 'Hexadecimal',
     'an address, target, PC or data'),
]


# The format of one signal, from FORMATS. KeyError when no row matches.
def fmt(path, width, enum):
    last = re.sub(r'\[\d+\]$', '', path.split('.')[-1])
    for match, f, _ in FORMATS:
        if match == ENUM:
            hit = bool(enum)
        elif match == BIT:
            hit = width == 1
        elif match.startswith('tb.'):
            hit = path == match
        else:
            hit = re.fullmatch(match, last) is not None
        if hit:
            return f
    raise KeyError('no row of fe_demo_sigs.FORMATS matches ' + path)


# The slot count of the model that wrote an FST, from its names: the p2
# slot array tb.dut.bpu_slot_p2 has one element per slot.
def nslots(names):
    n = 0
    while 'tb.dut.bpu_slot_p2.[%d].slot_valid' % n in names:
        n += 1
    if n == 0:
        raise KeyError('no tb.dut.bpu_slot_p2 slot in the FST')
    return n


# ---------------------------------------------------------------------
# Signal sets, by unit. D is fe_top's scope. scenarios(n) builds them
# for n prediction slots: every per-slot list runs over range(n), so a
# one-slot FST is given only the slot-0 names it has (DOC-006).
# ---------------------------------------------------------------------
D = 'tb.dut'
B = D + '.u_bpu'
Q = D + '.u_ftq'
I = D + '.u_ifu'
L = D + '.u_l1i'
TC = B + '.u_tage.u_tage_cntrl'
SLOT = ['slot_valid', 'br_type', 'pos', 'taken', 'target', 'pred_src']

# The scenarios in FD order; the Makefile's SCENARIOS.
NAMES = ['fd01_reset_init', 'fd02_steady', 'fd03_two_branch',
         'fd04_p2_override', 'fd05_p3_override', 'fd06_loop_pred',
         'fd07_calls_returns', 'fd08_indirect', 'fd09_tage',
         'fd10_pd_redirect', 'fd11_be_mispredict', 'fd12_training',
         'fd13_l1i', 'fd14_translation', 'fd15_faults', 'fd16_page_cross',
         'fd17_rvc', 'fd18_uncached', 'fd19_fencei_cbo',
         'fd20_backpressure', 'fd21_commit', 'fd22_sc_slot1',
         'fd23_jump_cut', 'fd24_call_slot1']


def scenarios(n):
    sl = range(n)

    def slots(arr):
        return ['%s.[%d].%s' % (arr, s, f) for s in sl for f in SLOT]

    def redir(arr):
        return ['%s.[%d].%s' % (arr, s, f) for s in sl
                for f in ('valid', 'target_pc')]

    def bits(scope, name):
        return ['%s.%s.%s[%d]' % (scope, name, name, s) for s in sl]

    clk = ['tb.clk', 'tb.rstn', 'tb.cyc']
    bpu_p0 = [D + '.ftq_pred_val_p0', D + '.ftq_pred_pc_p0',
              D + '.ftq_pred_idx_p0', Q + '.u_npc.w_hold']
    bpu_p1 = [D + '.bpu_pred_val_p1', D + '.bpu_pred_idx_p1',
              B + '.r_ubtb_blk_p1.hit', D + '.bpu_pred_pft_p1'] + \
        slots(D + '.bpu_pred_slot_p1')
    bpu_p2 = [B + '.r_val_p2', D + '.bpu_slot_val_p2',
              D + '.bpu_slot_idx_p2', B + '.w_ftb_valid_p2'] + \
        slots(D + '.bpu_slot_p2') + redir(D + '.bpu_redir_p2') + \
        [D + '.bpu_redir_idx_p2']
    bpu_p3 = [B + '.r_val_p3', D + '.bpu_slot_val_p3',
              D + '.bpu_slot_idx_p3'] + slots(D + '.bpu_slot_p3') + \
        redir(D + '.bpu_redir_p3') + [D + '.bpu_redir_idx_p3']
    ftq = [Q + '.w_ok_pred_p1', Q + '.w_ok_slot_p2', Q + '.w_ok_slot_p3',
           Q + '.w_ok_redir_p2', Q + '.w_ok_redir_p3', Q + '.w_redir_val',
           Q + '.w_redir_idx', Q + '.w_commit_ptr', D + '.ftq_full',
           D + '.ftq_empty']
    ftq_ifu = [D + '.ftq_ifu_req_val', D + '.ftq_ifu_req_rdy',
               D + '.ftq_ifu_idx', D + '.ftq_ifu_start_pc',
               D + '.ftq_ifu_next_pc', D + '.ftq_ifu_taken_val',
               D + '.ftq_ifu_taken_pos', D + '.ftq_ifu_flush_val',
               D + '.ftq_ifu_flush_idx', D + '.ftq_ifu_commit_ptr']
    ifu_l1i = [D + '.ifu_l1i_req_val', D + '.ifu_l1i_req_rdy',
               D + '.ifu_l1i_req_id', D + '.ifu_l1i_req_paddr',
               D + '.ifu_l1i_req_uncached', D + '.l1i_ifu_rsp_val',
               D + '.l1i_ifu_rsp_id']
    ifu_f3 = [D + '.ifu_ftq_pdwb_val', D + '.ifu_ftq_pdwb_idx',
              D + '.ifu_ftq_cfi_val', D + '.ifu_ftq_cfi_pos',
              D + '.ifu_ftq_mis_val', D + '.ifu_ftq_mis_pos',
              D + '.ifu_ftq_target', Q + '.w_pd_redir_val']
    ibuf = [D + '.ifu_ibuf_val', D + '.ifu_ibuf_en', D + '.ibuf_ifu_rdy']
    # fd02: the eight decode lanes' valids, the first lane's PC
    # (Jeff, session-081: the other lanes' PCs are not walked).
    dec8 = ['tb.dec_ibuf_rdy', 'tb.pd_out.[0].start_pc'] + \
        ['tb.pd_out.[%d].valid' % i for i in range(8)]
    dec0 = ['tb.dec_ibuf_rdy', 'tb.pd_out.[0].valid',
            'tb.pd_out.[0].start_pc', 'tb.pd_out.[0].ftq_idx',
            'tb.pd_out.[0].pos', 'tb.pd_out.[0].instr',
            'tb.pd_out.[0].is_rvc', 'tb.pd_out.[0].fault_cause',
            'tb.pd_out.[0].fault_va']
    # fd17: lane 0 in full, lane 4 (the straddling instruction) and the
    # is_rvc of every lane; the other lanes' rows are not walked.
    dec_rvc = dec0 + ['tb.pd_out.[4].valid', 'tb.pd_out.[4].start_pc',
                      'tb.pd_out.[4].pos', 'tb.pd_out.[4].is_rvc'] + \
        ['tb.pd_out.[%d].is_rvc' % i for i in (1, 2, 3, 5, 6, 7)]
    backend = ['tb.bkend_ftq_redir_val', 'tb.bkend_ftq_redir_idx',
               'tb.bkend_ftq_redir_pc', 'tb.bkend_ftq_redir_cause',
               'tb.bkend_ftq_redir_self', 'tb.bkend_ftq_rsv_val',
               'tb.bkend_ftq_commit_val', 'tb.bkend_ftq_commit_idx']
    rollback = [D + '.ftq_rollback_val', D + '.ftq_rollback_idx',
                D + '.ftq_rollback_corr', D + '.bpu_ghist_ptr',
                D + '.ras_restore_val', D + '.ras_restore_snapshot.tosr',
                D + '.ras_restore_snapshot.tosw',
                D + '.ras_restore_snapshot.bos']
    ras = [B + '.u_ras.tosr', B + '.u_ras.tosw', B + '.u_ras.bos',
           B + '.u_ras.ras_rst_done'] + bits(B, 'w_ras_pred_val_p2') + \
        bits(B, 'w_br_type_p2') + \
        ['%s.u_ras.spec_ret_addr.spec_ret_addr[%d]' % (B, i)
         for i in range(4)] + \
        ['%s.u_ras.spec_rctr.spec_rctr[%d]' % (B, i) for i in range(4)]
    ras_cmt = [D + '.ras_commit_val', D + '.ras_commit_br_type',
               D + '.ras_commit_ret_addr', B + '.u_ras.csp',
               B + '.u_ras.commit_top_valid', B + '.u_ras.commit_top_addr']
    tage_p2 = [B + '.w_tage_pred_rdy_p2'] + \
        ['%s.tage_pred_meta_p2.[%d].%s' % (TC, s, f) for s in sl
         for f in ('tage_prm_comp', 'tage_alt_comp', 'tage_using_primary',
                   'tage_prm_ctr', 'tage_pred_tkn')]
    tage_upd = [TC + '.trx_type', TC + '.tage_upd_val_u0'] + \
        ['%s.tage_upd_inp_u0.[%d].%s' % (TC, s, f) for s in sl
         for f in ('cond_mispredict', 'resolved_taken',
                   'tage_pred_meta.tage_prm_comp',
                   'tage_pred_meta.tage_alt_comp',
                   'tage_pred_meta.tage_pred_weak',
                   'tage_pred_meta.tage_prm_tkn',
                   'tage_pred_meta.tage_alt_tkn')] + \
        bits(TC, 'u_alc_wr') + bits(TC, 'u_alc_comp') + bits(TC, 'uaon')
    # The address of the branch each update slot carries. The TAGE
    # update input has no address; ftq_upd_conv forms every predictor's
    # update from one record in the same cycle, and the loop
    # predictor's copy carries it.
    upd_pc = ['%s.u_upd_conv.lp_upd_p0.[%d].pc' % (Q, s) for s in sl]
    be_redir = ['tb.bkend_ftq_redir_val', 'tb.bkend_ftq_redir_pc',
                'tb.bkend_ftq_redir_cause']
    sc_p3 = [B + '.w_sc_pred_rdy_p3'] + bits(B, 'w_sc_hit_p3') + \
        bits(B, 'w_taken_p3')
    itt_p2 = [B + '.w_ittage_pred_rdy_p2'] + \
        ['%s.w_ittage_pred_meta_p2.[%d].%s' % (B, s, f) for s in sl
         for f in ('ittage_hit', 'ittage_prm_comp', 'ittage_prm_tgt')]
    updates = ['tb.bkend_ftq_rsv_val', 'tb.ftq_bkend_rsv_rdy',
               B + '.w_lp_upd_val_p0', B + '.w_tage_upd_val_u0',
               B + '.w_ittage_upd_val_u0', B + '.w_sc_upd_val_u0',
               D + '.bpu_tage_upd_rdy', B + '.w_ras_commit_val'] + \
        ['%s.w_ubtb_upd_u0.[%d].valid' % (B, s) for s in sl]
    ftb_upd = [D + '.ftb_upd_valid_u0', D + '.ftb_upd_pc_u0',
               D + '.ftb_upd_hit_u0', D + '.ftb_upd_is_br_u0',
               D + '.ftb_upd_taken_u0', D + '.ftb_upd_is_jmp_u0',
               Q + '.u_npc.h3_ftb_upd']
    l1i = [L + '.b_rsp_valid.b_rsp_valid[0]',
           L + '.b_rsp_valid.b_rsp_valid[1]',
           L + '.b_mis_valid.b_mis_valid[0]',
           L + '.b_mis_valid.b_mis_valid[1]', L + '.u_mshr.mrg_hit'] + \
        ['%s.u_mshr.e_val.e_val[%d]' % (L, m) for m in range(4)] + \
        ['%s.u_mshr.e_got.e_got[%d]' % (L, m) for m in range(4)] + \
        ['tb.l1i_mem_a_valid', 'tb.l1i_mem_a_address',
         'tb.l1i_mem_a_source', 'tb.l1i_mem_d_valid', 'tb.l1i_mem_d_source',
         L + '.u_mshr.b_fil_valid.b_fil_valid[0]',
         L + '.u_mshr.b_fil_valid.b_fil_valid[1]']
    itlb = [D + '.ifu_itlb_req_val', D + '.ifu_itlb_req_rdy',
            D + '.ifu_itlb_vpn', D + '.itlb_ifu_rsp_val',
            D + '.itlb_ifu_status', D + '.itlb_ifu_ppn',
            D + '.itlb_ifu_cause']
    walk = ['tb.itlb_l2t_req_val', 'tb.itlb_l2t_req_rdy', 'tb.itlb_l2t_vpn',
            'tb.itlb_l2t_v', 'tb.itlb_l2t_priv', 'tb.u_ptw.r_st',
            'tb.u_ptw.r_g_on', 'tb.l2t_itlb_rsp_val', 'tb.l2t_itlb_status',
            'tb.l2t_itlb_ppn', 'tb.l2t_itlb_cause']
    walk_mem = ['tb.ptw_mem_req_val', 'tb.ptw_mem_req_rdy',
                'tb.ptw_mem_req_op', 'tb.ptw_mem_req_paddr',
                'tb.ptw_mem_req_cmp', 'tb.ptw_mem_req_swap',
                'tb.mem_ptw_rsp_val', 'tb.mem_ptw_rsp_data']
    xq = [I + '.u_xlate.xq_val', I + '.u_xlate.xq_pop',
          I + '.u_xlate.xq_idx', I + '.u_xlate.xq_pc',
          I + '.u_xlate.xq_cross', I + '.u_xlate.xq_ppn0',
          I + '.u_xlate.xq_ppn1', I + '.u_xlate.xq_fault0',
          I + '.u_xlate.xq_fault1', I + '.u_xlate.xq_uc']
    fault = [D + '.ifu_ftq_fault_val', D + '.ifu_ftq_fault_pos']
    maint = ['tb.cmt_ifu_maint_val', 'tb.cmt_ifu_maint_rdy',
             'tb.cmt_ifu_maint_op', 'tb.cmt_ifu_maint_paddr',
             I + '.u_maint.r_st', D + '.ifu_l1i_inv_val',
             D + '.ifu_l1i_inv_rdy', D + '.ifu_l1i_inv_all',
             D + '.ifu_l1i_inv_paddr', L + '.u_maint.r_st',
             L + '.mt_busy_any', L + '.mt_busy_line', D + '.l1i_ifu_inv_done',
             'tb.ifu_cmt_maint_ack']
    init = [B + '.u_tage.u_sram_init.state', B + '.u_tage.u_sram_init.waddr',
            D + '.bpu_tage_rdy', B + '.u_ittage.u_sram_init.state',
            B + '.u_ittage.u_sram_init.waddr', D + '.bpu_ittage_rdy',
            B + '.u_sc.u_sram_init.state', B + '.u_sc.u_sram_init.waddr',
            D + '.bpu_sc_ready', B + '.u_ras.ras_rst_done']
    first = [D + '.ftq_pred_val_p0', D + '.bpu_pred_val_p1',
             Q + '.w_ok_pred_p1', B + '.w_tage_pred_rdy_p2',
             B + '.w_ittage_pred_rdy_p2', B + '.w_sc_pred_rdy_p3']
    ftq_ptr = [Q + '.w_commit_ptr', D + '.ftq_full', D + '.ftq_empty',
               D + '.ftq_pred_idx_p0', D + '.ftq_ifu_idx']
    ibuf_occ = ibuf + [D + '.u_ibuf.r_count', D + '.u_ibuf.w_n_pres',
                       D + '.u_ibuf.w_n_pop']
    # The loop predictor's per-slot answer: at p1 the answer the uBTB
    # slot takes, at p2 the re-read with its count and confidence. The
    # p1 copies of lp_conf, lp_past_itr and lp_curs duplicate p2's and
    # are left out (Jeff, session-081).
    lp_pred = ['%s.w_lp_pred_p1.[%d].%s' % (B, s, f) for s in sl
               for f in ('lp_hit', 'lp_pred_is_loop', 'lp_pred_taken')] + \
        ['%s.w_lp_pred_p2.[%d].%s' % (B, s, f) for s in sl
         for f in ('lp_hit', 'lp_pred_is_loop', 'lp_pred_taken', 'lp_conf',
                   'lp_past_itr', 'lp_curs')]
    # F3's straddle register: the first half of a 32-bit instruction
    # that ends a block, held for the next block.
    f3_strad = [I + '.u_f3.r_strad_val', I + '.u_f3.r_strad_pc',
                I + '.u_f3.r_strad_idx']
    # ifu_fetch's commit gate on an uncached block.
    fetch_uc = [I + '.u_fetch.xq_uc', I + '.u_fetch.w_uc_gate']
    # fd23: the p2 block's start, the FTB's jump field, the cut and the
    # block's end (bp_cluster p2_class_comb, p2_succ_comb).
    jmp_cut = [B + '.r_pc_p2'] + bits(B, 'w_ftb_br_valid_p2') + \
        [B + '.w_ftb_jmp_valid_p2', B + '.w_jmp_pc_p2', B + '.w_jmp_cut_p2',
         D + '.bpu_blk_pft_p2']

    return [
        ('fd01_reset_init', [('clock', clk), ('sram_init', init),
                             ('bp_cluster_first', first),
                             ('bp_cluster_p0', bpu_p0)]),
        ('fd02_steady', [('clock', clk), ('bp_cluster_p0', bpu_p0),
                         ('bp_cluster_p1', bpu_p1), ('ftq', ftq),
                         ('ftq_ifu', ftq_ifu), ('ifu_l1i', ifu_l1i),
                         ('ifu_f3', ifu_f3), ('ibuf', ibuf_occ),
                         ('decode', dec8)]),
        ('fd03_two_branch', [('clock', clk), ('bp_cluster_p1_ubtb', bpu_p1),
                             ('bp_cluster_p2_ftb', bpu_p2), ('ftq', ftq)]),
        ('fd04_p2_override', [('clock', clk), ('bp_cluster_p1_ubtb', bpu_p1),
                              ('bp_cluster_p2_ftb', bpu_p2), ('ftq', ftq),
                              ('bp_cluster_p0', bpu_p0)]),
        ('fd05_p3_override', [('clock', clk), ('tage_p2', tage_p2),
                              ('bp_cluster_p2', bpu_p2), ('sc_p3', sc_p3),
                              ('bp_cluster_p3', bpu_p3), ('ftq', ftq)]),
        ('fd06_loop_pred', [('clock', clk), ('bp_cluster_p1', bpu_p1),
                            ('loop_pred_p1_p2', lp_pred),
                            ('bp_cluster_p2', bpu_p2), ('ftq', ftq),
                            ('loop_pred_update', [B + '.w_lp_upd_val_p0']),
                            ('decode', dec0)]),
        ('fd07_calls_returns', [('clock', clk), ('bp_cluster_p1', bpu_p1),
                                ('ras', ras), ('bp_cluster_p2', bpu_p2),
                                ('ftq', ftq), ('ras_commit', ras_cmt)]),
        ('fd08_indirect', [('clock', clk), ('ittage_p2', itt_p2),
                           ('bp_cluster_p2', bpu_p2), ('ftq', ftq)]),
        ('fd09_tage', [('clock', clk), ('tage_p2', tage_p2),
                       ('bp_cluster_p2', bpu_p2), ('backend', be_redir),
                       ('ftq_upd_conv', upd_pc), ('tage_update', tage_upd)]),
        ('fd10_pd_redirect', [('clock', clk), ('ftq_ifu', ftq_ifu),
                              ('ifu_f3', ifu_f3), ('ftq', ftq),
                              ('bp_cluster_p0', bpu_p0)]),
        ('fd11_be_mispredict', [('clock', clk), ('decode', dec0),
                                ('backend', backend), ('ftq', ftq),
                                ('ftq_ifu', ftq_ifu),
                                ('bp_history_ras', rollback),
                                ('bp_cluster_p0', bpu_p0)]),
        ('fd12_training', [('clock', clk), ('backend', backend),
                           ('ftq_upd_conv', updates),
                           ('ftb_update', ftb_upd),
                           ('bp_cluster_p0', bpu_p0)]),
        ('fd13_l1i', [('clock', clk), ('ftq_ifu', ftq_ifu),
                      ('ifu_l1i', ifu_l1i), ('l1i', l1i)]),
        ('fd14_translation', [('clock', clk), ('ifu_xlate', xq),
                              ('itlb', itlb), ('walker', walk),
                              ('walker_mem', walk_mem)]),
        ('fd15_faults', [('clock', clk), ('itlb', itlb), ('walker', walk),
                         ('ifu_xlate', xq), ('ifu_fault', fault),
                         ('decode', dec0), ('backend', backend)]),
        ('fd16_page_cross', [('clock', clk), ('ftq_ifu', ftq_ifu),
                             ('ifu_xlate', xq), ('itlb', itlb),
                             ('ifu_l1i', ifu_l1i), ('decode', dec0)]),
        ('fd17_rvc', [('clock', clk), ('ftq_ifu', ftq_ifu),
                      ('ifu_f3', ifu_f3), ('ifu_f3_straddle', f3_strad),
                      ('ibuf', ibuf), ('decode', dec_rvc)]),
        ('fd18_uncached', [('clock', clk), ('ftq_ifu', ftq_ifu),
                           ('ifu_xlate', xq), ('ifu_fetch', fetch_uc),
                           ('ifu_l1i', ifu_l1i), ('l1i', l1i),
                           ('backend', backend), ('decode', dec0)]),
        ('fd19_fencei_cbo', [('clock', clk), ('backend', backend),
                             ('maintenance', maint), ('ftq_ifu', ftq_ifu),
                             ('ifu_l1i', ifu_l1i)]),
        ('fd20_backpressure', [('clock', clk), ('bp_cluster_p0', bpu_p0),
                               ('ftq', ftq_ptr), ('ftq_ifu', ftq_ifu),
                               ('ibuf', ibuf_occ), ('decode', dec0)]),
        ('fd21_commit', [('clock', clk), ('backend', backend),
                         ('ftq', ftq_ptr), ('ras_commit', ras_cmt),
                         ('ras', ras)]),
        ('fd22_sc_slot1', [('clock', clk), ('tage_p2', tage_p2),
                           ('bp_cluster_p2', bpu_p2), ('sc_p3', sc_p3),
                           ('bp_cluster_p3', bpu_p3), ('ftq', ftq)]),
        ('fd23_jump_cut', [('clock', clk), ('bp_cluster_p2_ftb', jmp_cut),
                           ('bp_cluster_p2', bpu_p2), ('ftq', ftq),
                           ('bp_cluster_p0', bpu_p0)]),
        ('fd24_call_slot1', [('clock', clk), ('bp_cluster_p2', bpu_p2),
                             ('ras', ras), ('ftq', ftq),
                             ('ras_commit', ras_cmt)]),
    ]
