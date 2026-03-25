# ECC SECDED IP Core

> **Lumees Lab** — FPGA-Verified, Production-Ready Silicon IP

[![License](https://img.shields.io/badge/License-Source_Available-orange.svg)](LICENSE)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--100T-green.svg)]()
[![Fmax](https://img.shields.io/badge/Fmax-100%20MHz-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-13%2F13%20HW%20PASS-blue.svg)]()

---

## Overview

The Lumees Lab ECC IP Core implements **SECDED (Single Error Correct, Double Error Detect) Hamming code** for memory and data-link protection. Given a DATA_W-bit input, the encoder produces a CODE_W-bit codeword with automatically computed check bits. On the decode side, the syndrome distinguishes no-error, correctable single-bit error, and uncorrectable double-bit error — all in pure combinational logic with a single-cycle registered pipeline.

The data width is compile-time selectable (8, 16, 32, or 64 bits) with check-bit counts derived automatically from the Hamming bound. At 100 MHz the core occupies just **543 LUTs and 749 FFs** — zero DSP, zero BRAM — making it ideal for protecting SRAM, register files, FIFO payloads, and on-chip bus transfers.

Verified in simulation (12/12 cocotb tests across two interfaces) and on Xilinx FPGA hardware (Arty A7-100T, **13/13 UART regression checks** covering encode, decode, SEC, and DED), the core is production-ready for SoC integration.

---

## Key Features

| Feature | Detail |
|---|---|
| **Algorithm** | SECDED Hamming code (extended Hamming with overall parity) |
| **Data Widths** | 8, 16, 32 bits (bus wrappers); 64 bits (bare core) |
| **Check Bits** | Auto-calculated: 5 (8-bit), 6 (16-bit), 7 (32-bit), 8 (64-bit) |
| **Encoder** | Combinational — data in, codeword out (1-cycle registered) |
| **Decoder** | Combinational — codeword in, corrected data + status out (1-cycle registered) |
| **Status** | `ECC_OK` (no error), `ECC_SEC` (corrected), `ECC_DED` (uncorrectable) |
| **Syndrome** | Full syndrome output for error-position diagnostics |
| **Latency** | 1 clock cycle (encode or decode) |
| **Bus Interfaces** | AXI4-Lite, Wishbone B4 |
| **Interrupt** | Single-cycle IRQ pulse on encode-done or decode-done |
| **Technology** | FPGA / ASIC, pure synchronous RTL, no vendor primitives |

---

## Performance — Arty A7-100T (XC7A100T) @ 100 MHz

| Resource | ECC Core (DATA_W=32) | Full SoC | Available |
|---|---|---|---|
| LUT | 543 | 543 | 63,400 |
| FF | 749 | 749 | 126,800 |
| DSP48 | 0 | 0 | 240 |
| Block RAM | 0 | 0 | 135 |

> **Timing:** WNS = +1.064 ns @ 100 MHz. Core utilization: 0.86% LUTs. Pure LUT/FF — zero DSP/BRAM.

---

## Supported Configurations

| DATA_W | PARITY_W | CHECK_W | CODE_W | Overhead | Bus Wrapper Support |
|---|---|---|---|---|---|
| 8 | 4 | 5 | 13 | 62.5% | AXI4-Lite, Wishbone |
| 16 | 5 | 6 | 22 | 37.5% | AXI4-Lite, Wishbone |
| 32 | 6 | 7 | 39 | 21.9% | AXI4-Lite, Wishbone |
| 64 | 7 | 8 | 72 | 12.5% | Bare core only (`ecc_top`) |

Set data width at compile time via `` `define ECC_PKG_DATA_W <N> `` or leave unset for the default (32).

---

## Architecture

```
               ┌────────────────────────────────────────────────────┐
               │                     ecc_top                        │
               │              (1-cycle registered I/O)              │
               │                                                    │
 enc_valid_i ──┤──►┌──────────────────────────────────┐             │
 enc_data_i  ──┤   │           ecc_core               │──► enc_code_o
               │   │       (combinational)             │    enc_valid_o
               │   │                                   │             │
               │   │  ENCODER                          │             │
               │   │    data → place non-2^i pos       │             │
               │   │    → Hamming parity (2^i pos)     │             │
               │   │    → overall parity (pos 0)       │             │
               │   │                                   │             │
 dec_valid_i ──┤   │  DECODER                          │──► dec_data_o
 dec_code_i  ──┤──►│    syndrome = XOR parity groups   │    dec_status_o
               │   │    overall = XOR all bits         │    dec_syndrome_o
               │   │    SEC: flip corrected[syndrome]  │    dec_valid_o
               │   │    DED: syndrome≠0 & overall=0    │             │
               │   └──────────────────────────────────┘             │
               │                                                    │
 version_o   ◄─┤  IP_VERSION = 0x00010000                           │
               └────────────────────────────────────────────────────┘
```

**Encoder:** Places data bits at non-power-of-2 codeword positions, computes Hamming parity at each power-of-2 position, then sets overall parity (position 0) as XOR of all other bits.

**Decoder:** Recomputes syndrome (XOR of parity groups) and overall parity. Syndrome = 0 means no error. Syndrome ≠ 0 with odd overall parity → single-bit error at position `syndrome` (correctable). Syndrome ≠ 0 with even overall parity → double-bit error (detected, uncorrectable).

---

## Interface — Bare Core (`ecc_top`)

```systemverilog
ecc_top u_ecc (
  .clk            (clk),
  .rst_n          (rst_n),

  // Encoder — 1-cycle latency
  .enc_valid_i    (enc_valid),       // pulse: encode request
  .enc_data_i     (enc_data),        // [DATA_W-1:0] data to protect
  .enc_valid_o    (enc_done),        // pulse: codeword ready
  .enc_code_o     (enc_code),        // [CODE_W-1:0] protected codeword

  // Decoder — 1-cycle latency
  .dec_valid_i    (dec_valid),       // pulse: decode request
  .dec_code_i     (dec_code),        // [CODE_W-1:0] received codeword
  .dec_valid_o    (dec_done),        // pulse: decode complete
  .dec_data_o     (dec_data),        // [DATA_W-1:0] corrected data
  .dec_status_o   (dec_status),      // ECC_OK | ECC_SEC | ECC_DED
  .dec_syndrome_o (dec_syndrome),    // [PARITY_W-1:0] error syndrome

  // Info
  .version_o      (version)          // 0x00010000
);
```

**Software flow:**
1. **Encode:** Assert `enc_valid_i` with `enc_data_i` → read `enc_code_o` one cycle later when `enc_valid_o` pulses
2. **Decode:** Assert `dec_valid_i` with `dec_code_i` → read `dec_data_o` and `dec_status_o` one cycle later when `dec_valid_o` pulses
3. **Check status:** `ECC_OK` (0) = clean, `ECC_SEC` (1) = corrected, `ECC_DED` (2) = uncorrectable

---

## Register Map — AXI4-Lite / Wishbone

Both `ecc_axil` and `ecc_wb` share the same register map:

| Offset | Register | Access | Description |
|---|---|---|---|
| 0x00 | CTRL | W | `[0]`=enc_start `[1]`=dec_start (both self-clearing) |
| 0x04 | STATUS | RO | `[0]`=enc_done `[1]`=dec_done `[3:2]`=dec_status |
| 0x08 | INFO | RO | `[7:0]`=DATA_W `[15:8]`=CODE_W `[23:16]`=PARITY_W |
| 0x0C | VERSION | RO | IP version `0x00010000` |
| 0x10 | ENC_DATA | W | Data input for encoding `[DATA_W-1:0]` |
| 0x14 | ENC_CODE_LO | RO | Encoded codeword `[31:0]` |
| 0x18 | ENC_CODE_HI | RO | Encoded codeword `[CODE_W-1:32]` (if CODE_W > 32) |
| 0x1C | DEC_CODE_LO | W | Codeword for decoding `[31:0]` |
| 0x20 | DEC_CODE_HI | W | Codeword for decoding `[CODE_W-1:32]` |
| 0x24 | DEC_DATA | RO | Decoded data `[DATA_W-1:0]` |
| 0x28 | DEC_SYNDROME | RO | Syndrome `[PARITY_W-1:0]` |

**Software flow (bus wrapper):**
1. Write data to `ENC_DATA`
2. Write `0x01` to `CTRL` (triggers encode)
3. Poll `STATUS[0]` for `enc_done`, then read `ENC_CODE_LO`/`HI`
4. Write codeword to `DEC_CODE_LO`/`HI`
5. Write `0x02` to `CTRL` (triggers decode)
6. Poll `STATUS[1]` for `dec_done`, then read `DEC_DATA` and check `STATUS[3:2]`

---

## Verification

### Simulation (cocotb + Verilator) — 12/12 PASS

| Test | Suite | Description |
|---|---|---|
| T01 | `test_ecc_top` | Version register == 0x00010000 |
| T02 | `test_ecc_top` | Encode/decode round-trip — no error (ECC_OK) |
| T03 | `test_ecc_top` | Single-bit error injection — corrected (ECC_SEC) |
| T04 | `test_ecc_top` | Double-bit error injection — detected (ECC_DED) |
| T05 | `test_ecc_top` | All-zero data encode/decode |
| T06 | `test_ecc_top` | Single-bit error at every codeword position (39/39 corrected) |
| T07 | `test_ecc_top` | 20 random data values — round-trip golden-model match |
| T01 | `test_ecc_axil` | VERSION register via AXI4-Lite |
| T02 | `test_ecc_axil` | INFO register — DATA_W, CODE_W, PARITY_W readback |
| T03 | `test_ecc_axil` | Encode via registers — codeword non-zero |
| T04 | `test_ecc_axil` | Encode → decode via registers — data matches, syndrome == 0 |
| T05 | `test_ecc_axil` | IRQ pulse fires on encode-done (single-cycle) |

### UVM Constrained-Random

Full UVM environment (12 files): agent, driver, monitor, scoreboard, coverage, sequences. Directed + random + stress test classes with encode/decode/error-injection coverage.

### FPGA Hardware (Arty A7-100T) — 13/13 PASS

| Test | Checks | Description |
|---|---|---|
| T01 | 4 | VERSION, INFO.DATA_W, INFO.CODE_W, INFO.PARITY_W |
| T02 | 4 | Encode non-zero, decoded data match, status == ECC_OK, syndrome == 0 |
| T03 | 3 | SEC: corrected data match, status == ECC_SEC, syndrome ≠ 0 |
| T04 | 2 | DED: status == ECC_DED, syndrome ≠ 0 |

All tests run at 100 MHz via LiteX SoC + UARTBone bridge on Xilinx XC7A100T.

---

## Directory Structure

```
ecc/
├── rtl/                       # Synthesizable RTL (5 files, 730 lines)
│   ├── ecc_pkg.sv             # Types, parameters, calc_parity_bits()
│   ├── ecc_core.sv            # Combinational SECDED encoder/decoder
│   ├── ecc_top.sv             # Registered pipeline wrapper (1-cycle)
│   ├── ecc_axil.sv            # AXI4-Lite slave wrapper
│   └── ecc_wb.sv              # Wishbone B4 slave wrapper
├── model/
│   └── ecc_model.py           # Python golden model (4 data widths)
├── tb/
│   ├── directed/              # cocotb tests (12/12 PASS)
│   │   ├── test_ecc_top.py    # 7 tests: encode, decode, SEC, DED, sweep
│   │   └── test_ecc_axil.py   # 5 tests: registers, round-trip, IRQ
│   └── uvm/                   # UVM environment (12 files, 1,556 lines)
├── sim/
│   └── Makefile.cocotb        # make sim-top / sim-axil / sim-all
├── litex/                     # LiteX SoC for Arty A7-100T
│   ├── ecc_litex.py           # Migen/LiteX module wrapper
│   ├── ecc_soc.py             # Reference SoC (Arty A7-100T)
│   └── ecc_uart_test.py       # UART hardware regression (13 checks)
├── README.md
├── LICENSE
└── .gitignore
```

---

## Applications

- **SRAM / register file protection** — Encode on write, decode on read for soft-error resilience
- **On-chip bus integrity** — Protect AXI/AHB data transfers against transient faults
- **ECC DRAM controllers** — SECDED parity generation and checking for DDR memory
- **Flash / NVM storage** — Protect stored data against bit-rot and read disturb
- **Safety-critical systems** — IEC 61508 / ISO 26262 memory integrity requirements
- **Space / radiation environments** — SEU (single-event upset) mitigation in FPGA fabric

---

## Roadmap

### v1.1
- [ ] AXI4-Stream wrapper for inline pipeline protection
- [ ] Multi-bit error injection test modes (BIST)
- [ ] DATA_W=64 bus wrapper support (triple-register codeword span)
- [ ] Interrupt mask/enable register

### v1.2
- [ ] BCH codes (multi-bit correction for higher reliability)
- [ ] Scrubbing controller (periodic background correction)

### v2.0
- [ ] SkyWater 130nm silicon-proven version

---

## Why Lumees ECC?

| Differentiator | Detail |
|---|---|
| **Parameterized** | 8/16/32/64-bit data widths from a single RTL source |
| **543 LUTs** | Minimal footprint — embed in any SoC without area pressure |
| **Zero DSP/BRAM** | Pure combinational XOR + flip-flops |
| **1-cycle latency** | No pipeline stalls — drop into any data path |
| **Full diagnostics** | Syndrome output pinpoints the exact error position |
| **Dual bus interfaces** | AXI4-Lite and Wishbone B4 with shared register map |
| **12/12 sim + 13/13 HW** | Verified on real FPGA silicon, not just simulation |
| **Source-available** | Full RTL — inspect the Hamming matrix |

---

## License

**Dual license:** Free for non-commercial use (Apache 2.0). Commercial use requires a Lumees Lab license.

See [LICENSE](LICENSE) for full terms.

---

**Lumees Lab** · Hasan Kurşun · [lumeeslab.com](https://lumeeslab.com) · info@lumeeslab.com

*Copyright © 2026 Lumees Lab. All rights reserved.*
