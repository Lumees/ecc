#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
ECC UART Hardware Regression Test
====================================
Runs on Arty A7-100T via litex_server + RemoteClient.
Requires: litex_server --uart --uart-port /dev/ttyUSB1 --uart-baudrate 115200
"""

import os
import sys
import time

from litex.tools.litex_client import RemoteClient

# ── Parameters (must match ecc_soc.py / ecc_pkg.sv defaults) ────────────────
DATA_W   = 32
PARITY_W = 6       # calc_parity_bits(32) = 6
CHECK_W  = 7       # PARITY_W + 1
CODE_W   = 39      # DATA_W + CHECK_W

PASS_COUNT = 0
FAIL_COUNT = 0


class ECCClient:
    def __init__(self, host='localhost', tcp_port=1234, csr_csv=None):
        self.client = RemoteClient(host=host, port=tcp_port, csr_csv=csr_csv)
        self.client.open()

    def close(self):
        self.client.close()

    def _w(self, reg: str, val: int):
        getattr(self.client.regs, f"ecc_{reg}").write(val & 0xFFFFFFFF)

    def _r(self, reg: str) -> int:
        return int(getattr(self.client.regs, f"ecc_{reg}").read())

    def version(self) -> int:
        return self._r("version")

    def info(self) -> dict:
        v = self._r("info")
        return {
            "DATA_W":   v & 0xFF,
            "CODE_W":   (v >> 8) & 0xFF,
            "PARITY_W": (v >> 16) & 0xFF,
        }

    def status(self) -> dict:
        s = self._r("status")
        return {
            "enc_done":   bool(s & 0x01),
            "dec_done":   bool(s & 0x02),
            "dec_status": (s >> 2) & 0x03,
        }

    def encode(self, data: int) -> int:
        """Encode DATA_W-bit data, return CODE_W-bit codeword."""
        self._w("enc_data", data)
        self._w("ctrl", 0x01)       # enc_start
        time.sleep(0.002)
        lo = self._r("enc_code_lo")
        hi = self._r("enc_code_hi") if CODE_W > 32 else 0
        return lo | (hi << 32)

    def decode(self, codeword: int) -> dict:
        """Decode CODE_W-bit codeword, return data, status, syndrome."""
        self._w("dec_code_lo", codeword & 0xFFFFFFFF)
        if CODE_W > 32:
            self._w("dec_code_hi", (codeword >> 32) & 0xFFFFFFFF)
        self._w("ctrl", 0x02)       # dec_start
        time.sleep(0.002)
        st = self.status()
        return {
            "data":     self._r("dec_data"),
            "status":   st["dec_status"],
            "syndrome": self._r("dec_syndrome"),
        }


def check(name, condition, detail=""):
    global PASS_COUNT, FAIL_COUNT
    if condition:
        print(f"  [PASS] {name}")
        PASS_COUNT += 1
    else:
        print(f"  [FAIL] {name}  {detail}")
        FAIL_COUNT += 1


# ── Tests ────────────────────────────────────────────────────────────────────

def test_version(dut: ECCClient):
    print("\n[T01] Version / Info registers")
    ver = dut.version()
    check("VERSION == 0x00010000", ver == 0x00010000, f"got 0x{ver:08X}")
    info = dut.info()
    check(f"INFO.DATA_W == {DATA_W}", info["DATA_W"] == DATA_W,
          f"got {info['DATA_W']}")
    check(f"INFO.CODE_W == {CODE_W}", info["CODE_W"] == CODE_W,
          f"got {info['CODE_W']}")
    check(f"INFO.PARITY_W == {PARITY_W}", info["PARITY_W"] == PARITY_W,
          f"got {info['PARITY_W']}")


def test_encode_decode_no_error(dut: ECCClient):
    print("\n[T02] Encode / Decode with no error")
    test_data = 0xDEADBEEF
    codeword = dut.encode(test_data)
    check(f"Encode 0x{test_data:08X} produces non-zero codeword",
          codeword != 0, f"got 0x{codeword:010X}")

    result = dut.decode(codeword)
    check(f"Decoded data == 0x{test_data:08X}",
          result["data"] == test_data,
          f"got 0x{result['data']:08X}")
    check("Status == ECC_OK (0)",
          result["status"] == 0,
          f"got {result['status']}")
    check("Syndrome == 0",
          result["syndrome"] == 0,
          f"got 0x{result['syndrome']:02X}")


def test_single_bit_correction(dut: ECCClient):
    print("\n[T03] Single-bit error correction (SEC)")
    test_data = 0xCAFEBABE
    codeword = dut.encode(test_data)

    # Flip bit 5 in the codeword
    corrupted = codeword ^ (1 << 5)
    result = dut.decode(corrupted)
    check(f"Corrected data == 0x{test_data:08X}",
          result["data"] == test_data,
          f"got 0x{result['data']:08X}")
    check("Status == ECC_SEC (1)",
          result["status"] == 1,
          f"got {result['status']}")
    check("Syndrome != 0",
          result["syndrome"] != 0,
          f"got 0x{result['syndrome']:02X}")


def test_double_bit_detection(dut: ECCClient):
    print("\n[T04] Double-bit error detection (DED)")
    test_data = 0x12345678
    codeword = dut.encode(test_data)

    # Flip two bits in the codeword
    corrupted = codeword ^ (1 << 3) ^ (1 << 7)
    result = dut.decode(corrupted)
    check("Status == ECC_DED (2)",
          result["status"] == 2,
          f"got {result['status']}")
    check("Syndrome != 0",
          result["syndrome"] != 0,
          f"got 0x{result['syndrome']:02X}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    csr_csv = os.path.join(os.path.dirname(__file__),
                           'build/digilent_arty/csr.csv')
    if not os.path.exists(csr_csv):
        csr_csv = None

    dut = ECCClient(csr_csv=csr_csv)

    try:
        print("=" * 60)
        print("ECC UART Hardware Regression")
        print(f"  DATA_W={DATA_W} CODE_W={CODE_W} PARITY_W={PARITY_W}")
        print("=" * 60)

        test_version(dut)
        test_encode_decode_no_error(dut)
        test_single_bit_correction(dut)
        test_double_bit_detection(dut)

        print("\n" + "=" * 60)
        total = PASS_COUNT + FAIL_COUNT
        print(f"Result: {PASS_COUNT}/{total} PASS  {FAIL_COUNT}/{total} FAIL")
        print("=" * 60)
        sys.exit(0 if FAIL_COUNT == 0 else 1)

    finally:
        dut.close()


if __name__ == "__main__":
    main()
