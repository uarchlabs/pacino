# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# fe_demo_sigs.py -- the signal lists of the scenario waveforms, shared
# by mk_gtkw.py (the GTKWave save files, FDT-12) and mk_sucl.py (the
# Surfer command files, FDT-12a), so the two viewers show the same
# signals in the same groups (fe_demo_tb_decisions.md FDT-1). DOC-001
# wrote the lists in mk_gtkw.py; DOC-002 moved them here unchanged.
# Every scenario's first group, clock, holds the cycle counter tb.cyc
# (FDT-12b). DOC-003 added the signals the descriptions cite that the
# lists lacked: LP_PRED (fd06), F3_STRAD (fd17), FETCH_UC (fd18),
# mt_busy_line and u_maint.r_st in MAINT (fd19), u_ibuf.r_count in
# IBUF_OCC (fd02, fd20), and the fd09 groups TAGE_UPD, UPD_PC and
# BE_REDIR.
#
# fst_names(fst) reads an FST's names; S is the scenarios and their
# groups; radix() is the display format of one signal.
import re
import subprocess


# ---------------------------------------------------------------------
# The FST's names: path without range -> (GTKWave name, width, Surfer
# name).
#
# The names are read from the FST header (fst2vcd, from the GTKWave
# distribution). GTKWave forms them as the scope path joined by '.', a
# struct of an array as '.[i].', and a vector's range appended; the
# path without the range is the key used in the lists below.
#
# Surfer (wellen) forms the same path, without the range, except for an
# element of an unpacked array: Verilator writes it as a scope named
# after the array holding variables <array>[i], and wellen names each
# variable [i], so GTKWave's a.a[0] is Surfer's a.[0].
# ---------------------------------------------------------------------
def fst_names(fst):
    hdr = subprocess.run(['fst2vcd', '-f', fst], capture_output=True,
                         text=True, check=True).stdout
    hdr = hdr[:hdr.index('$enddefinitions')]
    names = {}
    scope = []
    for line in hdr.split('\n'):
        w = line.split()
        if not w:
            continue
        if w[0] == '$scope':
            scope.append(w[2])
        elif w[0] == '$upscope':
            scope.pop()
        elif w[0] == '$var':
            width = int(w[2])
            nm = w[4]
            rng = w[5] if w[5] != '$end' else ''
            if width > 1 and not rng:
                rng = '[%d:0]' % (width - 1)
            # GTKWave names a 1-bit signal and an int or integer without
            # a range.
            if width == 1 or w[1] in ('int', 'integer'):
                rng = ''
            base = '.'.join(scope + [nm])
            snm = nm
            if scope:
                m = re.fullmatch(re.escape(scope[-1]) + r'(\[\d+\])', nm)
                if m:
                    snm = m.group(1)
            names.setdefault(base, (base + rng, width,
                                    '.'.join(scope + [snm])))
    return names


# Display format: 1 bit binary; addresses, data and targets hex; small
# fields decimal. 'bin', 'hex' or 'dec'.
def radix(width, path):
    if width == 1:
        return 'bin'
    if width > 8 or re.search(r'(pc|addr|target|paddr|data|vpn|ppn|instr|'
                              r'_va|tgt|cmp|swap)', path.split('.')[-1]):
        return 'hex'
    return 'dec'


# ---------------------------------------------------------------------
# Signal sets, by unit. D is fe_top's scope.
# ---------------------------------------------------------------------
D = 'tb.dut'
B = D + '.u_bpu'
Q = D + '.u_ftq'
I = D + '.u_ifu'
L = D + '.u_l1i'
SLOT = ['slot_valid', 'br_type', 'pos', 'taken', 'target', 'pred_src']


def slots(arr, n=2):
    return ['%s.[%d].%s' % (arr, s, f) for s in range(n) for f in SLOT]


