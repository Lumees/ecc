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
// ECC UVM Testbench -- Scoreboard
// =============================================================================
// Self-checking scoreboard:
//   - Receives full-context items via ae_context (from sequence)
//   - Receives DUT output items via ae_out (from output monitor)
//   - Verifies:
//       * No error   -> decoded data == original data, status == ECC_OK
//       * SEC error  -> decoded data == original data, status == ECC_SEC
//       * DED error  -> status == ECC_DED (data may be corrupted)
//   - Reports pass/fail counts in check_phase
// =============================================================================

`ifndef ECC_SCOREBOARD_SV
`define ECC_SCOREBOARD_SV

`include "uvm_macros.svh"

class ecc_scoreboard extends uvm_scoreboard;

  import ecc_pkg::*;

  `uvm_component_utils(ecc_scoreboard)

  // TLM FIFOs fed from the monitor / sequence analysis ports
  uvm_tlm_analysis_fifo #(ecc_seq_item) fifo_in;
  uvm_tlm_analysis_fifo #(ecc_seq_item) fifo_out;
  uvm_tlm_analysis_fifo #(ecc_seq_item) fifo_context;

  // Analysis exports (connected in env)
  uvm_analysis_export #(ecc_seq_item) ae_in;
  uvm_analysis_export #(ecc_seq_item) ae_out;
  uvm_analysis_export #(ecc_seq_item) ae_context;

  // Counters
  int unsigned pass_count;
  int unsigned fail_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    pass_count = 0;
    fail_count = 0;
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    fifo_in      = new("fifo_in",      this);
    fifo_out     = new("fifo_out",     this);
    fifo_context = new("fifo_context", this);
    ae_in        = new("ae_in",        this);
    ae_out       = new("ae_out",       this);
    ae_context   = new("ae_context",   this);
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // connect_phase: wire exports to FIFOs
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    ae_in.connect      (fifo_in.analysis_export);
    ae_out.connect     (fifo_out.analysis_export);
    ae_context.connect (fifo_context.analysis_export);
  endfunction : connect_phase

  // ---------------------------------------------------------------------------
  // run_phase: drain FIFOs and check
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    ecc_seq_item stim_item, resp_item, ctx_item;

    forever begin
      // Wait for a DUT decoder output
      fifo_out.get(resp_item);

      // Get matching encoder stimulus (in-order pipeline)
      fifo_in.get(stim_item);

      // Get full context (sent by the sequence, includes error injection info)
      fifo_context.get(ctx_item);

      // Check based on error type
      case (ctx_item.error_type)
        // -----------------------------------------------------------------
        // No error: decoded data must match original, status must be ECC_OK
        // -----------------------------------------------------------------
        0: begin
          if (resp_item.actual_data === ctx_item.enc_data &&
              resp_item.actual_status === ECC_OK) begin
            pass_count++;
            `uvm_info("SB_PASS",
              $sformatf("PASS (no error) | data=%h | dec_data=%h status=%s",
                ctx_item.enc_data, resp_item.actual_data,
                resp_item.actual_status.name()),
              UVM_MEDIUM)
          end else begin
            fail_count++;
            `uvm_error("SB_FAIL",
              $sformatf("FAIL (no error) | data=%h | dec_data=%h status=%s (expected ECC_OK, data match)",
                ctx_item.enc_data, resp_item.actual_data,
                resp_item.actual_status.name()))
          end
        end

        // -----------------------------------------------------------------
        // SEC: decoded data must match original, status must be ECC_SEC
        // -----------------------------------------------------------------
        1: begin
          if (resp_item.actual_data === ctx_item.enc_data &&
              resp_item.actual_status === ECC_SEC) begin
            pass_count++;
            `uvm_info("SB_PASS",
              $sformatf("PASS (SEC) | data=%h pos=%0d | dec_data=%h status=%s",
                ctx_item.enc_data, ctx_item.error_pos_0,
                resp_item.actual_data, resp_item.actual_status.name()),
              UVM_MEDIUM)
          end else begin
            fail_count++;
            `uvm_error("SB_FAIL",
              $sformatf("FAIL (SEC) | data=%h pos=%0d | dec_data=%h status=%s (expected ECC_SEC, data match)",
                ctx_item.enc_data, ctx_item.error_pos_0,
                resp_item.actual_data, resp_item.actual_status.name()))
          end
        end

        // -----------------------------------------------------------------
        // DED: status must be ECC_DED (data may be wrong)
        // -----------------------------------------------------------------
        2: begin
          if (resp_item.actual_status === ECC_DED) begin
            pass_count++;
            `uvm_info("SB_PASS",
              $sformatf("PASS (DED) | data=%h pos0=%0d pos1=%0d | status=%s",
                ctx_item.enc_data, ctx_item.error_pos_0, ctx_item.error_pos_1,
                resp_item.actual_status.name()),
              UVM_MEDIUM)
          end else begin
            fail_count++;
            `uvm_error("SB_FAIL",
              $sformatf("FAIL (DED) | data=%h pos0=%0d pos1=%0d | status=%s (expected ECC_DED)",
                ctx_item.enc_data, ctx_item.error_pos_0, ctx_item.error_pos_1,
                resp_item.actual_status.name()))
          end
        end

        default: begin
          `uvm_warning("SB_UNKNOWN",
            $sformatf("Unknown error_type=%0d -- skipping check", ctx_item.error_type))
        end
      endcase
    end
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // check_phase: summary report
  // ---------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    `uvm_info("SB_SUMMARY",
      $sformatf("Scoreboard results: PASS=%0d  FAIL=%0d",
        pass_count, fail_count),
      UVM_NONE)

    if (fail_count > 0)
      `uvm_error("SB_SUMMARY",
        $sformatf("%0d transaction(s) FAILED -- see above for details", fail_count))

    if (!fifo_in.is_empty())
      `uvm_warning("SB_LEFTOVERS",
        $sformatf("%0d input item(s) unmatched in fifo_in at end of test",
          fifo_in.used()))

    if (!fifo_out.is_empty())
      `uvm_warning("SB_LEFTOVERS",
        $sformatf("%0d output item(s) unmatched in fifo_out at end of test",
          fifo_out.used()))
  endfunction : check_phase

endclass : ecc_scoreboard

`endif // ECC_SCOREBOARD_SV
