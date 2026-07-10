`timescale 1 ns / 100 ps

// Package: vector_stream_uvm_pkg
// Description:
//UVM environment for AXI-Lite configured four-filter AXI4-Stream preprocessing.

package vector_stream_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int AXI_ADDR_WIDTH = 8;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int AXIS_DATA_WIDTH = 32;
    localparam int AXIS_KEEP_WIDTH = 4;
    localparam int IMAGE_WIDTH = 28;
    localparam int IMAGE_HEIGHT = 28;
    localparam int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int UVM_TIMEOUT_CYCLES = 50000;

    localparam bit [7:0] ADDR_CTRL = 8'h00;
    localparam bit [7:0] ADDR_STATUS = 8'h04;
    localparam bit [7:0] ADDR_MODE = 8'h2c;
    localparam bit [7:0] ADDR_VECTOR_CFG_INDEX = 8'h60;
    localparam bit [7:0] ADDR_VECTOR_CFG_DATA = 8'h64;
    localparam bit [7:0] ADDR_VECTOR_CFG_COMMIT = 8'h68;
    localparam bit [7:0] ADDR_VECTOR_CFG_VERSION = 8'h6c;
    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_VECTOR4 = 3;

    `include "verif/uvm/axi_lite_item.sv"
    `include "verif/uvm/axi_lite_sequencer.sv"
    `include "verif/uvm/axi_lite_driver.sv"
    `include "verif/uvm/axi_lite_monitor.sv"
    `include "verif/uvm/axi_lite_agent.sv"
    `include "verif/uvm_axis/axis_stream_item.sv"
    `include "verif/uvm_axis/axis_stream_sequencer.sv"
    `include "verif/uvm_axis/axis_stream_source_driver.sv"
    `include "verif/uvm_axis/axis_stream_source_agent.sv"
    `include "verif/uvm_axis/axis_stream_sink_driver.sv"
    `include "verif/uvm_axis/axis_stream_monitors.sv"
    `include "verif/uvm_axis/vector_stream_scoreboard.sv"
    `include "verif/uvm_axis/vector_stream_coverage.sv"
    `include "verif/uvm_axis/vector_stream_sequences.sv"
    `include "verif/uvm_axis/vector_stream_env.sv"
    `include "verif/uvm_axis/vector_stream_tests.sv"
endpackage
