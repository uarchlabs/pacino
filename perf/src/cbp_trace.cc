// ===================================================================
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
// ===================================================================
// cbp_trace.cc -- the CBP trace reader, writer, reference counts and
// SHA-256 (PERF-002). See cbp_trace.h.
// ===================================================================
#include "cbp_trace.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sys/stat.h>
#include <unistd.h>

namespace cbp {

const char* README_REF = "see README.md, section Performance analysis";

static constexpr size_t BUF_BYTES = 16u << 20;   // decompressed buffer

static inline uint64_t rd64(const uint8_t* p) {
  uint64_t v;
  std::memcpy(&v, p, 8);
  return v;
}

// -------------------------------------------------------------------
// Reader
// -------------------------------------------------------------------
bool Reader::open(const std::string& path) {
  close();
  path_ = path;
  err_.clear();
  gz_ = gzopen(path.c_str(), "rb");
  if (gz_ == nullptr) {
    err_ = path + ": cannot open";
    return false;
  }
  gzbuffer(gz_, 1u << 20);
  buf_.resize(BUF_BYTES + MAX_RECORD);
  pos_ = end_ = 0;
  eof_ = false;
  nrec_ = 0;
  return true;
}

void Reader::close() {
  if (gz_ != nullptr) gzclose(gz_);
  gz_ = nullptr;
}

// Move the unread tail to the front and read more.
bool Reader::fill() {
  size_t left = end_ - pos_;
  if (left != 0) std::memmove(buf_.data(), buf_.data() + pos_, left);
  pos_ = 0;
  end_ = left;
  while (!eof_ && end_ < BUF_BYTES) {
    int n = gzread(gz_, buf_.data() + end_, unsigned(BUF_BYTES - end_));
    if (n < 0) {
      int e;
      err_ = path_ + ": " + gzerror(gz_, &e);
      return false;
    }
    if (n == 0) {
      eof_ = true;
      break;
    }
    end_ += size_t(n);
  }
  return true;
}

bool Reader::next(Rec& r) {
  if (gz_ == nullptr) return false;
  if (!eof_ && end_ - pos_ < size_t(MAX_RECORD)) {
    if (!fill()) return false;
  }
  if (pos_ >= end_) return false;             // the end of the trace
  const uint8_t* b = buf_.data() + pos_;
  size_t avail = end_ - pos_;
  auto truncated = [&]() {
    err_ = path_ + ": truncated record " + std::to_string(nrec_);
    return false;
  };
  if (avail < 9) return truncated();
  r.pc = rd64(b);
  r.cls = b[8];
  r.taken = false;
  r.target = r.pc + 4;
  r.target_off = 0;
  r.ea = 0;
  r.pieces = 0;
  size_t p = 9;
  if (r.cls == C_UNDEF || r.cls > C_RET) {
    err_ = path_ + ": record " + std::to_string(nrec_) + " has class " +
           std::to_string(r.cls);
    return false;
  }
  if (r.cls == C_LOAD || r.cls == C_STORE) {
    if (avail < p + 11) return truncated();
    r.ea = rd64(b + p);
    p += (r.cls == C_LOAD) ? 10 : 11;
  } else if (is_branch(r.cls)) {
    if (avail < p + 1) return truncated();
    r.taken = b[p] != 0;
    p += 1;
    if (r.taken) {
      if (avail < p + 8) return truncated();
      r.target = rd64(b + p);
      r.target_off = uint32_t(p);
      p += 8;
    } else if (r.cls != C_COND) {
      err_ = path_ + ": record " + std::to_string(nrec_) +
             " is an unconditional branch not taken";
      return false;
    }
  }
  if (avail < p + 1) return truncated();
  r.nin = b[p];
  p += 1 + r.nin;
  if (avail < p + 1) return truncated();
  r.nout = b[p];
  size_t regs = p + 1;
  p = regs + r.nout;
  if (avail < p) return truncated();
  uint32_t simd_hi = 0;
  for (int i = 0; i < r.nout; i++) {
    int vb = value_bytes(b[regs + i]);
    if (avail < p + size_t(vb)) return truncated();
    if (vb == 16) {
      uint64_t hi = rd64(b + p + 8);
      if (hi != 0) simd_hi++;
    }
    p += size_t(vb);
  }
  if (r.cls == C_COND) r.pieces = (r.nout == 0) ? 1 : r.nout + simd_hi;
  r.raw = b;
  r.len = uint32_t(p);
  pos_ += p;
  nrec_++;
  return true;
}

// -------------------------------------------------------------------
// Writer
// -------------------------------------------------------------------
bool Writer::open(const std::string& path, int level) {
  char mode[8];
  std::snprintf(mode, sizeof(mode), "wb%d", level);
  gz_ = gzopen(path.c_str(), mode);
  if (gz_ == nullptr) {
    err_ = path + ": cannot create";
    return false;
  }
  gzbuffer(gz_, 1u << 20);
  return true;
}

bool Writer::write(const uint8_t* p, size_t n) {
  buf_.insert(buf_.end(), p, p + n);
  if (buf_.size() >= (4u << 20)) {
    if (gzwrite(gz_, buf_.data(), unsigned(buf_.size())) !=
        int(buf_.size())) {
      int e;
      err_ = gzerror(gz_, &e);
      return false;
    }
    buf_.clear();
  }
  return true;
}

bool Writer::close() {
  if (gz_ == nullptr) return true;
  bool ok = true;
  if (!buf_.empty() &&
      gzwrite(gz_, buf_.data(), unsigned(buf_.size())) != int(buf_.size()))
    ok = false;
  buf_.clear();
  if (gzclose(gz_) != Z_OK) ok = false;
  gz_ = nullptr;
  if (!ok && err_.empty()) err_ = "write failed";
  return ok;
}

// -------------------------------------------------------------------
// Counts
// -------------------------------------------------------------------
void Counts::add(const Rec& r) {
  if (r.cls < 12) by_cls[r.cls]++;
  if (r.cls == C_COND) {
    uint64_t e = instr / EPOCH_RECORDS;
    if (ep_.size() <= e) ep_.resize(e + 1, 0);
    ep_[e] += r.pieces;
    numbr += r.pieces;
    if (r.taken) cond_taken++;
  }
  instr++;
}

// The 50Perc window: walk back from the last epoch until the summed
// records exceed half the total (integer half, as bp.cc).
void Counts::finish() {
  uint64_t n_ep = (instr + EPOCH_RECORDS - 1) / EPOCH_RECORDS;
  if (ep_.size() < n_ep) ep_.resize(n_ep, 0);
  uint64_t half = instr / 2;
  half_instr = half_numbr = 0;
  for (uint64_t e = n_ep; e-- > 0;) {
    uint64_t in_ep = instr - e * EPOCH_RECORDS;
    half_instr += (in_ep < EPOCH_RECORDS) ? in_ep : EPOCH_RECORDS;
    half_numbr += ep_[e];
    if (half_instr > half) break;
  }
}

// -------------------------------------------------------------------
// SHA-256, FIPS 180-4
// -------------------------------------------------------------------
namespace {
const uint32_t K256[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

inline uint32_t ror(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

struct Sha256 {
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  uint8_t  blk[64];
  size_t   nblk = 0;
  uint64_t total = 0;

  void block(const uint8_t* p) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
      w[i] = (uint32_t(p[4 * i]) << 24) | (uint32_t(p[4 * i + 1]) << 16) |
             (uint32_t(p[4 * i + 2]) << 8) | uint32_t(p[4 * i + 3]);
    for (int i = 16; i < 64; i++) {
      uint32_t s0 = ror(w[i - 15], 7) ^ ror(w[i - 15], 18) ^ (w[i - 15] >> 3);
      uint32_t s1 = ror(w[i - 2], 17) ^ ror(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
    uint32_t e = h[4], f = h[5], g = h[6], k = h[7];
    for (int i = 0; i < 64; i++) {
      uint32_t s1 = ror(e, 6) ^ ror(e, 11) ^ ror(e, 25);
      uint32_t ch = (e & f) ^ (~e & g);
      uint32_t t1 = k + s1 + ch + K256[i] + w[i];
      uint32_t s0 = ror(a, 2) ^ ror(a, 13) ^ ror(a, 22);
      uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
      uint32_t t2 = s0 + mj;
      k = g; g = f; f = e; e = d + t1;
      d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += k;
  }

  void update(const uint8_t* p, size_t n) {
    total += n;
    if (nblk != 0) {
      while (n != 0 && nblk < 64) { blk[nblk++] = *p++; n--; }
      if (nblk == 64) { block(blk); nblk = 0; }
    }
    while (n >= 64) { block(p); p += 64; n -= 64; }
    while (n != 0) { blk[nblk++] = *p++; n--; }
  }

  std::string hex() {
    uint64_t bits = total * 8;
    uint8_t pad = 0x80;
    update(&pad, 1);
    uint8_t z = 0;
    while (nblk != 56) update(&z, 1);
    uint8_t len[8];
    for (int i = 0; i < 8; i++) len[i] = uint8_t(bits >> (56 - 8 * i));
    update(len, 8);
    char out[65];
    for (int i = 0; i < 8; i++) std::snprintf(out + 8 * i, 9, "%08x", h[i]);
    return std::string(out, 64);
  }
};
}  // namespace

std::string sha256_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (f == nullptr) return "";
  std::vector<uint8_t> b(4u << 20);
  Sha256 s;
  size_t n;
  while ((n = std::fread(b.data(), 1, b.size(), f)) != 0) s.update(b.data(), n);
  bool bad = std::ferror(f) != 0;
  std::fclose(f);
  return bad ? "" : s.hex();
}

bool read_sha_list(const std::string& path, std::vector<ShaEntry>& out,
                   std::string& msg) {
  std::ifstream in(path);
  if (!in) {
    msg = "checksum list " + path + " not found";
    return false;
  }
  std::string line;
  int ln = 0;
  while (std::getline(in, line)) {
    ln++;
    if (line.empty()) continue;
    size_t sp = line.find("  ");
    if (sp != 64) {
      msg = path + " line " + std::to_string(ln) + " is not sha256sum format";
      return false;
    }
    ShaEntry e;
    e.sha = line.substr(0, 64);
    e.rel = line.substr(66);
    size_t sl = e.rel.rfind('/');
    std::string dir = (sl == std::string::npos) ? "" : e.rel.substr(0, sl);
    std::string file = (sl == std::string::npos) ? e.rel : e.rel.substr(sl + 1);
    size_t s2 = dir.rfind('/');
    e.group = (s2 == std::string::npos) ? dir : dir.substr(s2 + 1);
    e.trace = (file.size() > 3 && file.compare(file.size() - 3, 3, ".gz") == 0)
                  ? file.substr(0, file.size() - 3) : file;
    out.push_back(e);
  }
  if (out.empty()) {
    msg = "checksum list " + path + " is empty";
    return false;
  }
  return true;
}

static bool is_dir(const std::string& p) {
  struct stat st;
  return stat(p.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

static std::string abs_path(const std::string& p) {
  char* r = realpath(p.c_str(), nullptr);
  if (r == nullptr) return p;
  std::string s(r);
  std::free(r);
  return s;
}

std::string repo_root(const char* argv0) {
  const char* env = std::getenv("RVA_ROOT");
  if (env != nullptr && *env != 0) return abs_path(env);
  // argv0 is <root>/perf/build/<tool>: up three levels.
  std::string a = abs_path(argv0);
  for (int i = 0; i < 3; i++) {
    size_t s = a.rfind('/');
    if (s == std::string::npos) break;
    a = a.substr(0, s);
  }
  if (is_dir(a + "/perf")) return a;
  return abs_path(".");
}

static std::string env_root(const std::string& repo, const char* var,
                            const char* dflt) {
  const char* env = std::getenv(var);
  std::string p = (env != nullptr && *env != 0) ? std::string(env)
                                                : repo + "/" + dflt;
  return abs_path(p);
}

std::string traces_root(const std::string& repo) {
  return env_root(repo, "CBP_TRACES", "../cbp_traces");
}

std::string traces_rv_root(const std::string& repo) {
  return env_root(repo, "CBP_TRACES_RV", "../cbp_traces_rv");
}

}  // namespace cbp
