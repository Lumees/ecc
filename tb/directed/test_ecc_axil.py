# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
ECC IP — Directed cocotb tests for ecc_axil (AXI4-Lite wrapper)
================================================================
Tests register reads, Hamming encode/decode via AXI4-Lite, and IRQ.

Register map:
  0x00 CTRL        [0]=enc_start(W,self-clear) [1]=dec_start(W,self-clear)
  0x04 STATUS   RO [0]=enc_done [1]=dec_done [3:2]=dec_status
  0x08 INFO     RO [7:0]=DATA_W [15:8]=CODE_W [23:16]=PARITY_W
  0x0C VERSION  RO IP_VERSION (0x00010000)
  0x10 ENC_DATA    W  data for encoding [DATA_W-1:0]
  0x14 ENC_CODE_LO RO encoded codeword [31:0]
  0x18 ENC_CODE_HI RO encoded codeword [CODE_W-1:32]
  0x1C DEC_CODE_LO W  codeword for decoding [31:0]
  0x20 DEC_CODE_HI W  codeword for decoding [CODE_W-1:32]
  0x24 DEC_DATA    RO decoded data [DATA_W-1:0]
  0x28 DEC_SYNDROME RO syndrome [PARITY_W-1:0]
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os

DATA_W = int(os.environ.get("ECC_DATA_W", "32"))
CLK_NS = 10

# Register offsets
REG_CTRL         = 0x00
REG_STATUS       = 0x04
REG_INFO         = 0x08
REG_VERSION      = 0x0C
REG_ENC_DATA     = 0x10
REG_ENC_CODE_LO  = 0x14
REG_ENC_CODE_HI  = 0x18
REG_DEC_CODE_LO  = 0x1C
REG_DEC_CODE_HI  = 0x20
REG_DEC_DATA     = 0x24
REG_DEC_SYNDROME = 0x28


# ---------------------------------------------------------------------------
# AXI4-Lite bus helpers
# ---------------------------------------------------------------------------
async def axil_write(dut, addr, data):
    """Single AXI4-Lite write transaction."""
    dut.s_axil_awaddr.value  = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = data & 0xFFFFFFFF
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_wvalid.value  = 1
    dut.s_axil_bready.value  = 1

    while True:
        await RisingEdge(dut.clk)
        aw_done = int(dut.s_axil_awready.value) == 1
        w_done  = int(dut.s_axil_wready.value)  == 1
        if aw_done:
            dut.s_axil_awvalid.value = 0
        if w_done:
            dut.s_axil_wvalid.value = 0
        if aw_done and w_done:
            break

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_bvalid.value) == 1:
            dut.s_axil_bready.value = 0
            return
    raise TimeoutError(f"axil_write timeout at addr=0x{addr:02X}")


async def axil_read(dut, addr) -> int:
    """Single AXI4-Lite read transaction, returns 32-bit data."""
    dut.s_axil_araddr.value  = addr
    dut.s_axil_arvalid.value = 1
    dut.s_axil_rready.value  = 1

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            dut.s_axil_arvalid.value = 0
            break
    else:
        raise TimeoutError(f"axil_read AR timeout at addr=0x{addr:02X}")

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            data = int(dut.s_axil_rdata.value)
            dut.s_axil_rready.value = 0
            return data
    raise TimeoutError(f"axil_read R timeout at addr=0x{addr:02X}")


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------
async def hw_reset(dut):
    """Assert reset and initialize all AXI4-Lite inputs to idle."""
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    dut.s_axil_bready.value  = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value  = 0
    dut.s_axil_awaddr.value  = 0
    dut.s_axil_wdata.value   = 0
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_araddr.value  = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 8)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_t01_version(dut):
    """T01: Read VERSION register (offset 0x0C) == 0x00010000."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    ver = await axil_read(dut, REG_VERSION)
    dut._log.info(f"[T01] VERSION = 0x{ver:08X}")
    assert ver == 0x00010000, f"VERSION mismatch: 0x{ver:08X} != 0x00010000"


@cocotb.test()
async def test_t02_info(dut):
    """T02: Read INFO register — {PARITY_W, CODE_W, DATA_W} packed."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    info = await axil_read(dut, REG_INFO)
    got_data_w   = info & 0xFF
    got_code_w   = (info >> 8) & 0xFF
    got_parity_w = (info >> 16) & 0xFF

    dut._log.info(f"[T02] INFO = 0x{info:08X}: DATA_W={got_data_w} "
                  f"CODE_W={got_code_w} PARITY_W={got_parity_w}")
    assert got_data_w == DATA_W, f"DATA_W mismatch: {got_data_w} != {DATA_W}"
    assert got_code_w > got_data_w, f"CODE_W ({got_code_w}) should exceed DATA_W ({got_data_w})"
    assert got_parity_w > 0, f"PARITY_W should be > 0, got {got_parity_w}"


