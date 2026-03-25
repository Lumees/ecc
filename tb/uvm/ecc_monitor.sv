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
// ECC UVM Testbench -- Monitor
// =============================================================================
// Passive monitor with two logical sub-monitors:
//
//   Encode sub-monitor : captures enc_valid_i pulse and enc_data_i
//   Decode sub-monitor : captures dec_valid_o pulse and dec_data_o / status
//
// The encode analysis port emits items when encoder input is seen; the decode
// port emits items when the DUT decoder produces a result. The scoreboard
// correlates them via FIFO ordering (pipeline is in-order).
// =============================================================================

`ifndef ECC_MONITOR_SV
`define ECC_MONITOR_SV

`include "uvm_macros.svh"

class ecc_monitor extends uvm_monitor;

  import ecc_pkg::*;

  `uvm_component_utils(ecc_monitor)

  // Analysis ports
  uvm_analysis_port #(ecc_seq_item) ap_in;   // encoder stimuli
  uvm_analysis_port #(ecc_seq_item) ap_out;  // decoder results

  // Virtual interface (read-only via monitor_cb)
  virtual ecc_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_in  = new("ap_in",  this);
    ap_out = new("ap_out", this);

    if (!uvm_config_db #(virtual ecc_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "ecc_monitor: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // run_phase: fork both sub-monitors
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      monitor_encode();
      monitor_decode();
    join
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // monitor_encode: watch for enc_valid_i assertion
  // ---------------------------------------------------------------------------
  task monitor_encode();
    ecc_seq_item item;
    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.enc_valid_i === 1'b1) begin
        item = ecc_seq_item::type_id::create("mon_enc_item");
        item.enc_data = vif.monitor_cb.enc_data_i;

        `uvm_info("MON_ENC",
          $sformatf("Encode input captured: data=%h", item.enc_data),
          UVM_HIGH)
        ap_in.write(item);
      end
    end
  endtask : monitor_encode

  // ---------------------------------------------------------------------------
  // monitor_decode: watch for dec_valid_o assertion
  // ---------------------------------------------------------------------------
  task monitor_decode();
    ecc_seq_item item;
    forever begin
      @(vif.monitor_cb);
      if (vif.monitor_cb.dec_valid_o === 1'b1) begin
        item = ecc_seq_item::type_id::create("mon_dec_item");
        item.actual_data     = vif.monitor_cb.dec_data_o;
        item.actual_status   = ecc_status_t'(vif.monitor_cb.dec_status_o);
        item.actual_syndrome = vif.monitor_cb.dec_syndrome_o;

        `uvm_info("MON_DEC",
          $sformatf("Decode output captured: data=%h status=%s syndrome=%h",
            item.actual_data, item.actual_status.name(), item.actual_syndrome),
          UVM_HIGH)
        ap_out.write(item);
      end
    end
  endtask : monitor_decode

endclass : ecc_monitor

`endif // ECC_MONITOR_SV
