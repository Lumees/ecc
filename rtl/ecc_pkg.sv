// =============================================================================
// Copyright (c) 2026 Lumees Lab / Hasan Kurşun
// SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
//
// Licensed under the Apache License 2.0 with Commons Clause restriction.
// You may use this file freely for non-commercial purposes (academic,
// research, hobby, education, personal projects).
//
// COMMERCIAL USE requires a separate license from Lumees Lab.
// Contact: info@lumeeslab.com · https://lumeeslab.com
// =============================================================================
// ECC IP — Package: types, parameters, Hamming parity functions
// =============================================================================
// Implements SECDED (Single Error Correct, Double Error Detect) Hamming code.
// Supports DATA_W = 8, 16, 32, 64 with automatically computed check bits.
// =============================================================================

`timescale 1ns/1ps

package ecc_pkg;

  localparam int IP_VERSION = 32'h0001_0000;

  // ── Compile-time data width ───────────────────────────────────────────────
`ifdef ECC_PKG_DATA_W
  localparam int DATA_W = `ECC_PKG_DATA_W;
`else
  localparam int DATA_W = 32;
`endif

  // ── Check bit width calculation ───────────────────────────────────────────
  // For SECDED Hamming: need m check bits where 2^m >= DATA_W + m + 1
  // Plus 1 overall parity bit for double-error detection
  // DATA_W=8:  m=4, total check=5 (4 Hamming + 1 overall)
  // DATA_W=16: m=5, total check=6
  // DATA_W=32: m=6, total check=7
  // DATA_W=64: m=7, total check=8
  function automatic int calc_parity_bits(int dw);
    int m;
    for (m = 1; (1 << m) < (dw + m + 1); m++);
    return m;
  endfunction

  localparam int PARITY_W = calc_parity_bits(DATA_W);  // Hamming parity bits
  localparam int CHECK_W  = PARITY_W + 1;               // + overall parity
  localparam int CODE_W   = DATA_W + CHECK_W;            // total codeword width

  // ── ECC status ────────────────────────────────────────────────────────────
  typedef enum logic [1:0] {
    ECC_OK      = 2'b00,   // no error
    ECC_SEC     = 2'b01,   // single-bit error corrected
    ECC_DED     = 2'b10,   // double-bit error detected (uncorrectable)
    ECC_RSVD    = 2'b11
  } ecc_status_t;

endpackage : ecc_pkg
