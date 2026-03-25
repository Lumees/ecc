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
// ECC UVM Testbench -- Top-level Module
// =============================================================================
// Instantiates:
//   - ecc_top DUT
//   - Clock generator (10 ns period)
//   - Reset sequence (active-low, deassert after 10 cycles)
//   - ecc_if virtual interface
//   - UVM config_db registration
//   - run_test() kick-off
//
// Simulation plusargs:
//   +UVM_TESTNAME=<test>   (e.g., ecc_directed_test, ecc_random_test)
// =============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"

import uvm_pkg::*;
import ecc_pkg::*;

// Include all testbench files in order of dependency
`include "ecc_seq_item.sv"
`include "ecc_if.sv"
`include "ecc_driver.sv"
`include "ecc_monitor.sv"
`include "ecc_scoreboard.sv"
`include "ecc_coverage.sv"
`include "ecc_agent.sv"
`include "ecc_env.sv"
`include "ecc_sequences.sv"
`include "ecc_tests.sv"

module ecc_tb_top;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  // 10 ns period -> 100 MHz
  initial clk = 1'b0;
  always #5ns clk = ~clk;

  // Reset: assert for 10 cycles, then release
  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    @(negedge clk);   // deassert on falling edge for clean setup
    rst_n = 1'b1;
    `uvm_info("TB_TOP", "Reset deasserted", UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Virtual interface instantiation
  // ---------------------------------------------------------------------------
  ecc_if dut_if (.clk(clk), .rst_n(rst_n));

  // ---------------------------------------------------------------------------
  // DUT instantiation
  // ---------------------------------------------------------------------------
  ecc_top dut (
    .clk            (clk),
    .rst_n          (rst_n),

    // Encoder
    .enc_valid_i    (dut_if.enc_valid_i),
    .enc_data_i     (dut_if.enc_data_i),
    .enc_valid_o    (dut_if.enc_valid_o),
    .enc_code_o     (dut_if.enc_code_o),

    // Decoder
    .dec_valid_i    (dut_if.dec_valid_i),
    .dec_code_i     (dut_if.dec_code_i),
    .dec_valid_o    (dut_if.dec_valid_o),
    .dec_data_o     (dut_if.dec_data_o),
    .dec_status_o   (dut_if.dec_status_o),
    .dec_syndrome_o (dut_if.dec_syndrome_o),

    // Info
    .version_o      (dut_if.version_o)
  );

  // ---------------------------------------------------------------------------
  // UVM config_db: register virtual interface
  // ---------------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual ecc_if)::set(
      null,          // from context (global)
      "uvm_test_top.*",
      "vif",
      dut_if
    );

    `uvm_info("TB_TOP",
      "ECC DUT instantiated, vif registered in config_db",
      UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Simulation timeout watchdog (prevents infinite hang on protocol errors)
  // ---------------------------------------------------------------------------
  initial begin
    // Allow enough time for stress test (200 txns x ~20 cycles x 10 ns)
    #1ms;
    `uvm_fatal("WATCHDOG", "Simulation timeout -- check for protocol deadlock")
  end

  // ---------------------------------------------------------------------------
  // Waveform dump (uncomment for VCD/FSDB capture)
  // ---------------------------------------------------------------------------
  // initial begin
  //   $dumpfile("ecc_tb.vcd");
  //   $dumpvars(0, ecc_tb_top);
  // end

  // ---------------------------------------------------------------------------
  // Start UVM test
  // ---------------------------------------------------------------------------
  initial begin
    run_test();
  end

endmodule : ecc_tb_top
