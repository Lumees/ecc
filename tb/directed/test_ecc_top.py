# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
ECC IP — Directed cocotb tests for ecc_top
============================================
Tests SECDED Hamming encode/decode for DATA_W=32 (default).
"""

import os, sys, random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../model'))
from ecc_model import ECCModel

DATA_W = int(os.environ.get("ECC_DATA_W", "32"))
model = ECCModel(DATA_W)


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.enc_valid_i.value = 0
    dut.enc_data_i.value = 0
    dut.dec_valid_i.value = 0
    dut.dec_code_i.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_t01_version(dut):
    """T01: Version register."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    ver = int(dut.version_o.value)
    dut._log.info(f"[T01] version = 0x{ver:08X}")
    assert ver == 0x00010000


@cocotb.test()
async def test_t02_encode_decode_no_error(dut):
    """T02: Encode then decode — no error, data matches."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    data = 0xDEADBEEF & ((1 << DATA_W) - 1)
    expected_code = model.encode(data)

    # Encode
    dut.enc_valid_i.value = 1
    dut.enc_data_i.value = data
    await RisingEdge(dut.clk)
    dut.enc_valid_i.value = 0
    await RisingEdge(dut.clk)  # 1-cycle latency

    code = int(dut.enc_code_o.value)
    valid = int(dut.enc_valid_o.value)
    dut._log.info(f"[T02] Encode: data=0x{data:0{DATA_W//4}X} code=0x{code:0{model.code_w//4+1}X}")
    assert valid == 1
    assert code == expected_code, f"Code mismatch: 0x{code:X} != 0x{expected_code:X}"

    # Decode (no error)
    dut.dec_valid_i.value = 1
    dut.dec_code_i.value = code
    await RisingEdge(dut.clk)
    dut.dec_valid_i.value = 0
    await RisingEdge(dut.clk)

    dec_data = int(dut.dec_data_o.value) & ((1 << DATA_W) - 1)
    status = int(dut.dec_status_o.value)
    dut._log.info(f"[T02] Decode: data=0x{dec_data:0{DATA_W//4}X} status={status}")
    assert dec_data == data
    assert status == 0  # ECC_OK


@cocotb.test()
async def test_t03_single_bit_correction(dut):
    """T03: Inject single-bit error — corrected (SEC)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    data = 0xCAFEBABE & ((1 << DATA_W) - 1)
    code = model.encode(data)

    # Flip bit 5 (single-bit error)
    code_err = code ^ (1 << 5)

    dut.dec_valid_i.value = 1
    dut.dec_code_i.value = code_err
    await RisingEdge(dut.clk)
    dut.dec_valid_i.value = 0
    await RisingEdge(dut.clk)

    dec_data = int(dut.dec_data_o.value) & ((1 << DATA_W) - 1)
    status = int(dut.dec_status_o.value)
    dut._log.info(f"[T03] SEC: corrected=0x{dec_data:0{DATA_W//4}X} status={status}")
    assert dec_data == data, f"Correction failed: 0x{dec_data:X} != 0x{data:X}"
    assert status == 1  # ECC_SEC


@cocotb.test()
async def test_t04_double_bit_detection(dut):
    """T04: Inject double-bit error — detected (DED)."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    data = 0x12345678 & ((1 << DATA_W) - 1)
    code = model.encode(data)

    # Flip bits 3 and 7 (double-bit error)
    code_derr = code ^ (1 << 3) ^ (1 << 7)

    dut.dec_valid_i.value = 1
    dut.dec_code_i.value = code_derr
    await RisingEdge(dut.clk)
    dut.dec_valid_i.value = 0
    await RisingEdge(dut.clk)

    status = int(dut.dec_status_o.value)
    dut._log.info(f"[T04] DED: status={status}")
    assert status == 2  # ECC_DED


@cocotb.test()
async def test_t05_all_zero(dut):
    """T05: Encode/decode all-zero data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    data = 0
    code = model.encode(data)

    dut.enc_valid_i.value = 1
    dut.enc_data_i.value = data
    await RisingEdge(dut.clk)
    dut.enc_valid_i.value = 0
    await RisingEdge(dut.clk)

    enc_code = int(dut.enc_code_o.value)
    assert enc_code == code

    dut.dec_valid_i.value = 1
    dut.dec_code_i.value = enc_code
    await RisingEdge(dut.clk)
    dut.dec_valid_i.value = 0
    await RisingEdge(dut.clk)

    dec_data = int(dut.dec_data_o.value) & ((1 << DATA_W) - 1)
    status = int(dut.dec_status_o.value)
    dut._log.info(f"[T05] Zero: dec=0x{dec_data:X} status={status}")
    assert dec_data == 0
    assert status == 0


@cocotb.test()
async def test_t06_all_bits_correction(dut):
    """T06: Single-bit error at every position — all corrected."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    data = 0xA5A5A5A5 & ((1 << DATA_W) - 1)
    code = model.encode(data)
    mismatches = 0

    for bit in range(model.code_w):
        code_err = code ^ (1 << bit)
        dut.dec_valid_i.value = 1
        dut.dec_code_i.value = code_err
        await RisingEdge(dut.clk)
        dut.dec_valid_i.value = 0
        await RisingEdge(dut.clk)

        dec_data = int(dut.dec_data_o.value) & ((1 << DATA_W) - 1)
        status = int(dut.dec_status_o.value)
        if dec_data != data or status != 1:
            mismatches += 1

    dut._log.info(f"[T06] All-bit correction: {model.code_w - mismatches}/{model.code_w} OK")
    assert mismatches == 0


@cocotb.test()
async def test_t07_random_encode_decode(dut):
    """T07: 20 random data values — encode/decode round-trip."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    rng = random.Random(0xBEEF)
    mask = (1 << DATA_W) - 1
    mismatches = 0

    for _ in range(20):
        data = rng.randint(0, mask)
        exp_code = model.encode(data)

        dut.enc_valid_i.value = 1
        dut.enc_data_i.value = data
        await RisingEdge(dut.clk)
        dut.enc_valid_i.value = 0
        await RisingEdge(dut.clk)

        code = int(dut.enc_code_o.value)
        if code != exp_code:
            mismatches += 1
            continue

        dut.dec_valid_i.value = 1
        dut.dec_code_i.value = code
        await RisingEdge(dut.clk)
        dut.dec_valid_i.value = 0
        await RisingEdge(dut.clk)

        dec_data = int(dut.dec_data_o.value) & mask
        if dec_data != data:
            mismatches += 1

    dut._log.info(f"[T07] Random: {20 - mismatches}/20 matched")
    assert mismatches == 0
