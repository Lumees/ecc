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
// ECC UVM Testbench -- Sequences
// =============================================================================
// All sequences in one file. Each sequence:
//   1. Randomises (or hard-codes) a seq_item
//   2. Starts it on the sequencer
//   3. Writes the full item to env.ap_context so the scoreboard reference
//      model has all fields (including error injection info) available.
//
// Sequences access ap_context through a direct handle set in the test's
// build_phase.
// =============================================================================

`ifndef ECC_SEQUENCES_SV
`define ECC_SEQUENCES_SV

`include "uvm_macros.svh"

// ============================================================================
// Base sequence
// ============================================================================
class ecc_base_seq extends uvm_sequence #(ecc_seq_item);

  import ecc_pkg::*;

  `uvm_object_utils(ecc_base_seq)

  // Handle to the env's context analysis port -- set by test before starting
  uvm_analysis_port #(ecc_seq_item) ap_context;

  function new(string name = "ecc_base_seq");
    super.new(name);
  endfunction : new

  // Helper: send one item and publish context
  task send_item(ecc_seq_item item);
    start_item(item);
    if (!item.randomize())
      `uvm_fatal("SEQ_RAND", "Failed to randomise seq_item")
    finish_item(item);

    // Publish full item so scoreboard has error injection info
    if (ap_context != null)
      ap_context.write(item);
    else
      `uvm_warning("SEQ_CTX", "ap_context handle is null -- scoreboard may not have context")
  endtask : send_item

  // Helper: send a pre-built (non-randomised) item directly
  task send_fixed_item(ecc_seq_item item);
    start_item(item);
    finish_item(item);
    if (ap_context != null)
      ap_context.write(item);
    else
      `uvm_warning("SEQ_CTX", "ap_context handle is null -- scoreboard may not have context")
  endtask : send_fixed_item

  virtual task body();
    `uvm_warning("SEQ", "ecc_base_seq::body() called -- override in derived class")
  endtask : body

endclass : ecc_base_seq


// ============================================================================
// Directed sequence: known patterns with no error, SEC, and DED
// ============================================================================
class ecc_directed_seq extends ecc_base_seq;

  `uvm_object_utils(ecc_directed_seq)

  function new(string name = "ecc_directed_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    ecc_seq_item item;

    // ----------------------------------------------------------------
    // Test 1: All-zeros data, no error
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_zero_noerr");
    item.enc_data    = '0;
    item.error_type  = 0;
    item.error_pos_0 = 0;
    item.error_pos_1 = 0;
    `uvm_info("SEQ_DIR", "Sending all-zeros data, no error", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 2: All-ones data, no error
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_ones_noerr");
    item.enc_data    = {DATA_W{1'b1}};
    item.error_type  = 0;
    item.error_pos_0 = 0;
    item.error_pos_1 = 0;
    `uvm_info("SEQ_DIR", "Sending all-ones data, no error", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 3: Walking-one data, no error
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_walk1_noerr");
    item.enc_data    = {{(DATA_W-1){1'b0}}, 1'b1};
    item.error_type  = 0;
    item.error_pos_0 = 0;
    item.error_pos_1 = 0;
    `uvm_info("SEQ_DIR", "Sending walking-one data, no error", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 4: All-zeros data, single-bit error at bit 0
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_zero_sec0");
    item.enc_data    = '0;
    item.error_type  = 1;
    item.error_pos_0 = 0;
    item.error_pos_1 = 0;
    `uvm_info("SEQ_DIR", "Sending all-zeros data, SEC at bit 0", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 5: All-ones data, single-bit error at MSB of codeword
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_ones_sec_msb");
    item.enc_data    = {DATA_W{1'b1}};
    item.error_type  = 1;
    item.error_pos_0 = CODE_W - 1;
    item.error_pos_1 = 0;
    `uvm_info("SEQ_DIR",
      $sformatf("Sending all-ones data, SEC at bit %0d", CODE_W - 1), UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 6: All-zeros data, double-bit error at bits 0 and 1
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_zero_ded01");
    item.enc_data    = '0;
    item.error_type  = 2;
    item.error_pos_0 = 0;
    item.error_pos_1 = 1;
    `uvm_info("SEQ_DIR", "Sending all-zeros data, DED at bits 0,1", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 7: Pattern 0xA5..A5, DED at distant bits
    // ----------------------------------------------------------------
    item = ecc_seq_item::type_id::create("dir_a5_ded");
    item.enc_data    = {(DATA_W/8){8'hA5}};
    item.error_type  = 2;
    item.error_pos_0 = 0;
    item.error_pos_1 = CODE_W - 1;
    `uvm_info("SEQ_DIR",
      $sformatf("Sending 0xA5 pattern data, DED at bits 0 and %0d", CODE_W - 1),
      UVM_MEDIUM)
    send_fixed_item(item);

  endtask : body

endclass : ecc_directed_seq


// ============================================================================
// Random sequence
// ============================================================================
class ecc_random_seq extends ecc_base_seq;

  `uvm_object_utils(ecc_random_seq)

  int unsigned num_transactions = 20;

  function new(string name = "ecc_random_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    ecc_seq_item item;

    repeat (num_transactions) begin
      item = ecc_seq_item::type_id::create("rand_ecc");
      send_item(item);
    end

    `uvm_info("SEQ_RAND",
      $sformatf("Completed %0d random ECC transactions", num_transactions),
      UVM_MEDIUM)
  endtask : body

endclass : ecc_random_seq


// ============================================================================
// Stress sequence (back-to-back transactions, no idle cycles between items)
// ============================================================================
class ecc_stress_seq extends ecc_base_seq;

  `uvm_object_utils(ecc_stress_seq)

  int unsigned num_transactions = 100;

  function new(string name = "ecc_stress_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    ecc_seq_item item;

    repeat (num_transactions) begin
      item = ecc_seq_item::type_id::create("stress_ecc");
      start_item(item);
      if (!item.randomize())
        `uvm_fatal("SEQ_RAND", "Failed to randomise stress seq_item")
      finish_item(item);
      if (ap_context != null) ap_context.write(item);
    end

    `uvm_info("SEQ_STRESS",
      $sformatf("Completed %0d back-to-back stress ECC transactions", num_transactions),
      UVM_MEDIUM)
  endtask : body

endclass : ecc_stress_seq

`endif // ECC_SEQUENCES_SV
