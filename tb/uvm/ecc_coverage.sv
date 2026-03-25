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
// ECC UVM Testbench -- Functional Coverage Collector
// =============================================================================
// Subscribes to the context analysis port.
// Covergroups:
//   cg_ecc : data_w x error_type (none/SEC/DED) x bit_position cross
// =============================================================================

`ifndef ECC_COVERAGE_SV
`define ECC_COVERAGE_SV

`include "uvm_macros.svh"

class ecc_coverage extends uvm_subscriber #(ecc_seq_item);

  import ecc_pkg::*;

  `uvm_component_utils(ecc_coverage)

  // Current sampled item fields (written in write() before sampling)
  logic [DATA_W-1:0] cov_enc_data;
  int unsigned       cov_error_type;
  int unsigned       cov_error_pos_0;
  int unsigned       cov_error_pos_1;

  // ---------------------------------------------------------------------------
  // Covergroup: ECC configuration and error space
  // ---------------------------------------------------------------------------
  covergroup cg_ecc;
    option.per_instance = 1;
    option.name         = "cg_ecc";
    option.comment      = "ECC data width, error type, and bit position coverage";

    cp_data_word: coverpoint cov_enc_data {
      bins all_zeros   = {0};
      bins all_ones    = {{DATA_W{1'b1}}};
      bins low_quarter = {[1 : (1 << (DATA_W/4)) - 1]};
      bins other       = default;
    }

    cp_error_type: coverpoint cov_error_type {
      bins no_error = {0};
      bins sec      = {1};
      bins ded      = {2};
    }

    cp_bit_position: coverpoint cov_error_pos_0 {
      bins positions[] = {[0:CODE_W-1]};
    }

    cp_bit_position_1: coverpoint cov_error_pos_1 {
      bins positions[] = {[0:CODE_W-1]};
    }

    // Cross: error_type x bit_position (primary)
    cx_error_pos: cross cp_error_type, cp_bit_position {
      // Only meaningful for SEC/DED
      ignore_bins no_err_pos = binsof(cp_error_type) intersect {0};
    }

    // Cross: data_word x error_type
    cx_data_error: cross cp_data_word, cp_error_type;

    // Cross: data_word x error_type x bit_position
    cx_data_error_pos: cross cp_data_word, cp_error_type, cp_bit_position {
      ignore_bins no_err_pos = binsof(cp_error_type) intersect {0};
    }
  endgroup : cg_ecc

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_ecc = new();
  endfunction : new

  // ---------------------------------------------------------------------------
  // write(): called by analysis port on each context transaction
  // ---------------------------------------------------------------------------
  function void write(ecc_seq_item t);
    cov_enc_data    = t.enc_data;
    cov_error_type  = t.error_type;
    cov_error_pos_0 = t.error_pos_0;
    cov_error_pos_1 = t.error_pos_1;

    cg_ecc.sample();

    `uvm_info("COV",
      $sformatf("Sampled: data=%h err_type=%0d pos0=%0d pos1=%0d",
        cov_enc_data, cov_error_type, cov_error_pos_0, cov_error_pos_1),
      UVM_DEBUG)
  endfunction : write

  // ---------------------------------------------------------------------------
  // report_phase: print coverage summary
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info("COV_REPORT",
      $sformatf("cg_ecc coverage: %.2f%%", cg_ecc.get_coverage()),
      UVM_NONE)
  endfunction : report_phase

endclass : ecc_coverage

`endif // ECC_COVERAGE_SV
