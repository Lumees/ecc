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
// ECC IP — Core encoder/decoder
// =============================================================================
// Combinational SECDED Hamming encoder and decoder.
// Encoder: data_in[DATA_W-1:0] → codeword[CODE_W-1:0]
// Decoder: codeword[CODE_W-1:0] → data_out[DATA_W-1:0] + status
//
// The codeword layout follows standard Hamming convention:
//   Position 0: overall parity (P0)
//   Position 2^i: check bit Pi (i=0..PARITY_W-1)
//   Other positions: data bits
// =============================================================================

`timescale 1ns/1ps

import ecc_pkg::*;

module ecc_core (
  // ── Encoder ───────────────────────────────────────────────────────────────
  input  logic [DATA_W-1:0]   enc_data_i,
  output logic [CODE_W-1:0]   enc_code_o,

  // ── Decoder ───────────────────────────────────────────────────────────────
  input  logic [CODE_W-1:0]   dec_code_i,
  output logic [DATA_W-1:0]   dec_data_o,
  output ecc_status_t          dec_status_o,
  output logic [PARITY_W-1:0] dec_syndrome_o
);

  // ── Encoder ───────────────────────────────────────────────────────────────
  // Place data bits into non-power-of-2 positions, compute parity bits

  logic [CODE_W-1:0] enc_raw;
  logic [PARITY_W-1:0] enc_parity;
  logic enc_p0;

  always_comb begin
    enc_raw = '0;

    // Place data bits (skip positions that are powers of 2 and position 0)
    for (int pos = 1, d = 0; pos < CODE_W; pos++) begin
      if ((pos & (pos - 1)) != 0) begin
        if (d < DATA_W)
          enc_raw[pos] = enc_data_i[d];
        d++;
      end
    end

    // Compute Hamming parity bits (at positions 2^i)
    for (int i = 0; i < PARITY_W; i++) begin
      enc_parity[i] = 1'b0;
      for (int pos = 1; pos < CODE_W; pos++) begin
        if (pos & (1 << i))
          enc_parity[i] = enc_parity[i] ^ enc_raw[pos];
      end
      enc_raw[1 << i] = enc_parity[i];
    end

    // Overall parity (position 0) = XOR of all other bits
    enc_p0 = 1'b0;
    for (int pos = 1; pos < CODE_W; pos++)
      enc_p0 = enc_p0 ^ enc_raw[pos];
    enc_raw[0] = enc_p0;

    enc_code_o = enc_raw;
  end

  // ── Decoder ───────────────────────────────────────────────────────────────
  // Compute syndrome, correct single-bit errors, detect double-bit errors

  logic [PARITY_W-1:0] syndrome;
  logic                 overall_parity;
  logic [CODE_W-1:0]   corrected;

  always_comb begin
    // Compute syndrome (XOR of parity groups)
    for (int i = 0; i < PARITY_W; i++) begin
      automatic logic s = 1'b0;
      for (int pos = 1; pos < CODE_W; pos++) begin
        if (pos & (1 << i))
          s = s ^ dec_code_i[pos];
      end
      syndrome[i] = s;
    end

    // Overall parity check (XOR of all bits including P0)
    overall_parity = 1'b0;
    for (int pos = 0; pos < CODE_W; pos++)
      overall_parity = overall_parity ^ dec_code_i[pos];

    // Correction
    corrected = dec_code_i;
    if (syndrome != '0 && overall_parity) begin
      // Single-bit error: syndrome points to error position
      if (int'(syndrome) < CODE_W)
        corrected[syndrome] = ~dec_code_i[syndrome];
    end

    // Extract data bits from corrected codeword
    dec_data_o = '0;
    for (int pos = 1, d = 0; pos < CODE_W; pos++) begin
      if ((pos & (pos - 1)) != 0) begin
        if (d < DATA_W)
          dec_data_o[d] = corrected[pos];
        d++;
      end
    end

    // Status
    dec_syndrome_o = syndrome;
    if (syndrome == '0 && !overall_parity)
      dec_status_o = ECC_OK;
    else if (syndrome != '0 && overall_parity)
      dec_status_o = ECC_SEC;    // single error corrected
    else if (syndrome != '0 && !overall_parity)
      dec_status_o = ECC_DED;    // double error detected
    else
      dec_status_o = ECC_SEC;    // P0-only error (correctable)
  end

endmodule : ecc_core
