`timescale 1 ns / 100 ps

// Package: preprocess_uvm_pkg
// Description:
//Mini UVM environment for the AXI-Lite preprocessing accelerator.

package preprocess_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import preprocess_verif_pkg::*;

    `include "verif/uvm/axi_lite_item.sv"
    `include "verif/uvm/axi_lite_sequencer.sv"
    `include "verif/uvm/axi_lite_driver.sv"
    `include "verif/uvm/axi_lite_monitor.sv"
    `include "verif/uvm/axi_lite_agent.sv"
    `include "verif/uvm/preprocess_scoreboard_uvm.sv"
    `include "verif/uvm/preprocess_coverage_uvm.sv"
    `include "verif/uvm/preprocess_env.sv"
    `include "verif/uvm/sequences/preprocess_image_sequence.sv"
    `include "verif/uvm/sequences/threshold_sequence.sv"
    `include "verif/uvm/sequences/sobel_sequence.sv"
    `include "verif/uvm/sequences/control_sequence.sv"
    `include "verif/uvm/sequences/random_control_sequence.sv"
    `include "verif/uvm/sequences/busy_write_sequence.sv"
    `include "verif/uvm/sequences/reset_sequence.sv"
    `include "verif/uvm/tests/preprocess_base_test.sv"
    `include "verif/uvm/tests/preprocess_threshold_test.sv"
    `include "verif/uvm/tests/preprocess_sobel_test.sv"
    `include "verif/uvm/tests/preprocess_control_test.sv"
    `include "verif/uvm/tests/preprocess_random_test.sv"
    `include "verif/uvm/tests/preprocess_busy_write_test.sv"
    `include "verif/uvm/tests/preprocess_reset_test.sv"

endpackage
