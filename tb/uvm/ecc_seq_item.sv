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
// ECC UVM Testbench -- Sequence Item
// =============================================================================
// Represents one complete ECC encode-then-decode transaction.
// Fields: input data, error injection control, and captured DUT responses.
// =============================================================================

`ifndef ECC_SEQ_ITEM_SV
`define ECC_SEQ_ITEM_SV

`include "uvm_macros.svh"

class ecc_seq_item extends uvm_sequence_item;

  import ecc_pkg::*;

  `uvm_object_utils_begin(ecc_seq_item)
    `uvm_field_int (enc_data,       UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (error_type,     UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (error_pos_0,    UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (error_pos_1,    UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (actual_code,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (actual_data,    UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (actual_status,  UVM_ALL_ON | UVM_DEC)
    `uvm_field_int (actual_syndrome,UVM_ALL_ON | UVM_HEX)
  `uvm_object_utils_end

  // -------------------------------------------------------------------------
  // Stimulus fields (randomised)
  // -------------------------------------------------------------------------
  rand logic [DATA_W-1:0] enc_data;       // data to encode

  // Error injection control:
  //   0 = no error, 1 = single-bit error (SEC), 2 = double-bit error (DED)
  rand int unsigned       error_type;
  rand int unsigned       error_pos_0;    // first bit to flip (0..CODE_W-1)
  rand int unsigned       error_pos_1;    // second bit to flip (DED only)

  // -------------------------------------------------------------------------
  // Response fields (captured from DUT)
  // -------------------------------------------------------------------------
  logic [CODE_W-1:0]      actual_code;     // encoder output
  logic [DATA_W-1:0]      actual_data;     // decoder output
  ecc_status_t            actual_status;   // decoder status
  logic [PARITY_W-1:0]    actual_syndrome; // decoder syndrome

  // -------------------------------------------------------------------------
  // Constraints
  // -------------------------------------------------------------------------

  // Error type: no error, SEC, or DED
  constraint c_error_type {
    error_type inside {[0:2]};
    error_type dist { 0 := 40, 1 := 40, 2 := 20 };
  }

  // Bit positions must be valid codeword bit indices
  constraint c_error_pos_0 {
    error_pos_0 inside {[0:CODE_W-1]};
  }

  constraint c_error_pos_1 {
    error_pos_1 inside {[0:CODE_W-1]};
  }

  // For DED, the two flipped bits must differ
  constraint c_ded_different {
    (error_type == 2) -> (error_pos_0 != error_pos_1);
  }

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "ecc_seq_item");
    super.new(name);
  endfunction : new

  // -------------------------------------------------------------------------
  // Convenience: inject error(s) into a codeword
  // -------------------------------------------------------------------------
  function logic [CODE_W-1:0] inject_errors(logic [CODE_W-1:0] code);
    logic [CODE_W-1:0] corrupted;
    corrupted = code;
    if (error_type >= 1) corrupted[error_pos_0] = ~corrupted[error_pos_0];
    if (error_type >= 2) corrupted[error_pos_1] = ~corrupted[error_pos_1];
    return corrupted;
  endfunction : inject_errors

  // Short printable summary
  function string convert2string();
    return $sformatf(
      "ECC | data=%h err_type=%0d pos0=%0d pos1=%0d | dec_data=%h status=%s syndrome=%h",
      enc_data,
      error_type,
      error_pos_0,
      error_pos_1,
      actual_data,
      actual_status.name(),
      actual_syndrome
    );
  endfunction : convert2string

endclass : ecc_seq_item

`endif // ECC_SEQ_ITEM_SV