def redir(arr):
    return ['%s.[%d].%s' % (arr, s, f) for s in range(2)
            for f in ('valid', 'target_pc')]


CLK = ['tb.clk', 'tb.rstn', 'tb.cyc']
BPU_P0 = [D + '.ftq_pred_val_p0', D + '.ftq_pred_pc_p0',
          D + '.ftq_pred_idx_p0', Q + '.u_npc.w_hold']
BPU_P1 = [D + '.bpu_pred_val_p1', D + '.bpu_pred_idx_p1',
          B + '.r_ubtb_blk_p1.hit', D + '.bpu_pred_pft_p1'] + \
    slots(D + '.bpu_pred_slot_p1')
BPU_P2 = [B + '.r_val_p2', D + '.bpu_slot_val_p2', D + '.bpu_slot_idx_p2',
          B + '.w_ftb_valid_p2'] + slots(D + '.bpu_slot_p2') + \
    redir(D + '.bpu_redir_p2') + [D + '.bpu_redir_idx_p2']
BPU_P3 = [B + '.r_val_p3', D + '.bpu_slot_val_p3', D + '.bpu_slot_idx_p3'] + \
    slots(D + '.bpu_slot_p3') + redir(D + '.bpu_redir_p3') + \
    [D + '.bpu_redir_idx_p3']
FTQ = [Q + '.w_ok_pred_p1', Q + '.w_ok_slot_p2', Q + '.w_ok_slot_p3',
       Q + '.w_ok_redir_p2', Q + '.w_ok_redir_p3', Q + '.w_redir_val',
       Q + '.w_redir_idx', Q + '.w_commit_ptr', D + '.ftq_full',
       D + '.ftq_empty']
FTQ_IFU = [D + '.ftq_ifu_req_val', D + '.ftq_ifu_req_rdy', D + '.ftq_ifu_idx',
           D + '.ftq_ifu_start_pc', D + '.ftq_ifu_next_pc',
           D + '.ftq_ifu_taken_val', D + '.ftq_ifu_taken_pos',
           D + '.ftq_ifu_flush_val', D + '.ftq_ifu_flush_idx',
           D + '.ftq_ifu_commit_ptr']
IFU_L1I = [D + '.ifu_l1i_req_val', D + '.ifu_l1i_req_rdy',
           D + '.ifu_l1i_req_id', D + '.ifu_l1i_req_paddr',
           D + '.ifu_l1i_req_uncached', D + '.l1i_ifu_rsp_val',
           D + '.l1i_ifu_rsp_id']
IFU_F3 = [D + '.ifu_ftq_pdwb_val', D + '.ifu_ftq_pdwb_idx',
          D + '.ifu_ftq_cfi_val', D + '.ifu_ftq_cfi_pos',
          D + '.ifu_ftq_mis_val', D + '.ifu_ftq_mis_pos',
          D + '.ifu_ftq_target', Q + '.w_pd_redir_val']
IBUF = [D + '.ifu_ibuf_val', D + '.ifu_ibuf_en', D + '.ibuf_ifu_rdy']
DEC = ['tb.dec_ibuf_rdy'] + ['tb.pd_out.[%d].%s' % (i, f) for i in range(8)
                             for f in ('valid', 'start_pc')]
DEC0 = ['tb.dec_ibuf_rdy', 'tb.pd_out.[0].valid', 'tb.pd_out.[0].start_pc',
        'tb.pd_out.[0].ftq_idx', 'tb.pd_out.[0].pos', 'tb.pd_out.[0].instr',
        'tb.pd_out.[0].is_rvc', 'tb.pd_out.[0].fault_cause',
        'tb.pd_out.[0].fault_va']
BACKEND = ['tb.bkend_ftq_redir_val', 'tb.bkend_ftq_redir_idx',
           'tb.bkend_ftq_redir_pc', 'tb.bkend_ftq_redir_cause',
           'tb.bkend_ftq_redir_self', 'tb.bkend_ftq_rsv_val',
           'tb.bkend_ftq_commit_val', 'tb.bkend_ftq_commit_idx']
