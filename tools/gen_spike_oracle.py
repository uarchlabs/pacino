#!/usr/bin/env python3
# gen_spike_oracle.py
# Parse rva23_insn_ref.disasm and write spike_oracle.csv.
# Called by: make spike_oracle
# Output columns: address,encoding,mnemonic_hint,skip

import os
import re
import csv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DISASM_PATH = os.path.join(SCRIPT_DIR, "rva23_insn_ref.disasm")
CSV_PATH = os.path.join(SCRIPT_DIR, "spike_oracle.csv")

# Match objdump disassembly lines:
#   <hex_offset>:  <raw_bytes>   <mnemonic...>
# raw_bytes may be 4, 6, or 8 hex chars (16-bit, 24-bit, or 32-bit insn).
# We require at least one tab-separated field after the raw bytes.
INSN_RE = re.compile(
  r"^\s+([0-9a-f]+):\s+([0-9a-f]{4,8})\s+(.+)$"
)


def parse_disasm(path):
  rows = []
  in_text = False
  skip_label = False

  with open(path, "r") as f:
    for line in f:
      line = line.rstrip("\n")

      # Find section start
      if "Disassembly of section .text:" in line:
        in_text = True
        skip_label = True  # next non-blank line is the function label
        continue

      if not in_text:
        continue

      # Skip blank lines
      if not line.strip():
        continue

      # Skip the function label line e.g. "0000...0000 <rva23s64_insn_ref>:"
      if skip_label:
        skip_label = False
        continue

      m = INSN_RE.match(line)
      if not m:
        # Lines with no mnemonic (pure data) - skip
        continue

      addr_hex = m.group(1)
      encoding = m.group(2)
      mnemonic_raw = m.group(3).strip()

      # Truncate mnemonic_hint to 32 characters max
      mnemonic_hint = mnemonic_raw[:32]

      # Format address as 0x%04x
      addr_int = int(addr_hex, 16)
      address = "0x{:04x}".format(addr_int)

      rows.append({
        "address": address,
        "encoding": encoding,
        "mnemonic_hint": mnemonic_hint,
        "skip": 0,
      })

  return rows


def write_csv(path, rows):
  fieldnames = ["address", "encoding", "mnemonic_hint", "skip"]
  with open(path, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
      writer.writerow(row)


def main():
  rows = parse_disasm(DISASM_PATH)
  write_csv(CSV_PATH, rows)
  print("Wrote {} rows to {}".format(len(rows), CSV_PATH))


if __name__ == "__main__":
  main()
