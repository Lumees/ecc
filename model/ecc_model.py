#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
ECC (SECDED Hamming) Golden Model — Lumees Lab
================================================
Bit-accurate encoder/decoder for SECDED Hamming codes.
Supports DATA_W = 8, 16, 32, 64.
"""

from __future__ import annotations


def calc_parity_bits(data_w: int) -> int:
    m = 1
    while (1 << m) < (data_w + m + 1):
        m += 1
    return m


class ECCModel:
    def __init__(self, data_w: int = 32):
        self.data_w = data_w
        self.parity_w = calc_parity_bits(data_w)
        self.check_w = self.parity_w + 1
        self.code_w = data_w + self.check_w

    def _is_power_of_2(self, n):
        return n > 0 and (n & (n - 1)) == 0

    def encode(self, data: int) -> int:
        """Encode data into SECDED Hamming codeword."""
        code = [0] * self.code_w

        # Place data bits at non-power-of-2 positions (skip 0 and 2^i)
        d = 0
        for pos in range(1, self.code_w):
            if not self._is_power_of_2(pos):
                if d < self.data_w:
                    code[pos] = (data >> d) & 1
                d += 1

        # Compute Hamming parity bits
        for i in range(self.parity_w):
            p = 0
            for pos in range(1, self.code_w):
                if pos & (1 << i):
                    p ^= code[pos]
            code[1 << i] = p

        # Overall parity (position 0)
        code[0] = 0
        for pos in range(1, self.code_w):
            code[0] ^= code[pos]

        # Pack into integer
        result = 0
        for pos in range(self.code_w):
            result |= code[pos] << pos
        return result

    def decode(self, codeword: int) -> tuple:
        """Decode codeword. Returns (data, status, syndrome).
        status: 'ok', 'sec' (corrected), 'ded' (uncorrectable)."""
        code = [(codeword >> i) & 1 for i in range(self.code_w)]

        # Compute syndrome
        syndrome = 0
        for i in range(self.parity_w):
            s = 0
            for pos in range(1, self.code_w):
                if pos & (1 << i):
                    s ^= code[pos]
            syndrome |= s << i

        # Overall parity
        overall = 0
        for pos in range(self.code_w):
            overall ^= code[pos]

        # Correction
        corrected = list(code)
        if syndrome != 0 and overall:
            # Single-bit error at position syndrome
            if syndrome < self.code_w:
                corrected[syndrome] ^= 1

        # Determine status
        if syndrome == 0 and not overall:
            status = 'ok'
        elif syndrome != 0 and overall:
            status = 'sec'
        elif syndrome != 0 and not overall:
            status = 'ded'
        else:
            status = 'sec'  # P0-only error

        # Extract data
        data = 0
        d = 0
        for pos in range(1, self.code_w):
            if not self._is_power_of_2(pos):
                if d < self.data_w:
                    data |= corrected[pos] << d
                d += 1

        return data, status, syndrome


def _self_test():
    tests_passed = 0

    for dw in [8, 16, 32, 64]:
        m = ECCModel(dw)

        # Test 1: encode then decode — no error
        data = (1 << dw) - 1  # all ones
        code = m.encode(data)
        dec_data, status, syn = m.decode(code)
        ok = (dec_data == data and status == 'ok')
        print(f"  [{'PASS' if ok else 'FAIL'}] DATA_W={dw}: encode/decode no error")
        if ok: tests_passed += 1

        # Test 2: single-bit error — corrected
        code_err = code ^ (1 << 3)  # flip bit 3
        dec_data, status, syn = m.decode(code_err)
        ok = (dec_data == data and status == 'sec')
        print(f"  [{'PASS' if ok else 'FAIL'}] DATA_W={dw}: single-bit correction (bit 3)")
        if ok: tests_passed += 1

        # Test 3: double-bit error — detected
        code_derr = code ^ (1 << 3) ^ (1 << 5)  # flip 2 bits
        dec_data, status, syn = m.decode(code_derr)
        ok = (status == 'ded')
        print(f"  [{'PASS' if ok else 'FAIL'}] DATA_W={dw}: double-bit detection")
        if ok: tests_passed += 1

    total = 12
    print(f"\n  {tests_passed}/{total} self-tests passed")
    return tests_passed == total


if __name__ == "__main__":
    print("ECC Model Self-Test")
    print("=" * 40)
    ok = _self_test()
    exit(0 if ok else 1)