ROLLBACK = [D + '.ftq_rollback_val', D + '.ftq_rollback_idx',
            D + '.ftq_rollback_corr', D + '.bpu_ghist_ptr',
            D + '.ras_restore_val', D + '.ras_restore_snapshot.tosr',
            D + '.ras_restore_snapshot.tosw', D + '.ras_restore_snapshot.bos']
RAS = [B + '.u_ras.tosr', B + '.u_ras.tosw', B + '.u_ras.bos',
       B + '.u_ras.ras_rst_done'] + \
    ['%s.w_ras_pred_val_p2.w_ras_pred_val_p2[%d]' % (B, s)
     for s in range(2)] + \
    ['%s.w_br_type_p2.w_br_type_p2[%d]' % (B, s) for s in range(2)] + \
    ['%s.u_ras.spec_ret_addr.spec_ret_addr[%d]' % (B, i) for i in range(4)] + \
    ['%s.u_ras.spec_rctr.spec_rctr[%d]' % (B, i) for i in range(4)]
RAS_CMT = [D + '.ras_commit_val', D + '.ras_commit_br_type',
           D + '.ras_commit_ret_addr', B + '.u_ras.csp',
           B + '.u_ras.commit_top_valid', B + '.u_ras.commit_top_addr']
TC = B + '.u_tage.u_tage_cntrl'
TAGE_P2 = [B + '.w_tage_pred_rdy_p2'] + \
    ['%s.tage_pred_meta_p2.[%d].%s' % (TC, s, f) for s in range(2)
     for f in ('tage_prm_comp', 'tage_alt_comp', 'tage_using_primary',
               'tage_prm_ctr', 'tage_pred_tkn')]
TAGE_UPD = [TC + '.trx_type', TC + '.tage_upd_val_u0'] + \
    ['%s.tage_upd_inp_u0.[%d].%s' % (TC, s, f) for s in range(2)
     for f in ('cond_mispredict', 'resolved_taken',
               'tage_pred_meta.tage_prm_comp', 'tage_pred_meta.tage_alt_comp',
               'tage_pred_meta.tage_pred_weak', 'tage_pred_meta.tage_prm_tkn',
               'tage_pred_meta.tage_alt_tkn')] + \
    ['%s.u_alc_wr.u_alc_wr[%d]' % (TC, s) for s in range(2)] + \
    ['%s.u_alc_comp.u_alc_comp[%d]' % (TC, s) for s in range(2)] + \
    ['%s.uaon.uaon[%d]' % (TC, s) for s in range(2)]
# The address of the branch each update slot carries. The TAGE update
# input has no address; ftq_upd_conv forms every predictor's update from
# one record in the same cycle, and the loop predictor's copy carries it.
UPD_PC = ['%s.u_upd_conv.lp_upd_p0.[%d].pc' % (Q, s) for s in range(2)]
BE_REDIR = ['tb.bkend_ftq_redir_val', 'tb.bkend_ftq_redir_pc',
            'tb.bkend_ftq_redir_cause']
SC_P3 = [B + '.w_sc_pred_rdy_p3'] + \
    ['%s.w_sc_hit_p3.w_sc_hit_p3[%d]' % (B, s) for s in range(2)] + \
    ['%s.w_taken_p3.w_taken_p3[%d]' % (B, s) for s in range(2)]
ITT_P2 = [B + '.w_ittage_pred_rdy_p2'] + \
    ['%s.w_ittage_pred_meta_p2.[%d].%s' % (B, s, f) for s in range(2)
     for f in ('ittage_hit', 'ittage_prm_comp', 'ittage_prm_tgt')]
