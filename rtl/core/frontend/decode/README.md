# Decoder Unit

RVA23-compliant instruction decoder for 8-issue out-of-order frontend.

---

## Responsibility

- Accept a fetch bundle of up to 8 instructions (mixed 16b and 32b)
- Pre-decode: expand RVC (16b) instructions to 32b canonical form
- Decode all instructions in parallel
- Output a bundle of up to 8 fully decoded instruction descriptors
- Interface cleanly with the rename/dispatch stage downstream

---

## Directory Structure

```
decoder/
|-- README.md          this file
|-- Makefile           build and simulation targets
|-- rtl/               synthesizable SystemVerilog
|-- tb/                SystemVerilog testbenches
|-- verilator/         C++ simulation wrapper (sim_main.cpp)
|-- tests/             directed test vectors if needed
```

---

## Status

See prompts/frontend/decoder/ for experiment log and design decisions.

---

## Interface (TBD - updated as experiments confirm decisions)

### Inputs

| Signal          | Width | Description                        |
|-----------------|-------|------------------------------------|
| clk             | 1     | clock                              |
| rst_n           | 1     | async reset, active low            |
| fetch_bundle    | TBD   | raw instruction bytes from fetch   |
| fetch_mask      | TBD   | valid/width/alignment mask         |

### Outputs

| Signal          | Width | Description                        |
|-----------------|-------|------------------------------------|
| decode_bundle   | TBD   | decoded instruction descriptors    |
| decode_valid    | 8     | valid bits per slot                |

---

## Makefile Targets

```
make lint        run Verilator lint only
make sim         build and run simulation
make clean       remove build artifacts
```