@cocotb.test()
async def test_t03_encode(dut):
    """T03: Encode data via registers and verify codeword is non-zero."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    data_mask = (1 << DATA_W) - 1
    test_val = 0xA5A5A5A5 & data_mask

    # Write data to encode
    await axil_write(dut, REG_ENC_DATA, test_val)

    # Trigger encode
    await axil_write(dut, REG_CTRL, 0x01)

    # Wait a few cycles for encode to complete
    await ClockCycles(dut.clk, 10)

    # Poll STATUS for enc_done
    for _ in range(50):
        status = await axil_read(dut, REG_STATUS)
        if status & 0x01:
            break
        await ClockCycles(dut.clk, 2)
    else:
        raise TimeoutError("Encode done timeout")

    # Read encoded codeword
    code_lo = await axil_read(dut, REG_ENC_CODE_LO)
    code_hi = await axil_read(dut, REG_ENC_CODE_HI)

    dut._log.info(f"[T03] Encode 0x{test_val:08X} -> code_lo=0x{code_lo:08X} code_hi=0x{code_hi:08X}")
    # Codeword must contain the data plus parity bits, so it should be non-zero
    assert (code_lo | code_hi) != 0, "Encoded codeword is all zeros"


@cocotb.test()
async def test_t04_decode_no_error(dut):
    """T04: Encode then decode with no injected errors — decoded data matches."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    data_mask = (1 << DATA_W) - 1
    test_val = 0xDEADBEEF & data_mask

    # Encode
    await axil_write(dut, REG_ENC_DATA, test_val)
    await axil_write(dut, REG_CTRL, 0x01)
    await ClockCycles(dut.clk, 10)

    for _ in range(50):
        status = await axil_read(dut, REG_STATUS)
        if status & 0x01:
            break
        await ClockCycles(dut.clk, 2)

    code_lo = await axil_read(dut, REG_ENC_CODE_LO)
    code_hi = await axil_read(dut, REG_ENC_CODE_HI)

    # Decode — feed the clean codeword back
    await axil_write(dut, REG_DEC_CODE_LO, code_lo)
    await axil_write(dut, REG_DEC_CODE_HI, code_hi)
    await axil_write(dut, REG_CTRL, 0x02)
    await ClockCycles(dut.clk, 10)

    for _ in range(50):
        status = await axil_read(dut, REG_STATUS)
        if status & 0x02:
            break
        await ClockCycles(dut.clk, 2)
    else:
        raise TimeoutError("Decode done timeout")

    dec_data = await axil_read(dut, REG_DEC_DATA)
    dec_data &= data_mask
    syndrome = await axil_read(dut, REG_DEC_SYNDROME)

    dut._log.info(f"[T04] Decoded = 0x{dec_data:08X} (expected 0x{test_val:08X}), "
                  f"syndrome = 0x{syndrome:08X}")
    assert dec_data == test_val, (f"Decode mismatch: 0x{dec_data:08X} != 0x{test_val:08X}")
    assert syndrome == 0, f"Syndrome should be 0 for clean codeword, got 0x{syndrome:08X}"


@cocotb.test()
async def test_t05_irq_on_done(dut):
    """T05: IRQ pulse fires on encode done."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    data_mask = (1 << DATA_W) - 1

    # Write data and trigger encode
    await axil_write(dut, REG_ENC_DATA, 0x12345678 & data_mask)
    await axil_write(dut, REG_CTRL, 0x01)

    # Monitor IRQ
    irq_seen = False
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.irq.value) == 1:
            irq_seen = True
            break

    dut._log.info(f"[T05] IRQ pulse detected: {irq_seen}")
    assert irq_seen, "IRQ pulse was never asserted after encode"

    # Verify IRQ is single-cycle pulse
    await RisingEdge(dut.clk)
    irq_after = int(dut.irq.value)
    dut._log.info(f"[T05] IRQ after one cycle: {irq_after}")
    assert irq_after == 0, "IRQ was not a single-cycle pulse"