UPDATES = ['tb.bkend_ftq_rsv_val', 'tb.ftq_bkend_rsv_rdy',
           B + '.w_lp_upd_val_p0', B + '.w_tage_upd_val_u0',
           B + '.w_ittage_upd_val_u0', B + '.w_sc_upd_val_u0',
           D + '.bpu_tage_upd_rdy', B + '.w_ras_commit_val'] + \
    ['%s.w_ubtb_upd_u0.[%d].valid' % (B, s) for s in range(2)]
FTB_UPD = [D + '.ftb_upd_valid_u0', D + '.ftb_upd_pc_u0',
           D + '.ftb_upd_hit_u0', D + '.ftb_upd_is_br_u0',
           D + '.ftb_upd_taken_u0', D + '.ftb_upd_is_jmp_u0',
           Q + '.u_npc.h3_ftb_upd']
L1I = [L + '.b_rsp_valid.b_rsp_valid[0]', L + '.b_rsp_valid.b_rsp_valid[1]',
       L + '.b_mis_valid.b_mis_valid[0]', L + '.b_mis_valid.b_mis_valid[1]',
       L + '.u_mshr.mrg_hit'] + \
    ['%s.u_mshr.e_val.e_val[%d]' % (L, m) for m in range(4)] + \
    ['%s.u_mshr.e_got.e_got[%d]' % (L, m) for m in range(4)] + \
    ['tb.l1i_mem_a_valid', 'tb.l1i_mem_a_address', 'tb.l1i_mem_a_source',
     'tb.l1i_mem_d_valid', 'tb.l1i_mem_d_source',
     L + '.u_mshr.b_fil_valid.b_fil_valid[0]',
     L + '.u_mshr.b_fil_valid.b_fil_valid[1]']
ITLB = [D + '.ifu_itlb_req_val', D + '.ifu_itlb_req_rdy', D + '.ifu_itlb_vpn',
        D + '.itlb_ifu_rsp_val', D + '.itlb_ifu_status', D + '.itlb_ifu_ppn',
        D + '.itlb_ifu_cause']
WALK = ['tb.itlb_l2t_req_val', 'tb.itlb_l2t_req_rdy', 'tb.itlb_l2t_vpn',
        'tb.itlb_l2t_v', 'tb.itlb_l2t_priv', 'tb.u_ptw.r_st', 'tb.u_ptw.r_g_on',
        'tb.l2t_itlb_rsp_val', 'tb.l2t_itlb_status', 'tb.l2t_itlb_ppn']
WALK_MEM = ['tb.ptw_mem_req_val', 'tb.ptw_mem_req_rdy', 'tb.ptw_mem_req_op',
            'tb.ptw_mem_req_paddr', 'tb.ptw_mem_req_cmp',
            'tb.ptw_mem_req_swap', 'tb.mem_ptw_rsp_val', 'tb.mem_ptw_rsp_data']
XQ = [I + '.u_xlate.xq_val', I + '.u_xlate.xq_pop', I + '.u_xlate.xq_idx',
      I + '.u_xlate.xq_pc', I + '.u_xlate.xq_cross', I + '.u_xlate.xq_ppn0',
      I + '.u_xlate.xq_ppn1', I + '.u_xlate.xq_fault0',
      I + '.u_xlate.xq_fault1', I + '.u_xlate.xq_uc']
FAULT = [D + '.ifu_ftq_fault_val', D + '.ifu_ftq_fault_pos']
MAINT = ['tb.cmt_ifu_maint_val', 'tb.cmt_ifu_maint_rdy', 'tb.cmt_ifu_maint_op',
         'tb.cmt_ifu_maint_paddr', I + '.u_maint.r_st',
         D + '.ifu_l1i_inv_val', D + '.ifu_l1i_inv_rdy', D + '.ifu_l1i_inv_all',
         D + '.ifu_l1i_inv_paddr', L + '.u_maint.r_st', L + '.mt_busy_any',
         L + '.mt_busy_line', D + '.l1i_ifu_inv_done', 'tb.ifu_cmt_maint_ack']
