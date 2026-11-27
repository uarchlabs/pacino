// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Jeff Nye, uarchlabs.com
// SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
//
// The CBP2025 interface of the pacino TAGE twin (PERF-005 Phase 4,
// pacino_twin.h). The framework calls get_cond_dir_prediction for each
// conditional and spec_update for every branch right after its
// prediction, with the resolved direction; the twin updates there
// (immediately) and then takes the branch's history bit. The execute and
// commit notifications do nothing.
#include "lib/sim_common_structs.h"
#include "pacino_twin.h"

static PacinoTwin twin;

void beginCondDirPredictor() { twin.setup(); }

void notify_instr_fetch(uint64_t, uint8_t, uint64_t, const uint64_t) {}

bool get_cond_dir_prediction(uint64_t, uint8_t, uint64_t pc,
                             const uint64_t) {
  return twin.predict(pc);
}

void spec_update(uint64_t, uint8_t, uint64_t pc, InstClass inst_class,
                 const bool resolve_dir, const bool, const uint64_t) {
  if (inst_class == InstClass::condBranchInstClass) {
    twin.update(pc, resolve_dir);
    twin.history(resolve_dir);
  } else {
    twin.history(true);
  }
}

void notify_instr_decode(uint64_t, uint8_t, uint64_t, const DecodeInfo&,
                         const uint64_t) {}

void notify_agen_complete(uint64_t, uint8_t, uint64_t, const DecodeInfo&,
                          const uint64_t, const uint64_t, const uint64_t) {}

void notify_instr_execute_resolve(uint64_t, uint8_t, uint64_t, const bool,
                                  const ExecuteInfo&, const uint64_t) {}

void notify_instr_commit(uint64_t, uint8_t, uint64_t, const bool,
                         const ExecuteInfo&, const uint64_t) {}

void endCondDirPredictor() {}
