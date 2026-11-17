// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// cbp_trace.h -- pacino's own reader and writer of the CBP2025 trace
// record format (PERF-002, perf_decisions.md PF-1, PF-14).
//
// No CBP code is used (PF-1). The format is the one documented in
// tools/cbp2025/lib/trace_reader.h and tools/scan_traces.py:
//   PC 8 bytes, class 1 byte, little endian
//   load or store: effective address 8, size 1, base update 1, and
//                  for a store, register offset 1
//   branch:        taken 1, and when taken, target 8
//   input register count 1, one byte per input register
//   output register count 1, one byte per output register
//   one value per output register: 8 bytes for an integer register
//   (0-31, 64, 65), 16 bytes otherwise (SIMD, 32-63)
//
// COUNTING follows the CBP2025 simulator as scan_traces.py does, so the
// counts compare with reference_results_training_set.csv:
//   Instr        records
//   NumBr        conditional branch PIECES: one per output register, at
//                least one, plus one per SIMD output whose upper 8
//                bytes are not 0
//   50Perc       the trailing 1e6-record epochs whose record sum first
//                exceeds half the records
// ===================================================================
#ifndef PERF_CBP_TRACE_H
#define PERF_CBP_TRACE_H

#include <cstdint>
#include <string>
#include <vector>
#include <zlib.h>

namespace cbp {

// Instruction classes, sim_common_structs.h InstClass.
enum Cls : uint8_t {
  C_ALU = 0, C_LOAD = 1, C_STORE = 2, C_COND = 3, C_JMP_DIR = 4,
  C_JMP_IND = 5, C_FP = 6, C_SLOW = 7, C_UNDEF = 8, C_CALL_DIR = 9,
  C_CALL_IND = 10, C_RET = 11
};

inline bool is_branch(uint8_t c) {
  return c == C_COND || c == C_JMP_DIR || c == C_JMP_IND ||
         c == C_CALL_DIR || c == C_CALL_IND || c == C_RET;
}
inline bool is_direct(uint8_t c) {
  return c == C_COND || c == C_JMP_DIR || c == C_CALL_DIR;
}

// Value bytes of output register r: 8 integer, 16 SIMD.
inline int value_bytes(uint8_t r) {
  return (r < 32 || r == 64 || r == 65) ? 8 : 16;
}

constexpr uint64_t EPOCH_RECORDS = 1000000;  // CBP EPOCH_SIZE_INSTS
constexpr int      MAX_RECORD    = 8192;     // more than any record

// One record, decoded. raw points into the reader's buffer and is
// valid until the next call to next().
struct Rec {
  uint64_t       pc;
  uint8_t        cls;
  bool           taken;      // branches; false otherwise
  uint64_t       target;     // the taken target; pc + 4 when not taken
  uint32_t       target_off; // byte offset of the target in raw, or 0
  uint64_t       ea;         // load and store effective address
  uint8_t        nin;
  uint8_t        nout;
  uint32_t       pieces;     // a conditional's NumBr pieces, else 0
  const uint8_t* raw;
  uint32_t       len;
};

// A streaming reader of one .gz trace.
class Reader {
 public:
  Reader() = default;
  ~Reader() { close(); }
  Reader(const Reader&) = delete;
  Reader& operator=(const Reader&) = delete;

  bool open(const std::string& path);
  void close();
  // The next record into r; false at the end or on an error (err()).
  bool next(Rec& r);
  const std::string& err() const { return err_; }
  uint64_t records() const { return nrec_; }

 private:
  bool fill();
  gzFile               gz_ = nullptr;
  std::vector<uint8_t> buf_;
  size_t               pos_ = 0;
  size_t               end_ = 0;
  bool                 eof_ = false;
  uint64_t             nrec_ = 0;
  std::string          path_;
  std::string          err_;
};

// A .gz writer of raw records.
class Writer {
 public:
  ~Writer() { close(); }
  bool open(const std::string& path, int level);
  bool write(const uint8_t* p, size_t n);
  bool close();
  const std::string& err() const { return err_; }

 private:
  gzFile               gz_ = nullptr;
  std::vector<uint8_t> buf_;
  std::string          err_;
};

// The reference counts of one trace, accumulated record by record.
class Counts {
 public:
  void add(const Rec& r);
  void finish();
  uint64_t instr      = 0;
  uint64_t numbr      = 0;
  uint64_t half_instr = 0;
  uint64_t half_numbr = 0;
  // Every class's records, 0 to 11.
  uint64_t by_cls[12] = {};
  uint64_t cond_taken = 0;

 private:
  std::vector<uint64_t> ep_;   // conditional pieces per epoch
};

// SHA-256 of a file, lower-case hex; empty on a read error.
std::string sha256_file(const std::string& path);

// One line of a sha256sum list: the digest and the relative path.
struct ShaEntry {
  std::string sha;
  std::string rel;
  std::string group;   // the parent directory name
  std::string trace;   // the file name less .gz
};
// Read a sha256sum list; false with msg on a format error.
bool read_sha_list(const std::string& path, std::vector<ShaEntry>& out,
                   std::string& msg);

// The repository root: RVA_ROOT if set, else the directory above perf/
// found from argv0's path, else the current directory.
std::string repo_root(const char* argv0);
// The training traces' root (CBP_TRACES, default ../cbp_traces) and the
// changed traces' root (CBP_TRACES_RV, default ../cbp_traces_rv), both
// from the repository root (PF-14, PERF-002).
std::string traces_root(const std::string& repo);
std::string traces_rv_root(const std::string& repo);

// The README section every trace error names (PF-14).
extern const char* README_REF;

}  // namespace cbp

#endif  // PERF_CBP_TRACE_H
