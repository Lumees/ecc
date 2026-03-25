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
// ECC UVM Testbench -- Environment
// =============================================================================
// Top-level UVM environment containing:
//   - ecc_agent       (active)
//   - ecc_scoreboard
//   - ecc_coverage
//
// Analysis port connections:
//   agent.monitor.ap_in  -> scoreboard.ae_in
//   agent.monitor.ap_out -> scoreboard.ae_out
//   ap_context           -> scoreboard.ae_context
//   ap_context           -> coverage (via subscriber write())
// =============================================================================

`ifndef ECC_ENV_SV
`define ECC_ENV_SV

`include "uvm_macros.svh"

class ecc_env extends uvm_env;

  import ecc_pkg::*;

  `uvm_component_utils(ecc_env)

  // Sub-components
  ecc_agent       agent;
  ecc_scoreboard  scoreboard;
  ecc_coverage    coverage;

  // Broadcast analysis port for full context items.
  // Sequences write to this port after each item is sent; the env fans it
  // out to the scoreboard context FIFO and coverage collector.
  uvm_analysis_port #(ecc_seq_item) ap_context;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    agent      = ecc_agent::type_id::create      ("agent",      this);
    scoreboard = ecc_scoreboard::type_id::create  ("scoreboard", this);
    coverage   = ecc_coverage::type_id::create    ("coverage",   this);

    ap_context = new("ap_context", this);
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // connect_phase: wire analysis ports
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // Monitor encode input captures -> scoreboard input FIFO
    agent.monitor.ap_in.connect(scoreboard.ae_in);

    // Monitor decode output captures -> scoreboard output FIFO
    agent.monitor.ap_out.connect(scoreboard.ae_out);

    // Full-context items (with all error injection info) -> scoreboard context FIFO
    ap_context.connect(scoreboard.ae_context);

    // Full-context items -> coverage collector
    ap_context.connect(coverage.analysis_export);
  endfunction : connect_phase

  // ---------------------------------------------------------------------------
  // start_of_simulation_phase
  // ---------------------------------------------------------------------------
  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info("ENV", "ECC UVM Environment topology:", UVM_MEDIUM)
    this.print();
  endfunction : start_of_simulation_phase

endclass : ecc_env

`endif // ECC_ENV_SV
