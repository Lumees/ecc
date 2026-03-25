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
// ECC IP — AXI4-Lite Interface Wrapper
// =============================================================================
// Register map (32-bit word address, 4-byte aligned):
//
//  Offset  Name          Access  Description
//  0x00    CTRL          RW      [0]=enc_start(W,self-clear) [1]=dec_start(W,self-clear)
//  0x04    STATUS        RO      [0]=enc_done [1]=dec_done [3:2]=dec_status
//  0x08    INFO          RO      [7:0]=DATA_W [15:8]=CODE_W [23:16]=PARITY_W
//  0x0C    VERSION       RO      IP_VERSION from ecc_pkg
//  0x10    ENC_DATA      W       Data input for encoding [DATA_W-1:0]
//  0x14    ENC_CODE_LO   RO      Encoded codeword bits [31:0]
//  0x18    ENC_CODE_HI   RO      Encoded codeword bits [CODE_W-1:32] (for CODE_W>32)
//  0x1C    DEC_CODE_LO   W       Codeword for decoding bits [31:0]
//  0x20    DEC_CODE_HI   W       Codeword for decoding bits [CODE_W-1:32]
//  0x24    DEC_DATA      RO      Decoded data [DATA_W-1:0]
//  0x28    DEC_SYNDROME  RO      Syndrome [PARITY_W-1:0]
//
// Write CTRL[0]=1 to trigger encode, CTRL[1]=1 to trigger decode.
// Both bits self-clear. Results available one cycle later.
//
// irq: single-cycle output pulse when enc_done or dec_done rises.
// =============================================================================

