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
// ECC UVM Testbench -- Virtual Interface
// =============================================================================
// Provides a SystemVerilog interface wrapping all ecc_top ports.
// =============================================================================

`timescale 1ns/1ps

interface ecc_if (input logic clk, input logic rst_n);

  import ecc_pkg::*;

  // ---------------------------------------------------------------------------
  // DUT ports (all driven/sampled here)
  // ---------------------------------------------------------------------------

  // Encoder
  logic                  enc_valid_i;
  logic [DATA_W-1:0]    enc_data_i;
  logic                  enc_valid_o;
  logic [CODE_W-1:0]    enc_code_o;

  // Decoder
  logic                  dec_valid_i;
  logic [CODE_W-1:0]    dec_code_i;
  logic                  dec_valid_o;
  logic [DATA_W-1:0]    dec_data_o;
  ecc_status_t           dec_status_o;
  logic [PARITY_W-1:0]  dec_syndrome_o;

  // Info
  logic [31:0]           version_o;

  // ---------------------------------------------------------------------------
  // Driver clocking block (active driving on posedge; sample 1-step before edge)
  // ---------------------------------------------------------------------------
  clocking driver_cb @(posedge clk);
    default input  #1step
            output #1step;

    // Encoder -- driven by driver
    output enc_valid_i;
    output enc_data_i;
    input  enc_valid_o;
    input  enc_code_o;

    // Decoder -- driven by driver
    output dec_valid_i;
    output dec_code_i;
    input  dec_valid_o;
    input  dec_data_o;
    input  dec_status_o;
    input  dec_syndrome_o;

    // Info
    input  version_o;
  endclocking : driver_cb

  // ---------------------------------------------------------------------------
  // Monitor clocking block (passive -- only inputs)
  // ---------------------------------------------------------------------------
  clocking monitor_cb @(posedge clk);
    default input #1step;

    input enc_valid_i;
    input enc_data_i;
    input enc_valid_o;
    input enc_code_o;

    input dec_valid_i;
    input dec_code_i;
    input dec_valid_o;
    input dec_data_o;
    input dec_status_o;
    input dec_syndrome_o;

    input version_o;
  endclocking : monitor_cb

  // ---------------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------------
  modport driver_mp  (clocking driver_cb,  input clk, input rst_n);
  modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : ecc_if