INIT = [B + '.u_tage.u_sram_init.state', B + '.u_tage.u_sram_init.waddr',
        D + '.bpu_tage_rdy', B + '.u_ittage.u_sram_init.state',
        B + '.u_ittage.u_sram_init.waddr', D + '.bpu_ittage_rdy',
        B + '.u_sc.u_sram_init.state', B + '.u_sc.u_sram_init.waddr',
        D + '.bpu_sc_ready', B + '.u_ras.ras_rst_done']
FIRST = [D + '.ftq_pred_val_p0', D + '.bpu_pred_val_p1', Q + '.w_ok_pred_p1',
         B + '.w_tage_pred_rdy_p2', B + '.w_ittage_pred_rdy_p2',
         B + '.w_sc_pred_rdy_p3']
FTQ_PTR = [Q + '.w_commit_ptr', D + '.ftq_full', D + '.ftq_empty',
           D + '.ftq_pred_idx_p0', D + '.ftq_ifu_idx']
IBUF_OCC = IBUF + [D + '.u_ibuf.r_count', D + '.u_ibuf.w_n_pres',
                  D + '.u_ibuf.w_n_pop']
# The loop predictor's per-slot answer at p1 and p2.
LP_PRED = ['%s.w_lp_pred_%s.[%d].%s' % (B, p, s, f) for p in ('p1', 'p2')
           for s in range(2)
           for f in ('lp_hit', 'lp_pred_is_loop', 'lp_pred_taken', 'lp_conf',
                     'lp_past_itr', 'lp_curs')]
# F3's straddle register: the first half of a 32-bit instruction that
# ends a block, held for the next block.
F3_STRAD = [I + '.u_f3.r_strad_val', I + '.u_f3.r_strad_pc',
            I + '.u_f3.r_strad_idx']
# ifu_fetch's commit gate on an uncached block.
FETCH_UC = [I + '.u_fetch.xq_uc', I + '.u_fetch.w_uc_gate']

