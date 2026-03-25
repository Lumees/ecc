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
// ECC UVM Testbench -- Driver
// =============================================================================
// Drives ecc_top via the virtual interface clocking block.
// Protocol per DUT spec (ecc_top.sv):
//   1. Assert enc_valid_i with enc_data_i for one cycle.
//   2. Wait one cycle for enc_valid_o, capture enc_code_o.
//   3. Optionally inject bit error(s) into the codeword.
//   4. Assert dec_valid_i with (corrupted) dec_code_i for one cycle.
//   5. Wait one cycle for dec_valid_o, capture dec_data_o / status / syndrome.
// =============================================================================

`ifndef ECC_DRIVER_SV
`define ECC_DRIVER_SV

`include "uvm_macros.svh"

class ecc_driver extends uvm_driver #(ecc_seq_item);

  import ecc_pkg::*;

  `uvm_component_utils(ecc_driver)

  // Virtual interface handle
  virtual ecc_if vif;

  // Max cycles to wait for valid outputs
  localparam int VALID_TIMEOUT = 100;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase: retrieve virtual interface from config_db
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual ecc_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "ecc_driver: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // run_phase: main driver loop
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    ecc_seq_item req, rsp;

    // Initialise all driven signals to safe defaults
    vif.driver_cb.enc_valid_i <= 1'b0;
    vif.driver_cb.enc_data_i  <= '0;
    vif.driver_cb.dec_valid_i <= 1'b0;
    vif.driver_cb.dec_code_i  <= '0;

    // Wait for reset to deassert
    @(posedge vif.clk);
    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    forever begin
      // Get next item from sequencer
      seq_item_port.get_next_item(req);
      `uvm_info("DRV", $sformatf("Driving: %s", req.convert2string()), UVM_HIGH)

      // Clone for response
      rsp = ecc_seq_item::type_id::create("rsp");
      rsp.copy(req);

      // ------------------------------------------------------------------
      // Step 1: Encode
      // ------------------------------------------------------------------
      drive_encode(req);

      // ------------------------------------------------------------------
      // Step 2: Capture encoder output
      // ------------------------------------------------------------------
      capture_encode(rsp);

      // ------------------------------------------------------------------
      // Step 3: Inject errors and decode
      // ------------------------------------------------------------------
      drive_decode(rsp);

      // ------------------------------------------------------------------
      // Step 4: Capture decoder output
      // ------------------------------------------------------------------
      capture_decode(rsp);

      // Return response to sequence
      seq_item_port.item_done(rsp);
    end
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // drive_encode: present data, pulse enc_valid_i
  // ---------------------------------------------------------------------------
  task drive_encode(ecc_seq_item item);
    @(vif.driver_cb);
    vif.driver_cb.enc_valid_i <= 1'b1;
    vif.driver_cb.enc_data_i  <= item.enc_data;
    @(vif.driver_cb);
    vif.driver_cb.enc_valid_i <= 1'b0;
    vif.driver_cb.enc_data_i  <= '0;

    `uvm_info("DRV",
      $sformatf("Encode driven: data=%h", item.enc_data),
      UVM_HIGH)
  endtask : drive_encode

  // ---------------------------------------------------------------------------
  // capture_encode: wait for enc_valid_o, read enc_code_o
  // ---------------------------------------------------------------------------
  task capture_encode(ecc_seq_item rsp);
    int timeout = 0;

    while (!vif.driver_cb.enc_valid_o) begin
      @(vif.driver_cb);
      timeout++;
      if (timeout >= VALID_TIMEOUT)
        `uvm_fatal("DRV_TIMEOUT",
          $sformatf("enc_valid_o never asserted after %0d cycles", VALID_TIMEOUT))
    end

    rsp.actual_code = vif.driver_cb.enc_code_o;
    `uvm_info("DRV",
      $sformatf("Encode captured: code=%h", rsp.actual_code),
      UVM_HIGH)
  endtask : capture_encode

  // ---------------------------------------------------------------------------
  // drive_decode: inject errors then present codeword to decoder
  // ---------------------------------------------------------------------------
  task drive_decode(ecc_seq_item rsp);
    logic [CODE_W-1:0] code_to_decode;

    // Inject errors based on seq_item error control
    code_to_decode = rsp.inject_errors(rsp.actual_code);

    @(vif.driver_cb);
    vif.driver_cb.dec_valid_i <= 1'b1;
    vif.driver_cb.dec_code_i  <= code_to_decode;
    @(vif.driver_cb);
    vif.driver_cb.dec_valid_i <= 1'b0;
    vif.driver_cb.dec_code_i  <= '0;

    `uvm_info("DRV",
      $sformatf("Decode driven: code=%h (err_type=%0d)",
        code_to_decode, rsp.error_type),
      UVM_HIGH)
  endtask : drive_decode

  // ---------------------------------------------------------------------------
  // capture_decode: wait for dec_valid_o, read dec_data_o / status / syndrome
  // ---------------------------------------------------------------------------
  task capture_decode(ecc_seq_item rsp);
    int timeout = 0;

    while (!vif.driver_cb.dec_valid_o) begin
      @(vif.driver_cb);
      timeout++;
      if (timeout >= VALID_TIMEOUT)
        `uvm_fatal("DRV_TIMEOUT",
          $sformatf("dec_valid_o never asserted after %0d cycles", VALID_TIMEOUT))
    end

    rsp.actual_data     = vif.driver_cb.dec_data_o;
    rsp.actual_status   = ecc_status_t'(vif.driver_cb.dec_status_o);
    rsp.actual_syndrome = vif.driver_cb.dec_syndrome_o;

    `uvm_info("DRV",
      $sformatf("Decode captured: data=%h status=%s syndrome=%h",
        rsp.actual_data, rsp.actual_status.name(), rsp.actual_syndrome),
      UVM_HIGH)
  endtask : capture_decode

endclass : ecc_driver

`endif // ECC_DRIVER_SV
