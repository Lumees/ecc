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
// ECC IP — Wishbone B4 Classic Interface Wrapper
// =============================================================================
// Same register map as ecc_axil.sv.
//
//  Offset  Name          Access  Description
//  0x00    CTRL          RW      [0]=enc_start(W,self-clear) [1]=dec_start(W,self-clear)
//  0x04    STATUS        RO      [0]=enc_done [1]=dec_done [3:2]=dec_status
//  0x08    INFO          RO      [7:0]=DATA_W [15:8]=CODE_W [23:16]=PARITY_W
//  0x0C    VERSION       RO      IP_VERSION from ecc_pkg
//  0x10    ENC_DATA      W       Data input for encoding [DATA_W-1:0]
//  0x14    ENC_CODE_LO   RO      Encoded codeword bits [31:0]
//  0x18    ENC_CODE_HI   RO      Encoded codeword bits [CODE_W-1:32]
//  0x1C    DEC_CODE_LO   W       Codeword for decoding bits [31:0]
//  0x20    DEC_CODE_HI   W       Codeword for decoding bits [CODE_W-1:32]
//  0x24    DEC_DATA      RO      Decoded data [DATA_W-1:0]
//  0x28    DEC_SYNDROME  RO      Syndrome [PARITY_W-1:0]
// =============================================================================

