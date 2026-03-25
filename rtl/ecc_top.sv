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
// ECC IP — Top-level with registered I/O
// =============================================================================
// Registered encoder and decoder for pipeline integration.
// Latency: 1 cycle encode, 1 cycle decode.
// =============================================================================

`timescale 1ns/1ps

import ecc_pkg::*;

module ecc_top (
  input  logic                  clk,
  input  logic                  rst_n,

  // ── Encoder ───────────────────────────────────────────────────────────────
  input  logic                  enc_valid_i,
  input  logic [DATA_W-1:0]    enc_data_i,
  output logic                  enc_valid_o,
  output logic [CODE_W-1:0]    enc_code_o,

  // ── Decoder ───────────────────────────────────────────────────────────────
  input  logic                  dec_valid_i,
  input  logic [CODE_W-1:0]    dec_code_i,
  output logic                  dec_valid_o,
  output logic [DATA_W-1:0]    dec_data_o,
  output ecc_status_t           dec_status_o,
  output logic [PARITY_W-1:0]  dec_syndrome_o,

  // ── Info ──────────────────────────────────────────────────────────────────
  output logic [31:0]           version_o
);

  assign version_o = IP_VERSION;

  // ── Combinational core ────────────────────────────────────────────────────
  logic [CODE_W-1:0]    enc_code_comb;
  logic [DATA_W-1:0]    dec_data_comb;
  ecc_status_t           dec_status_comb;
  logic [PARITY_W-1:0]  dec_syndrome_comb;

  ecc_core u_core (
    .enc_data_i    (enc_data_i),
    .enc_code_o    (enc_code_comb),
    .dec_code_i    (dec_code_i),
    .dec_data_o    (dec_data_comb),
    .dec_status_o  (dec_status_comb),
    .dec_syndrome_o(dec_syndrome_comb)
  );

  // ── Registered outputs ────────────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      enc_valid_o    <= 1'b0;
      enc_code_o     <= '0;
      dec_valid_o    <= 1'b0;
      dec_data_o     <= '0;
      dec_status_o   <= ECC_OK;
      dec_syndrome_o <= '0;
    end else begin
      enc_valid_o    <= enc_valid_i;
      enc_code_o     <= enc_code_comb;
      dec_valid_o    <= dec_valid_i;
      dec_data_o     <= dec_data_comb;
      dec_status_o   <= dec_status_comb;
      dec_syndrome_o <= dec_syndrome_comb;
    end
  end

endmodule : ecc_top
