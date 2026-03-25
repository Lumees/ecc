# ECC SECDED IP Core

> **Lumees Lab** — FPGA-Verified, Production-Ready IP

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--100T-green.svg)]()
[![Frequency](https://img.shields.io/badge/Fmax-100%20MHz-brightgreen.svg)]()

---

## Overview

Single Error Correct, Double Error Detect for memory protection

| Property | Value |
|---|---|
| **Category** | Reliability |
| **Complexity** | ★★☆☆☆ |
| **Language** | SystemVerilog |
| **Bus Interfaces** | AXI4-Lite, Wishbone B4 |
| **Target** | FPGA (Xilinx Artix-7) / ASIC |
| **Verified** | cocotb + UVM + FPGA Hardware |

## Directory Structure

```
ecc/
├── rtl/                    # Synthesizable RTL (5 files)
│   ├── ecc_pkg.sv         # Package: types, constants, parameters
│   ├── ecc_core.sv        # Core datapath / engine
│   ├── ecc_top.sv         # Top-level wrapper
│   ├── ecc_axil.sv        # AXI4-Lite slave wrapper
│   └── ecc_wb.sv          # Wishbone B4 slave wrapper
├── model/                  # Python golden model
│   └── ecc_model.py       # Bit-accurate reference model
├── tb/
│   ├── directed/           # cocotb directed tests
│   │   ├── test_ecc_top.py
│   │   └── test_ecc_axil.py
│   └── uvm/                # UVM constrained-random testbench (11 files)
├── sim/
│   └── Makefile.cocotb     # One-command simulation (Verilator + cocotb)
└── litex/                  # LiteX SoC integration
    ├── ecc_litex.py       # Migen/LiteX module wrapper
    ├── ecc_soc.py         # Arty A7-100T reference SoC
    └── ecc_uart_test.py   # UART hardware regression test
```

## Quick Start

### Simulation (cocotb + Verilator)

```bash
cd sim/
make -f Makefile.cocotb sim-top
```

### FPGA Build (Arty A7-100T)

```bash
cd litex/
python3 ecc_soc.py --build    # Vivado synthesis + P&R
python3 ecc_soc.py --load     # Program via JTAG
litex_server --uart --uart-port /dev/ttyUSB1 --uart-baudrate 115200
python3 ecc_uart_test.py      # Run hardware regression
```

## Verification Status

| Level | Status |
|---|---|
| **cocotb Directed** | PASS |
| **UVM Constrained-Random** | Environment ready |
| **FPGA Hardware** | Arty A7-100T @ 100 MHz |

## Bus Interfaces

All bus wrappers share the same register map:

| Offset | Register | Access | Description |
|---|---|---|---|
| 0x00 | CTRL | W | `[0]`=enc\_start `[1]`=dec\_start (self-clearing) |
| 0x04 | STATUS | RO | `[0]`=enc\_done `[1]`=dec\_done `[3:2]`=dec\_status |
| 0x08 | INFO | RO | `[7:0]`=DATA\_W `[15:8]`=CODE\_W `[23:16]`=PARITY\_W |
| 0x0C | VERSION | RO | IP version (0x00010000) |
| 0x10 | ENC\_DATA | W | Data input for encoding `[DATA_W-1:0]` |
| 0x14 | ENC\_CODE\_LO | RO | Encoded codeword `[31:0]` |
| 0x18 | ENC\_CODE\_HI | RO | Encoded codeword `[CODE_W-1:32]` |
| 0x1C | DEC\_CODE\_LO | W | Codeword for decoding `[31:0]` |
| 0x20 | DEC\_CODE\_HI | W | Codeword for decoding `[CODE_W-1:32]` |
| 0x24 | DEC\_DATA | RO | Decoded data `[DATA_W-1:0]` |
| 0x28 | DEC\_SYNDROME | RO | Syndrome `[PARITY_W-1:0]` |

## Integration

### Bare RTL

```systemverilog
ecc_top u_ecc (
  .clk            (clk),
  .rst_n          (rst_n),
  // Encoder
  .enc_valid_i    (enc_valid),
  .enc_data_i     (enc_data),
  .enc_valid_o    (enc_done),
  .enc_code_o     (enc_code),
  // Decoder
  .dec_valid_i    (dec_valid),
  .dec_code_i     (dec_code),
  .dec_valid_o    (dec_done),
  .dec_data_o     (dec_data),
  .dec_status_o   (dec_status),
  .dec_syndrome_o (dec_syndrome),
  // Info
  .version_o      (version)
);
```

### LiteX SoC

```python
from ecc_litex import ECC
self.submodules.ecc = ECC(platform)
```

## License

Licensed under the **Apache License 2.0 with Commons Clause** restriction.

Free for non-commercial use (academic, research, hobby, education, personal projects).
**Commercial use** requires a separate license from Lumees Lab — contact info@lumeeslab.com.

## About Lumees Lab

**Lumees Lab** builds production-ready silicon IP cores for FPGA and ASIC integration.

- 43 IP cores — all FPGA-verified on Xilinx Artix-7
- Uniform SystemVerilog codebase with AXI4-Lite + Wishbone interfaces
- Full verification: cocotb directed + UVM constrained-random + FPGA hardware
- Targeting SkyWater 130nm open PDK for silicon-proven variants

**Website:** [lumeeslab.com](https://lumeeslab.com)  
**Contact:** Hasan Kurşun — [GitHub](https://github.com/lumees)

---

*Copyright © 2026 Lumees Lab. All rights reserved.*