`timescale 1ns/1ps

import ecc_pkg::*;

module ecc_axil (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite Slave
  input  logic [31:0] s_axil_awaddr,
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  output logic [1:0]  s_axil_bresp,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  input  logic [31:0] s_axil_araddr,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,

  // Interrupt — single-cycle pulse when enc_done or dec_done rises
  output logic        irq
);

  // -------------------------------------------------------------------------
  // Parameter guard — register map supports CODE_W ≤ 64 (DATA_W ≤ 32)
  // -------------------------------------------------------------------------
  initial begin
    if (DATA_W > 32)
      $fatal(1, "ecc_axil: DATA_W > 32 not supported (CODE_W exceeds 64-bit register span). Use ecc_top directly.");
  end

  // -------------------------------------------------------------------------
  // Internal registers
  // -------------------------------------------------------------------------
  logic                  enc_start_reg;
  logic                  dec_start_reg;
  logic                  enc_done_reg;
  logic                  dec_done_reg;
  logic [1:0]            dec_status_reg;
  logic [DATA_W-1:0]    enc_data_reg;
  logic [CODE_W-1:0]    enc_code_reg;
  logic [CODE_W-1:0]    dec_code_reg;
  logic [DATA_W-1:0]    dec_data_reg;
  logic [PARITY_W-1:0]  dec_syndrome_reg;

  // -------------------------------------------------------------------------
  // ECC core signals
  // -------------------------------------------------------------------------
  logic                  core_enc_valid_i;
  logic [DATA_W-1:0]    core_enc_data_i;
  logic                  core_enc_valid_o;
  logic [CODE_W-1:0]    core_enc_code_o;

  logic                  core_dec_valid_i;
  logic [CODE_W-1:0]    core_dec_code_i;
  logic                  core_dec_valid_o;
  logic [DATA_W-1:0]    core_dec_data_o;
  ecc_status_t           core_dec_status_o;
  logic [PARITY_W-1:0]  core_dec_syndrome_o;

  logic [31:0]           core_version;

  ecc_top u_ecc (
    .clk            (clk),
    .rst_n          (rst_n),
    .enc_valid_i    (core_enc_valid_i),
    .enc_data_i     (core_enc_data_i),
    .enc_valid_o    (core_enc_valid_o),
    .enc_code_o     (core_enc_code_o),
    .dec_valid_i    (core_dec_valid_i),
    .dec_code_i     (core_dec_code_i),
    .dec_valid_o    (core_dec_valid_o),
    .dec_data_o     (core_dec_data_o),
    .dec_status_o   (core_dec_status_o),
    .dec_syndrome_o (core_dec_syndrome_o),
    .version_o      (core_version)
  );

  // -------------------------------------------------------------------------
  // AXI4-Lite write path
  // -------------------------------------------------------------------------
  logic [5:0]  wr_addr;
  logic [31:0] wdata_lat;
  logic        aw_active, w_active;

  assign s_axil_awready = !aw_active;
  assign s_axil_wready  = !w_active;
  assign s_axil_bresp   = 2'b00;

  // Drive core inputs
  assign core_enc_data_i  = enc_data_reg;
  assign core_dec_code_i  = dec_code_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_active          <= 1'b0;
      w_active           <= 1'b0;
      wr_addr            <= '0;
      wdata_lat          <= '0;
      s_axil_bvalid      <= 1'b0;
      enc_start_reg      <= 1'b0;
      dec_start_reg      <= 1'b0;
      enc_done_reg       <= 1'b0;
      dec_done_reg       <= 1'b0;
      dec_status_reg     <= 2'b00;
      enc_data_reg       <= '0;
      enc_code_reg       <= '0;
      dec_code_reg       <= '0;
      dec_data_reg       <= '0;
      dec_syndrome_reg   <= '0;
      core_enc_valid_i   <= 1'b0;
      core_dec_valid_i   <= 1'b0;
    end else begin
      // ── AXI4-Lite write handshake ──────────────────────────────────────
      if (s_axil_awvalid && s_axil_awready) begin
        wr_addr   <= s_axil_awaddr[7:2];
        aw_active <= 1'b1;
      end
      if (s_axil_wvalid && s_axil_wready) begin
        wdata_lat <= s_axil_wdata;
        w_active  <= 1'b1;
      end
      if (s_axil_bvalid && s_axil_bready)
        s_axil_bvalid <= 1'b0;

      // ── Default: de-assert pulses ──────────────────────────────────────
      core_enc_valid_i <= 1'b0;
      core_dec_valid_i <= 1'b0;
      enc_start_reg    <= 1'b0;
      dec_start_reg    <= 1'b0;

      // ── Latch core results ─────────────────────────────────────────────
      if (core_enc_valid_o) begin
        enc_code_reg <= core_enc_code_o;
        enc_done_reg <= 1'b1;
      end
      if (core_dec_valid_o) begin
        dec_data_reg     <= core_dec_data_o;
        dec_status_reg   <= core_dec_status_o;
        dec_syndrome_reg <= core_dec_syndrome_o;
        dec_done_reg     <= 1'b1;
      end

      // ── Register writes ────────────────────────────────────────────────
      if (aw_active && w_active) begin
        aw_active     <= 1'b0;
        w_active      <= 1'b0;
        s_axil_bvalid <= 1'b1;
        unique case (wr_addr)
          6'h00: begin  // CTRL
            if (wdata_lat[0]) begin
              enc_start_reg    <= 1'b1;
              core_enc_valid_i <= 1'b1;
              enc_done_reg     <= 1'b0;
            end
            if (wdata_lat[1]) begin
              dec_start_reg    <= 1'b1;
              core_dec_valid_i <= 1'b1;
              dec_done_reg     <= 1'b0;
            end
          end
          6'h04: begin  // ENC_DATA
            enc_data_reg <= wdata_lat[DATA_W-1:0];
          end
          6'h07: begin  // DEC_CODE_LO
            dec_code_reg[31:0] <= wdata_lat;
          end
          6'h08: begin  // DEC_CODE_HI
            if (CODE_W > 32)
              dec_code_reg[CODE_W-1:32] <= wdata_lat[CODE_W-33:0];
          end
          default: ;
        endcase
      end
    end
  end

  // -------------------------------------------------------------------------
  // Interrupt: single-cycle pulse when enc_done or dec_done rises
  // -------------------------------------------------------------------------
  logic enc_done_prev, dec_done_prev;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      enc_done_prev <= 1'b0;
      dec_done_prev <= 1'b0;
      irq           <= 1'b0;
    end else begin
      enc_done_prev <= enc_done_reg;
      dec_done_prev <= dec_done_reg;
      irq <= (enc_done_reg & ~enc_done_prev) | (dec_done_reg & ~dec_done_prev);
    end
  end

  // -------------------------------------------------------------------------
  // AXI4-Lite read logic
  // -------------------------------------------------------------------------
  assign s_axil_rresp = 2'b00;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b1;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= '0;
    end else begin
      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b1;
        unique case (s_axil_araddr[7:2])
          6'h00: s_axil_rdata <= 32'h0;  // CTRL (write-only triggers)
          6'h01: s_axil_rdata <= {28'h0, dec_status_reg, dec_done_reg, enc_done_reg};  // STATUS
          6'h02: s_axil_rdata <= {8'h0, PARITY_W[7:0], CODE_W[7:0], DATA_W[7:0]};    // INFO
          6'h03: s_axil_rdata <= core_version;                                          // VERSION
          6'h04: s_axil_rdata <= {{(32-DATA_W){1'b0}}, enc_data_reg};                  // ENC_DATA
          6'h05: s_axil_rdata <= enc_code_reg[31:0];                                    // ENC_CODE_LO
          6'h06: s_axil_rdata <= (CODE_W > 32) ?
                                 {{(64-CODE_W){1'b0}}, enc_code_reg[CODE_W-1:32]} :
                                 32'h0;                                                  // ENC_CODE_HI
          6'h07: s_axil_rdata <= dec_code_reg[31:0];                                    // DEC_CODE_LO
          6'h08: s_axil_rdata <= (CODE_W > 32) ?
                                 {{(64-CODE_W){1'b0}}, dec_code_reg[CODE_W-1:32]} :
                                 32'h0;                                                  // DEC_CODE_HI
          6'h09: s_axil_rdata <= {{(32-DATA_W){1'b0}}, dec_data_reg};                  // DEC_DATA
          6'h0A: s_axil_rdata <= {{(32-PARITY_W){1'b0}}, dec_syndrome_reg};            // DEC_SYNDROME
          default: s_axil_rdata <= 32'hDEAD_BEEF;
        endcase
      end
      if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid  <= 1'b0;
        s_axil_arready <= 1'b1;
      end
    end
  end

endmodule : ecc_axil