`timescale 1ns/1ps

import ecc_pkg::*;

module ecc_wb (
  // Wishbone system
  input  logic        CLK_I,
  input  logic        RST_I,

  // Wishbone slave
  input  logic [31:0] ADR_I,
  input  logic [31:0] DAT_I,
  output logic [31:0] DAT_O,
  input  logic        WE_I,
  input  logic [3:0]  SEL_I,
  input  logic        STB_I,
  input  logic        CYC_I,
  output logic        ACK_O,
  output logic        ERR_O,
  output logic        RTY_O,

  // Interrupt
  output logic        irq
);

  // ── Parameter guard — register map supports CODE_W ≤ 64 (DATA_W ≤ 32) ──
  initial begin
    if (DATA_W > 32)
      $fatal(1, "ecc_wb: DATA_W > 32 not supported (CODE_W exceeds 64-bit register span). Use ecc_top directly.");
  end

  assign ERR_O = 1'b0;
  assign RTY_O = 1'b0;

  // ── Internal registers ────────────────────────────────────────────────────
  logic                  enc_done_reg;
  logic                  dec_done_reg;
  logic [1:0]            dec_status_reg;
  logic [DATA_W-1:0]    enc_data_reg;
  logic [CODE_W-1:0]    enc_code_reg;
  logic [CODE_W-1:0]    dec_code_reg;
  logic [DATA_W-1:0]    dec_data_reg;
  logic [PARITY_W-1:0]  dec_syndrome_reg;

  // ── ECC top signals ──────────────────────────────────────────────────────
  logic                  top_enc_valid_i;
  logic                  top_enc_valid_o;
  logic [CODE_W-1:0]    top_enc_code_o;

  logic                  top_dec_valid_i;
  logic                  top_dec_valid_o;
  logic [DATA_W-1:0]    top_dec_data_o;
  ecc_status_t           top_dec_status_o;
  logic [PARITY_W-1:0]  top_dec_syndrome_o;

  logic [31:0]           top_version;

  ecc_top u_ecc (
    .clk            (CLK_I),
    .rst_n          (~RST_I),
    .enc_valid_i    (top_enc_valid_i),
    .enc_data_i     (enc_data_reg),
    .enc_valid_o    (top_enc_valid_o),
    .enc_code_o     (top_enc_code_o),
    .dec_valid_i    (top_dec_valid_i),
    .dec_code_i     (dec_code_reg),
    .dec_valid_o    (top_dec_valid_o),
    .dec_data_o     (top_dec_data_o),
    .dec_status_o   (top_dec_status_o),
    .dec_syndrome_o (top_dec_syndrome_o),
    .version_o      (top_version)
  );

  // ── IRQ: registered pulse on done rising edge ────────────────────────────
  logic enc_done_prev, dec_done_prev;
  always_ff @(posedge CLK_I) begin
    if (RST_I) begin
      enc_done_prev <= 1'b0;
      dec_done_prev <= 1'b0;
      irq           <= 1'b0;
    end else begin
      enc_done_prev <= enc_done_reg;
      dec_done_prev <= dec_done_reg;
      irq <= (enc_done_reg & ~enc_done_prev) | (dec_done_reg & ~dec_done_prev);
    end
  end

  // ── Bus logic ────────────────────────────────────────────────────────────
  always_ff @(posedge CLK_I) begin
    if (RST_I) begin
      ACK_O            <= 1'b0;
      DAT_O            <= '0;
      enc_done_reg     <= 1'b0;
      dec_done_reg     <= 1'b0;
      dec_status_reg   <= 2'b00;
      enc_data_reg     <= '0;
      enc_code_reg     <= '0;
      dec_code_reg     <= '0;
      dec_data_reg     <= '0;
      dec_syndrome_reg <= '0;
      top_enc_valid_i  <= 1'b0;
      top_dec_valid_i  <= 1'b0;
    end else begin
      ACK_O           <= 1'b0;
      top_enc_valid_i <= 1'b0;
      top_dec_valid_i <= 1'b0;

      // Latch core results
      if (top_enc_valid_o) begin
        enc_code_reg <= top_enc_code_o;
        enc_done_reg <= 1'b1;
      end
      if (top_dec_valid_o) begin
        dec_data_reg     <= top_dec_data_o;
        dec_status_reg   <= top_dec_status_o;
        dec_syndrome_reg <= top_dec_syndrome_o;
        dec_done_reg     <= 1'b1;
      end

      // ── Wishbone transaction ────────────────────────────────────────────
      if (CYC_I && STB_I && !ACK_O) begin
        ACK_O <= 1'b1;

        if (WE_I) begin
          unique case (ADR_I[5:2])
            4'h0: begin  // CTRL
              if (DAT_I[0]) begin
                top_enc_valid_i <= 1'b1;
                enc_done_reg    <= 1'b0;
              end
              if (DAT_I[1]) begin
                top_dec_valid_i <= 1'b1;
                dec_done_reg    <= 1'b0;
              end
            end
            4'h4: begin  // ENC_DATA
              enc_data_reg <= DAT_I[DATA_W-1:0];
            end
            4'h7: begin  // DEC_CODE_LO
              dec_code_reg[31:0] <= DAT_I;
            end
            4'h8: begin  // DEC_CODE_HI
              if (CODE_W > 32)
                dec_code_reg[CODE_W-1:32] <= DAT_I[CODE_W-33:0];
            end
            default: ;
          endcase
        end else begin
          // Read
          unique case (ADR_I[5:2])
            4'h0: DAT_O <= 32'h0;  // CTRL (write-only triggers)
            4'h1: DAT_O <= {28'd0, dec_status_reg, dec_done_reg, enc_done_reg};  // STATUS
            4'h2: DAT_O <= {8'd0, PARITY_W[7:0], CODE_W[7:0], DATA_W[7:0]};    // INFO
            4'h3: DAT_O <= top_version;                                            // VERSION
            4'h4: DAT_O <= {{(32-DATA_W){1'b0}}, enc_data_reg};                  // ENC_DATA
            4'h5: DAT_O <= enc_code_reg[31:0];                                    // ENC_CODE_LO
            4'h6: DAT_O <= (CODE_W > 32) ?
                           {{(64-CODE_W){1'b0}}, enc_code_reg[CODE_W-1:32]} :
                           32'h0;                                                  // ENC_CODE_HI
            4'h7: DAT_O <= dec_code_reg[31:0];                                    // DEC_CODE_LO
            4'h8: DAT_O <= (CODE_W > 32) ?
                           {{(64-CODE_W){1'b0}}, dec_code_reg[CODE_W-1:32]} :
                           32'h0;                                                  // DEC_CODE_HI
            4'h9: DAT_O <= {{(32-DATA_W){1'b0}}, dec_data_reg};                  // DEC_DATA
            4'hA: DAT_O <= {{(32-PARITY_W){1'b0}}, dec_syndrome_reg};            // DEC_SYNDROME
            default: DAT_O <= 32'hDEAD_BEEF;
          endcase
        end
      end
    end
  end

endmodule : ecc_wb