# ---------------------------------------------------------------------
# The scenarios: (name, [(group, signals), ...]) in pipeline order.
# ---------------------------------------------------------------------
S = [
    ('fd01_reset_init', [('clock', CLK), ('sram_init', INIT),
                         ('bp_cluster_first', FIRST),
                         ('bp_cluster_p0', BPU_P0)]),
    ('fd02_steady', [('clock', CLK), ('bp_cluster_p0', BPU_P0),
                     ('bp_cluster_p1', BPU_P1), ('ftq', FTQ),
                     ('ftq_ifu', FTQ_IFU), ('ifu_l1i', IFU_L1I),
                     ('ifu_f3', IFU_F3), ('ibuf', IBUF_OCC), ('decode', DEC)]),
    ('fd03_two_branch', [('clock', CLK), ('bp_cluster_p1_ubtb', BPU_P1),
                         ('bp_cluster_p2_ftb', BPU_P2), ('ftq', FTQ)]),
    ('fd04_p2_override', [('clock', CLK), ('bp_cluster_p1_ubtb', BPU_P1),
                          ('bp_cluster_p2_ftb', BPU_P2), ('ftq', FTQ),
                          ('bp_cluster_p0', BPU_P0)]),
    ('fd05_p3_override', [('clock', CLK), ('tage_p2', TAGE_P2),
                          ('bp_cluster_p2', BPU_P2), ('sc_p3', SC_P3),
                          ('bp_cluster_p3', BPU_P3), ('ftq', FTQ)]),
    ('fd06_loop_pred', [('clock', CLK), ('bp_cluster_p1', BPU_P1),
                        ('loop_pred_p1_p2', LP_PRED),
                        ('bp_cluster_p2', BPU_P2), ('ftq', FTQ),
                        ('loop_pred_update', [B + '.w_lp_upd_val_p0']),
                        ('decode', DEC0)]),
    ('fd07_calls_returns', [('clock', CLK), ('bp_cluster_p1', BPU_P1),
                            ('ras', RAS), ('bp_cluster_p2', BPU_P2),
                            ('ftq', FTQ), ('ras_commit', RAS_CMT)]),
    ('fd08_indirect', [('clock', CLK), ('ittage_p2', ITT_P2),
                       ('bp_cluster_p2', BPU_P2), ('ftq', FTQ)]),
    ('fd09_tage', [('clock', CLK), ('tage_p2', TAGE_P2),
                   ('bp_cluster_p2', BPU_P2), ('backend', BE_REDIR),
                   ('ftq_upd_conv', UPD_PC), ('tage_update', TAGE_UPD)]),
    ('fd10_pd_redirect', [('clock', CLK), ('ftq_ifu', FTQ_IFU),
                          ('ifu_f3', IFU_F3), ('ftq', FTQ),
                          ('bp_cluster_p0', BPU_P0)]),
    ('fd11_be_mispredict', [('clock', CLK), ('decode', DEC0),
                            ('backend', BACKEND), ('ftq', FTQ),
                            ('ftq_ifu', FTQ_IFU), ('bp_history_ras',
                                                   ROLLBACK),
                            ('bp_cluster_p0', BPU_P0)]),
    ('fd12_training', [('clock', CLK), ('backend', BACKEND),
                       ('ftq_upd_conv', UPDATES), ('ftb_update', FTB_UPD),
                       ('bp_cluster_p0', BPU_P0)]),
    ('fd13_l1i', [('clock', CLK), ('ftq_ifu', FTQ_IFU), ('ifu_l1i', IFU_L1I),
                  ('l1i', L1I)]),
    ('fd14_translation', [('clock', CLK), ('ifu_xlate', XQ), ('itlb', ITLB),
                          ('walker', WALK), ('walker_mem', WALK_MEM)]),
    ('fd15_faults', [('clock', CLK), ('itlb', ITLB), ('walker', WALK),
                     ('ifu_xlate', XQ), ('ifu_fault', FAULT),
                     ('decode', DEC0), ('backend', BACKEND)]),
    ('fd16_page_cross', [('clock', CLK), ('ftq_ifu', FTQ_IFU),
                         ('ifu_xlate', XQ), ('itlb', ITLB),
                         ('ifu_l1i', IFU_L1I), ('decode', DEC0)]),
    ('fd17_rvc', [('clock', CLK), ('ftq_ifu', FTQ_IFU), ('ifu_f3', IFU_F3),
                  ('ifu_f3_straddle', F3_STRAD), ('ibuf', IBUF),
                  ('decode', DEC0 + ['tb.pd_out.[%d].%s' % (i, f)
                                     for i in range(1, 8)
                                     for f in ('valid', 'start_pc',
                                               'is_rvc')])]),
    ('fd18_uncached', [('clock', CLK), ('ftq_ifu', FTQ_IFU),
                       ('ifu_xlate', XQ), ('ifu_fetch', FETCH_UC),
                       ('ifu_l1i', IFU_L1I), ('l1i', L1I),
                       ('backend', BACKEND), ('decode', DEC0)]),
    ('fd19_fencei_cbo', [('clock', CLK), ('backend', BACKEND),
                         ('maintenance', MAINT), ('ftq_ifu', FTQ_IFU),
                         ('ifu_l1i', IFU_L1I)]),
    ('fd20_backpressure', [('clock', CLK), ('bp_cluster_p0', BPU_P0),
                           ('ftq', FTQ_PTR), ('ftq_ifu', FTQ_IFU),
                           ('ibuf', IBUF_OCC), ('decode', DEC0)]),
    ('fd21_commit', [('clock', CLK), ('backend', BACKEND),
                     ('ftq', FTQ_PTR), ('ras_commit', RAS_CMT),
                     ('ras', RAS)]),
]
