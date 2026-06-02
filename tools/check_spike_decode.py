#!/usr/bin/env python3
# check_spike_decode.py
# Read spike_oracle.csv and pipe each encoding through spike-dasm.
# Classify each result as DECODED, UNKNOWN, or ERROR.
# Exit 0 if all non-skipped rows decode; exit 1 otherwise.

import os
import csv
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(SCRIPT_DIR, "spike_oracle.csv")
SPIKE_DASM = os.path.join(
  SCRIPT_DIR, "spike", "install", "bin", "spike-dasm"
)

ISA = (
  "rv64imafdc_v_h_sscofpmf_sstc_svinval_svnapot_svpbmt"
  "_zawrs_zba_zbb_zbc_zbs_zfa_zfh_zfhmin_zicbom_zicboz"
  "_zicntr_zifencei_zicond_zihintntl_zihintpause_zihpm"
  "_zkt_zk_zkn_zknd_zkne_zknh_zbkb_zbkc_zbkx_zicbop"
  "_zcb_zvkb_zimop_zcmop"
)

RESULT_DECODED = "DECODED"
RESULT_UNKNOWN = "UNKNOWN"
RESULT_ERROR   = "ERROR"

COL_W_ADDR  = 8
COL_W_ENC   = 10
COL_W_MNE   = 34
COL_W_OUT   = 36
COL_W_RES   = 9
COL_W_SKIP  = 5


def run_spike_dasm(encoding):
  """Pipe DASM(<encoding>) through spike-dasm. Return (output, returncode)."""
  dasm_input = "DASM({})".format(encoding)
  try:
    proc = subprocess.run(
      [SPIKE_DASM, "--isa={}".format(ISA)],
      input=dasm_input,
      capture_output=True,
      text=True,
    )
    return proc.stdout.strip(), proc.returncode
  except FileNotFoundError:
    return "", -1


def classify(output, returncode):
  if returncode != 0:
    return RESULT_ERROR
  if "unknown" in output.lower():
    return RESULT_UNKNOWN
  return RESULT_DECODED


def fmt_row(addr, enc, mne, out, result, skip):
  """Format one table row, truncating fields to column widths."""
  out_trunc = out[:COL_W_OUT - 2] if len(out) > COL_W_OUT - 2 else out
  return (
    "{:<{w0}} {:<{w1}} {:<{w2}} {:<{w3}} {:<{w4}} {:<{w5}}"
    .format(
      addr,    mne[:COL_W_MNE - 1],
      enc,     out_trunc,
      result,  str(skip),
      w0=COL_W_ADDR,
      w1=COL_W_MNE,
      w2=COL_W_ENC,
      w3=COL_W_OUT,
      w4=COL_W_RES,
      w5=COL_W_SKIP,
    )
  )


def print_header():
  print(
    "{:<{w0}} {:<{w1}} {:<{w2}} {:<{w3}} {:<{w4}} {:<{w5}}"
    .format(
      "address", "mnemonic_hint", "encoding",
      "spike_output", "result", "skip",
      w0=COL_W_ADDR,
      w1=COL_W_MNE,
      w2=COL_W_ENC,
      w3=COL_W_OUT,
      w4=COL_W_RES,
      w5=COL_W_SKIP,
    )
  )
  sep_w = (
    COL_W_ADDR + 1 + COL_W_MNE + 1 + COL_W_ENC + 1
    + COL_W_OUT + 1 + COL_W_RES + 1 + COL_W_SKIP
  )
  print("-" * sep_w)


def main():
  if not os.path.isfile(CSV_PATH):
    print("ERROR: CSV not found: {}".format(CSV_PATH))
    sys.exit(1)

  if not os.path.isfile(SPIKE_DASM):
    print("ERROR: spike-dasm not found: {}".format(SPIKE_DASM))
    sys.exit(1)

  results = []
  with open(CSV_PATH, newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
      addr     = row["address"]
      encoding = row["encoding"]
      mne      = row["mnemonic_hint"]
      skip     = int(row["skip"])

      output, rc = run_spike_dasm(encoding)
      result = classify(output, rc)

      results.append({
        "address":  addr,
        "encoding": encoding,
        "mnemonic_hint": mne,
        "output":   output,
        "result":   result,
        "skip":     skip,
      })

  print_header()
  for r in results:
    print(fmt_row(
      r["address"],
      r["encoding"],
      r["mnemonic_hint"],
      r["output"],
      r["result"],
      r["skip"],
    ))

  total    = len(results)
  decoded  = sum(1 for r in results if r["result"] == RESULT_DECODED)
  unknown  = sum(1 for r in results if r["result"] == RESULT_UNKNOWN)
  errors   = sum(1 for r in results if r["result"] == RESULT_ERROR)
  skipped  = sum(1 for r in results if r["skip"] == 1)

  print()
  print(
    "Summary: total={} decoded={} unknown={} skipped={} errors={}"
    .format(total, decoded, unknown, skipped, errors)
  )

  # Fail if any non-skipped row is UNKNOWN or ERROR
  fail = any(
    r["result"] in (RESULT_UNKNOWN, RESULT_ERROR) and r["skip"] == 0
    for r in results
  )

  sys.exit(1 if fail else 0)


if __name__ == "__main__":
  main()
