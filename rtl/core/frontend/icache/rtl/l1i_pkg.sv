// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//--------------------------------------------------------------------
// FILE:      l1i_pkg.sv
// COPIED     from the cgen emission, tools/cachegen/output/
//            l1i (BP-123; cachegen_decisions.md CG-4, CG-D1).
//            The pacino L1I is this copy and is changed here; the
//            emission's DO NOT HAND EDIT note belongs to the
//            emission. A file changed by BP-123 says so in a
//            PACINO CHANGES note.
// TOOL:      cgen 0.1.0
// SOURCE:    system 'pacino', from pacino_system.json
//--------------------------------------------------------------------
// Node 'l1i', icache.
//
// Every number below was DERIVED by cgen from the configuration.
// None of them appears in the input, D-37. The address
// decomposition is built once here and read by the cache
// control, the testbench and the self checking tests, D-39.
//--------------------------------------------------------------------
package l1i_pkg;

  // A generated package states the whole derived geometry and
  // one module consumes a subset of it. The constants are the
  // artifact, so UNUSEDPARAM is off across the package.
  /* verilator lint_off UNUSEDPARAM */

  // ----------------------------------------------------------------
  // Geometry
  // ----------------------------------------------------------------
  localparam int unsigned L1iPaBits        = 36;
  localparam int unsigned L1iCapacityBytes = 65536;
  localparam int unsigned L1iLineBytes     = 64;
  localparam int unsigned L1iLineBits      = 512;
  localparam int unsigned L1iWays          = 8;
  localparam int unsigned L1iBanks         = 2;
  localparam int unsigned L1iSets          = 128;
  localparam int unsigned L1iSetsPerBank   = 64;
  localparam int unsigned L1iBytesPerWay   = 8192;

  // ----------------------------------------------------------------
  // Address decomposition, D-39. offset + index + tag == pa_bits,
  // which is what leaves a bank select no room of its own.
  // ----------------------------------------------------------------
  localparam int unsigned L1iOffsetBits    = 6;
  localparam int unsigned L1iIndexBits     = 7;
  localparam int unsigned L1iTagBits       = 23;
  localparam int unsigned L1iBankBits      = 1;
  localparam int unsigned L1iSetIdxBits    = 6;
  localparam int unsigned L1iWayBits       = 3;

  localparam int unsigned L1iOffsetLsb     = 0;
  localparam int unsigned L1iOffsetMsb     = 5;
  localparam int unsigned L1iIndexLsb      = 6;
  localparam int unsigned L1iIndexMsb      = 12;
  localparam int unsigned L1iTagLsb        = 13;
  localparam int unsigned L1iTagMsb        = 35;

  // R-7. The bank select. The index already spans the whole set
  // space, so the select is taken OUT of the index rather than
  // sitting beside it. bank_interleave_granularity is line,
  // so consecutive lines alternate banks and the select is the
  // 1 bits IMMEDIATELY ABOVE THE OFFSET. The set index
  // is what is left of the index, above the select.
  localparam int unsigned L1iBankLsb       = 6;
  localparam int unsigned L1iBankMsb       = 6;
  localparam int unsigned L1iSetIdxLsb     = 7;
  localparam int unsigned L1iSetIdxMsb     = 12;

  // ----------------------------------------------------------------
  // R-7. THE OFFSET UNIT IS THE BYTE. The offset field of an
  // address is a byte offset within the line.
  //
  // L1iAddrUnitBytes is the size of ONE ADDRESS UNIT in bytes.
  // It is 1, which is byte addressing. Every word count and
  // every word index below derives from it and from nothing
  // else, so reversing this design to word based addressing
  // is one edit, on the L1iAddrUnitBytes line, in this one file.
  // ----------------------------------------------------------------
  localparam int unsigned L1iAddrUnitBytes = 1;

  localparam int unsigned L1iWordBytes     = 64;
  localparam int unsigned L1iWordBits      = L1iWordBytes * 8;
  localparam int unsigned L1iWordsPerLine  = L1iLineBytes / L1iWordBytes;
  // one word IS one whole line, so there is no word index
  localparam int unsigned L1iWordIdxBits   = 0;
  localparam int unsigned L1iWordIdxLsb =
      $clog2(L1iWordBytes / L1iAddrUnitBytes);
  localparam int unsigned L1iWordIdxMsb    = L1iWordIdxLsb;

  localparam int unsigned L1iBeatBits      = 256;
  localparam int unsigned L1iBeatBytes     = 32;
  localparam int unsigned L1iBeats         = 2;
  localparam int unsigned L1iBeatIdxBits =
      $clog2(L1iBeats) > 0 ? $clog2(L1iBeats) : 1;

  // ----------------------------------------------------------------
  // Miss handling. The core link declares 16 outstanding
  // requests against 16 registers, so one register can be
  // held by every request that could be in flight and none
  // of them is unreachable.
  // ----------------------------------------------------------------
  localparam int unsigned L1iMshrs         = 16;
  localparam int unsigned L1iMshrTargets   = 4;
  localparam int unsigned L1iMshrIdxBits   = 4;
  localparam int unsigned L1iMshrTgtBits   = 2;
  localparam int unsigned L1iMshrCntBits   = 5;
  localparam int unsigned L1iReqIdBits     = 4;
  localparam int unsigned L1iMaxOutstanding = 16;
  // the registers a request carrying the 'prefetch' qualifier
  // must leave free. It is the only place the bit is read.
  localparam int unsigned L1iQualReserve   = 2;

  // ----------------------------------------------------------------
  // Pipeline. Stage 0 is the cycle the access is accepted
  // and its set is presented to the arrays. The tag compare
  // is in stage 1, which is tag_compare_stage next_cycle,
  // and the answer is registered out after it. 0 stages of the
  // 2 carry the answer and do nothing else.
  // ----------------------------------------------------------------
  localparam int unsigned L1iReadLatency   = 2;
  localparam int unsigned L1iCmpStage      = 1;
  localparam int unsigned L1iPipePad       = 0;

  // ----------------------------------------------------------------
  // Types
  // ----------------------------------------------------------------
  typedef logic [L1iPaBits-1:0]     l1i_addr_t;
  typedef logic [L1iTagBits-1:0]    l1i_tag_t;
  typedef logic [L1iSetIdxBits-1:0] l1i_set_t;
  typedef logic [L1iWayBits-1:0]    l1i_way_t;
  typedef logic [L1iLineBits-1:0]   l1i_line_t;
  typedef logic [L1iWordBits-1:0]   l1i_word_t;
  typedef logic [L1iBeatBits-1:0]   l1i_beat_t;
  typedef logic [L1iBankBits-1:0]   l1i_bank_t;
  typedef logic [L1iMshrIdxBits-1:0] l1i_mshr_t;
  typedef logic [L1iReqIdBits-1:0]   l1i_req_id_t;
  typedef logic [L1iMshrTargets-1:0] l1i_tgt_vec_t;

  // ----------------------------------------------------------------
  // The decomposition itself. Written as a shift and a cast
  // rather than a part select on purpose: a part select inside a
  // function leaves the other bits of the argument unread, and
  // that draws an UNUSEDSIGNAL warning from the linter. The
  // two forms are the same hardware.
  // ----------------------------------------------------------------
  function automatic l1i_tag_t l1i_tag_of(input l1i_addr_t a);
    l1i_tag_of = l1i_tag_t'((a & {L1iPaBits{1'b1}}) >> L1iTagLsb);
  endfunction

  function automatic l1i_set_t l1i_set_of(input l1i_addr_t a);
    l1i_set_of = l1i_set_t'((a & {L1iPaBits{1'b1}}) >> L1iSetIdxLsb);
  endfunction

  function automatic l1i_bank_t l1i_bank_of(input l1i_addr_t a);
    l1i_bank_of = l1i_bank_t'((a & {L1iPaBits{1'b1}}) >> L1iBankLsb);
  endfunction

  function automatic logic [L1iOffsetBits-1:0]
      l1i_offset_of(input l1i_addr_t a);
    l1i_offset_of = L1iOffsetBits'((a & {L1iPaBits{1'b1}}) >> L1iOffsetLsb);
  endfunction

  // The word index is zero bits wide, so every address
  // selects word 0. The function is kept so that a
  // consumer does not branch on the geometry, and the
  // argument is read so the linter does not report the
  // other bits unread.
  function automatic logic l1i_word_of(input l1i_addr_t a);
    l1i_word_of = 1'b0 & (|(a & {L1iPaBits{1'b1}}));
  endfunction

  // the line this address falls in, offset cleared
  function automatic l1i_addr_t l1i_line_base(input l1i_addr_t a);
    l1i_line_base = ((a & {L1iPaBits{1'b1}}) >> L1iOffsetBits) << L1iOffsetBits;
  endfunction

  // the address a tag and a set stand for, the inverse of
  // l1i_tag_of and l1i_set_of. A writeback needs it.
  function automatic l1i_addr_t l1i_line_addr
      (input l1i_tag_t t, input l1i_bank_t b, input l1i_set_t s);
    l1i_line_addr = (l1i_addr_t'(t) << L1iTagLsb)
              | (l1i_addr_t'(b) << L1iBankLsb)
              | (l1i_addr_t'(s) << L1iSetIdxLsb);
  endfunction

  // ----------------------------------------------------------------
  // Replacement, policy tree_plru, 8 ways.
  //
  // Built by cgen and emitted here so that the cache control, the
  // testbench and the self checking tests all read one encoding.
  // D-39, generated not transcribed.
  // ----------------------------------------------------------------
  localparam int unsigned L1iReplBits = 7;

  typedef logic [L1iReplBits-1:0] l1i_repl_state_t;

  localparam l1i_repl_state_t L1iReplReset = '0;

  localparam int unsigned L1iReplStates = 128;

  // The victim of every state, and the state that every touch
  // leaves. Both filled by cgen from the one walk, so a consumer
  // cannot hold a different encoding from the one the tool used.
  localparam l1i_way_t L1iReplVictimTable [0:L1iReplStates-1] = '{
    3'd0, 3'd4, 3'd2, 3'd4, 3'd0, 3'd6, 3'd2, 3'd6, 3'd1, 3'd4, 3'd2,
    3'd4, 3'd1, 3'd6, 3'd2, 3'd6, 3'd0, 3'd4, 3'd3, 3'd4, 3'd0, 3'd6,
    3'd3, 3'd6, 3'd1, 3'd4, 3'd3, 3'd4, 3'd1, 3'd6, 3'd3, 3'd6, 3'd0,
    3'd5, 3'd2, 3'd5, 3'd0, 3'd6, 3'd2, 3'd6, 3'd1, 3'd5, 3'd2, 3'd5,
    3'd1, 3'd6, 3'd2, 3'd6, 3'd0, 3'd5, 3'd3, 3'd5, 3'd0, 3'd6, 3'd3,
    3'd6, 3'd1, 3'd5, 3'd3, 3'd5, 3'd1, 3'd6, 3'd3, 3'd6, 3'd0, 3'd4,
    3'd2, 3'd4, 3'd0, 3'd7, 3'd2, 3'd7, 3'd1, 3'd4, 3'd2, 3'd4, 3'd1,
    3'd7, 3'd2, 3'd7, 3'd0, 3'd4, 3'd3, 3'd4, 3'd0, 3'd7, 3'd3, 3'd7,
    3'd1, 3'd4, 3'd3, 3'd4, 3'd1, 3'd7, 3'd3, 3'd7, 3'd0, 3'd5, 3'd2,
    3'd5, 3'd0, 3'd7, 3'd2, 3'd7, 3'd1, 3'd5, 3'd2, 3'd5, 3'd1, 3'd7,
    3'd2, 3'd7, 3'd0, 3'd5, 3'd3, 3'd5, 3'd0, 3'd7, 3'd3, 3'd7, 3'd1,
    3'd5, 3'd3, 3'd5, 3'd1, 3'd7, 3'd3, 3'd7
  };

  localparam l1i_repl_state_t
      L1iReplUpdateTable [0:L1iReplStates-1][0:L1iWays-1] = '{
    '{7'd11, 7'd3, 7'd17, 7'd1, 7'd36, 7'd4, 7'd64, 7'd0},
    '{7'd11, 7'd3, 7'd17, 7'd1, 7'd36, 7'd4, 7'd64, 7'd0},
    '{7'd11, 7'd3, 7'd17, 7'd1, 7'd38, 7'd6, 7'd66, 7'd2},
    '{7'd11, 7'd3, 7'd17, 7'd1, 7'd38, 7'd6, 7'd66, 7'd2},
    '{7'd15, 7'd7, 7'd21, 7'd5, 7'd36, 7'd4, 7'd64, 7'd0},
    '{7'd15, 7'd7, 7'd21, 7'd5, 7'd36, 7'd4, 7'd64, 7'd0},
    '{7'd15, 7'd7, 7'd21, 7'd5, 7'd38, 7'd6, 7'd66, 7'd2},
    '{7'd15, 7'd7, 7'd21, 7'd5, 7'd38, 7'd6, 7'd66, 7'd2},
    '{7'd11, 7'd3, 7'd25, 7'd9, 7'd44, 7'd12, 7'd72, 7'd8},
    '{7'd11, 7'd3, 7'd25, 7'd9, 7'd44, 7'd12, 7'd72, 7'd8},
    '{7'd11, 7'd3, 7'd25, 7'd9, 7'd46, 7'd14, 7'd74, 7'd10},
    '{7'd11, 7'd3, 7'd25, 7'd9, 7'd46, 7'd14, 7'd74, 7'd10},
    '{7'd15, 7'd7, 7'd29, 7'd13, 7'd44, 7'd12, 7'd72, 7'd8},
    '{7'd15, 7'd7, 7'd29, 7'd13, 7'd44, 7'd12, 7'd72, 7'd8},
    '{7'd15, 7'd7, 7'd29, 7'd13, 7'd46, 7'd14, 7'd74, 7'd10},
    '{7'd15, 7'd7, 7'd29, 7'd13, 7'd46, 7'd14, 7'd74, 7'd10},
    '{7'd27, 7'd19, 7'd17, 7'd1, 7'd52, 7'd20, 7'd80, 7'd16},
    '{7'd27, 7'd19, 7'd17, 7'd1, 7'd52, 7'd20, 7'd80, 7'd16},
    '{7'd27, 7'd19, 7'd17, 7'd1, 7'd54, 7'd22, 7'd82, 7'd18},
    '{7'd27, 7'd19, 7'd17, 7'd1, 7'd54, 7'd22, 7'd82, 7'd18},
    '{7'd31, 7'd23, 7'd21, 7'd5, 7'd52, 7'd20, 7'd80, 7'd16},
    '{7'd31, 7'd23, 7'd21, 7'd5, 7'd52, 7'd20, 7'd80, 7'd16},
    '{7'd31, 7'd23, 7'd21, 7'd5, 7'd54, 7'd22, 7'd82, 7'd18},
    '{7'd31, 7'd23, 7'd21, 7'd5, 7'd54, 7'd22, 7'd82, 7'd18},
    '{7'd27, 7'd19, 7'd25, 7'd9, 7'd60, 7'd28, 7'd88, 7'd24},
    '{7'd27, 7'd19, 7'd25, 7'd9, 7'd60, 7'd28, 7'd88, 7'd24},
    '{7'd27, 7'd19, 7'd25, 7'd9, 7'd62, 7'd30, 7'd90, 7'd26},
    '{7'd27, 7'd19, 7'd25, 7'd9, 7'd62, 7'd30, 7'd90, 7'd26},
    '{7'd31, 7'd23, 7'd29, 7'd13, 7'd60, 7'd28, 7'd88, 7'd24},
    '{7'd31, 7'd23, 7'd29, 7'd13, 7'd60, 7'd28, 7'd88, 7'd24},
    '{7'd31, 7'd23, 7'd29, 7'd13, 7'd62, 7'd30, 7'd90, 7'd26},
    '{7'd31, 7'd23, 7'd29, 7'd13, 7'd62, 7'd30, 7'd90, 7'd26},
    '{7'd43, 7'd35, 7'd49, 7'd33, 7'd36, 7'd4, 7'd96, 7'd32},
    '{7'd43, 7'd35, 7'd49, 7'd33, 7'd36, 7'd4, 7'd96, 7'd32},
    '{7'd43, 7'd35, 7'd49, 7'd33, 7'd38, 7'd6, 7'd98, 7'd34},
    '{7'd43, 7'd35, 7'd49, 7'd33, 7'd38, 7'd6, 7'd98, 7'd34},
    '{7'd47, 7'd39, 7'd53, 7'd37, 7'd36, 7'd4, 7'd96, 7'd32},
    '{7'd47, 7'd39, 7'd53, 7'd37, 7'd36, 7'd4, 7'd96, 7'd32},
    '{7'd47, 7'd39, 7'd53, 7'd37, 7'd38, 7'd6, 7'd98, 7'd34},
    '{7'd47, 7'd39, 7'd53, 7'd37, 7'd38, 7'd6, 7'd98, 7'd34},
    '{7'd43, 7'd35, 7'd57, 7'd41, 7'd44, 7'd12, 7'd104, 7'd40},
    '{7'd43, 7'd35, 7'd57, 7'd41, 7'd44, 7'd12, 7'd104, 7'd40},
    '{7'd43, 7'd35, 7'd57, 7'd41, 7'd46, 7'd14, 7'd106, 7'd42},
    '{7'd43, 7'd35, 7'd57, 7'd41, 7'd46, 7'd14, 7'd106, 7'd42},
    '{7'd47, 7'd39, 7'd61, 7'd45, 7'd44, 7'd12, 7'd104, 7'd40},
    '{7'd47, 7'd39, 7'd61, 7'd45, 7'd44, 7'd12, 7'd104, 7'd40},
    '{7'd47, 7'd39, 7'd61, 7'd45, 7'd46, 7'd14, 7'd106, 7'd42},
    '{7'd47, 7'd39, 7'd61, 7'd45, 7'd46, 7'd14, 7'd106, 7'd42},
    '{7'd59, 7'd51, 7'd49, 7'd33, 7'd52, 7'd20, 7'd112, 7'd48},
    '{7'd59, 7'd51, 7'd49, 7'd33, 7'd52, 7'd20, 7'd112, 7'd48},
    '{7'd59, 7'd51, 7'd49, 7'd33, 7'd54, 7'd22, 7'd114, 7'd50},
    '{7'd59, 7'd51, 7'd49, 7'd33, 7'd54, 7'd22, 7'd114, 7'd50},
    '{7'd63, 7'd55, 7'd53, 7'd37, 7'd52, 7'd20, 7'd112, 7'd48},
    '{7'd63, 7'd55, 7'd53, 7'd37, 7'd52, 7'd20, 7'd112, 7'd48},
    '{7'd63, 7'd55, 7'd53, 7'd37, 7'd54, 7'd22, 7'd114, 7'd50},
    '{7'd63, 7'd55, 7'd53, 7'd37, 7'd54, 7'd22, 7'd114, 7'd50},
    '{7'd59, 7'd51, 7'd57, 7'd41, 7'd60, 7'd28, 7'd120, 7'd56},
    '{7'd59, 7'd51, 7'd57, 7'd41, 7'd60, 7'd28, 7'd120, 7'd56},
    '{7'd59, 7'd51, 7'd57, 7'd41, 7'd62, 7'd30, 7'd122, 7'd58},
    '{7'd59, 7'd51, 7'd57, 7'd41, 7'd62, 7'd30, 7'd122, 7'd58},
    '{7'd63, 7'd55, 7'd61, 7'd45, 7'd60, 7'd28, 7'd120, 7'd56},
    '{7'd63, 7'd55, 7'd61, 7'd45, 7'd60, 7'd28, 7'd120, 7'd56},
    '{7'd63, 7'd55, 7'd61, 7'd45, 7'd62, 7'd30, 7'd122, 7'd58},
    '{7'd63, 7'd55, 7'd61, 7'd45, 7'd62, 7'd30, 7'd122, 7'd58},
    '{7'd75, 7'd67, 7'd81, 7'd65, 7'd100, 7'd68, 7'd64, 7'd0},
    '{7'd75, 7'd67, 7'd81, 7'd65, 7'd100, 7'd68, 7'd64, 7'd0},
    '{7'd75, 7'd67, 7'd81, 7'd65, 7'd102, 7'd70, 7'd66, 7'd2},
    '{7'd75, 7'd67, 7'd81, 7'd65, 7'd102, 7'd70, 7'd66, 7'd2},
    '{7'd79, 7'd71, 7'd85, 7'd69, 7'd100, 7'd68, 7'd64, 7'd0},
    '{7'd79, 7'd71, 7'd85, 7'd69, 7'd100, 7'd68, 7'd64, 7'd0},
    '{7'd79, 7'd71, 7'd85, 7'd69, 7'd102, 7'd70, 7'd66, 7'd2},
    '{7'd79, 7'd71, 7'd85, 7'd69, 7'd102, 7'd70, 7'd66, 7'd2},
    '{7'd75, 7'd67, 7'd89, 7'd73, 7'd108, 7'd76, 7'd72, 7'd8},
    '{7'd75, 7'd67, 7'd89, 7'd73, 7'd108, 7'd76, 7'd72, 7'd8},
    '{7'd75, 7'd67, 7'd89, 7'd73, 7'd110, 7'd78, 7'd74, 7'd10},
    '{7'd75, 7'd67, 7'd89, 7'd73, 7'd110, 7'd78, 7'd74, 7'd10},
    '{7'd79, 7'd71, 7'd93, 7'd77, 7'd108, 7'd76, 7'd72, 7'd8},
    '{7'd79, 7'd71, 7'd93, 7'd77, 7'd108, 7'd76, 7'd72, 7'd8},
    '{7'd79, 7'd71, 7'd93, 7'd77, 7'd110, 7'd78, 7'd74, 7'd10},
    '{7'd79, 7'd71, 7'd93, 7'd77, 7'd110, 7'd78, 7'd74, 7'd10},
    '{7'd91, 7'd83, 7'd81, 7'd65, 7'd116, 7'd84, 7'd80, 7'd16},
    '{7'd91, 7'd83, 7'd81, 7'd65, 7'd116, 7'd84, 7'd80, 7'd16},
    '{7'd91, 7'd83, 7'd81, 7'd65, 7'd118, 7'd86, 7'd82, 7'd18},
    '{7'd91, 7'd83, 7'd81, 7'd65, 7'd118, 7'd86, 7'd82, 7'd18},
    '{7'd95, 7'd87, 7'd85, 7'd69, 7'd116, 7'd84, 7'd80, 7'd16},
    '{7'd95, 7'd87, 7'd85, 7'd69, 7'd116, 7'd84, 7'd80, 7'd16},
    '{7'd95, 7'd87, 7'd85, 7'd69, 7'd118, 7'd86, 7'd82, 7'd18},
    '{7'd95, 7'd87, 7'd85, 7'd69, 7'd118, 7'd86, 7'd82, 7'd18},
    '{7'd91, 7'd83, 7'd89, 7'd73, 7'd124, 7'd92, 7'd88, 7'd24},
    '{7'd91, 7'd83, 7'd89, 7'd73, 7'd124, 7'd92, 7'd88, 7'd24},
    '{7'd91, 7'd83, 7'd89, 7'd73, 7'd126, 7'd94, 7'd90, 7'd26},
    '{7'd91, 7'd83, 7'd89, 7'd73, 7'd126, 7'd94, 7'd90, 7'd26},
    '{7'd95, 7'd87, 7'd93, 7'd77, 7'd124, 7'd92, 7'd88, 7'd24},
    '{7'd95, 7'd87, 7'd93, 7'd77, 7'd124, 7'd92, 7'd88, 7'd24},
    '{7'd95, 7'd87, 7'd93, 7'd77, 7'd126, 7'd94, 7'd90, 7'd26},
    '{7'd95, 7'd87, 7'd93, 7'd77, 7'd126, 7'd94, 7'd90, 7'd26},
    '{7'd107, 7'd99, 7'd113, 7'd97, 7'd100, 7'd68, 7'd96, 7'd32},
    '{7'd107, 7'd99, 7'd113, 7'd97, 7'd100, 7'd68, 7'd96, 7'd32},
    '{7'd107, 7'd99, 7'd113, 7'd97, 7'd102, 7'd70, 7'd98, 7'd34},
    '{7'd107, 7'd99, 7'd113, 7'd97, 7'd102, 7'd70, 7'd98, 7'd34},
    '{7'd111, 7'd103, 7'd117, 7'd101, 7'd100, 7'd68, 7'd96, 7'd32},
    '{7'd111, 7'd103, 7'd117, 7'd101, 7'd100, 7'd68, 7'd96, 7'd32},
    '{7'd111, 7'd103, 7'd117, 7'd101, 7'd102, 7'd70, 7'd98, 7'd34},
    '{7'd111, 7'd103, 7'd117, 7'd101, 7'd102, 7'd70, 7'd98, 7'd34},
    '{7'd107, 7'd99, 7'd121, 7'd105, 7'd108, 7'd76, 7'd104, 7'd40},
    '{7'd107, 7'd99, 7'd121, 7'd105, 7'd108, 7'd76, 7'd104, 7'd40},
    '{7'd107, 7'd99, 7'd121, 7'd105, 7'd110, 7'd78, 7'd106, 7'd42},
    '{7'd107, 7'd99, 7'd121, 7'd105, 7'd110, 7'd78, 7'd106, 7'd42},
    '{7'd111, 7'd103, 7'd125, 7'd109, 7'd108, 7'd76, 7'd104, 7'd40},
    '{7'd111, 7'd103, 7'd125, 7'd109, 7'd108, 7'd76, 7'd104, 7'd40},
    '{7'd111, 7'd103, 7'd125, 7'd109, 7'd110, 7'd78, 7'd106, 7'd42},
    '{7'd111, 7'd103, 7'd125, 7'd109, 7'd110, 7'd78, 7'd106, 7'd42},
    '{7'd123, 7'd115, 7'd113, 7'd97, 7'd116, 7'd84, 7'd112, 7'd48},
    '{7'd123, 7'd115, 7'd113, 7'd97, 7'd116, 7'd84, 7'd112, 7'd48},
    '{7'd123, 7'd115, 7'd113, 7'd97, 7'd118, 7'd86, 7'd114, 7'd50},
    '{7'd123, 7'd115, 7'd113, 7'd97, 7'd118, 7'd86, 7'd114, 7'd50},
    '{7'd127, 7'd119, 7'd117, 7'd101, 7'd116, 7'd84, 7'd112, 7'd48},
    '{7'd127, 7'd119, 7'd117, 7'd101, 7'd116, 7'd84, 7'd112, 7'd48},
    '{7'd127, 7'd119, 7'd117, 7'd101, 7'd118, 7'd86, 7'd114, 7'd50},
    '{7'd127, 7'd119, 7'd117, 7'd101, 7'd118, 7'd86, 7'd114, 7'd50},
    '{7'd123, 7'd115, 7'd121, 7'd105, 7'd124, 7'd92, 7'd120, 7'd56},
    '{7'd123, 7'd115, 7'd121, 7'd105, 7'd124, 7'd92, 7'd120, 7'd56},
    '{7'd123, 7'd115, 7'd121, 7'd105, 7'd126, 7'd94, 7'd122, 7'd58},
    '{7'd123, 7'd115, 7'd121, 7'd105, 7'd126, 7'd94, 7'd122, 7'd58},
    '{7'd127, 7'd119, 7'd125, 7'd109, 7'd124, 7'd92, 7'd120, 7'd56},
    '{7'd127, 7'd119, 7'd125, 7'd109, 7'd124, 7'd92, 7'd120, 7'd56},
    '{7'd127, 7'd119, 7'd125, 7'd109, 7'd126, 7'd94, 7'd122, 7'd58},
    '{7'd127, 7'd119, 7'd125, 7'd109, 7'd126, 7'd94, 7'd122, 7'd58}
  };

  function automatic l1i_way_t l1i_repl_victim(input l1i_repl_state_t s);
    l1i_repl_victim = L1iReplVictimTable[s];
  endfunction

  function automatic l1i_repl_state_t l1i_repl_update
      (input l1i_repl_state_t s, input l1i_way_t w);
    l1i_repl_update = L1iReplUpdateTable[s][w];
  endfunction

  /* verilator lint_on UNUSEDPARAM */

endpackage
