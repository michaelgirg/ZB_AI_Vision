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
    localparam bit [7:0] ADDR_THRESHOLD = 8'h08;
    localparam bit [7:0] ADDR_IMAGE_PIXELS = 8'h0c;
    localparam bit [7:0] ADDR_PIXELS_PER_CYCLE = 8'h10;
    localparam bit [7:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam bit [7:0] ADDR_MODE = 8'h2c;
    localparam bit [7:0] ADDR_CONV_BIAS = 8'h54;
    localparam bit [7:0] ADDR_VECTOR_CFG_INDEX = 8'h60;
    localparam bit [7:0] ADDR_VECTOR_CFG_DATA = 8'h64;
    localparam bit [7:0] ADDR_VECTOR_CFG_COMMIT = 8'h68;
    localparam bit [7:0] ADDR_VECTOR_CFG_VERSION = 8'h6c;
    localparam bit [7:0] ADDR_IP_ID = 8'h70;
    localparam bit [7:0] ADDR_IP_VERSION = 8'h74;
    localparam bit [7:0] ADDR_CAPABILITIES = 8'h78;
    localparam bit [7:0] ADDR_FRAME_COUNT = 8'h7c;
    localparam bit [7:0] ADDR_ERROR_COUNT = 8'h80;
    localparam bit [7:0] ADDR_INPUT_STALL_CYCLES = 8'h84;
    localparam bit [7:0] ADDR_OUTPUT_STALL_CYCLES = 8'h88;
    localparam bit [7:0] ADDR_ERROR_STATUS = 8'h8c;
    localparam bit [7:0] ADDR_INT_STATUS = 8'h90;
    localparam bit [7:0] ADDR_INT_ENABLE = 8'h94;
    localparam bit [7:0] ADDR_PERF_CONTROL = 8'h98;
    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_VECTOR4 = 3;

    `include "verif/uvm/axi_lite_item.sv"
    `include "verif/uvm/axi_lite_sequencer.sv"
    `include "verif/uvm/axi_lite_driver.sv"
    `include "verif/uvm/axi_lite_monitor.sv"
    `include "verif/uvm/axi_lite_agent.sv"
    `include "verif/uvm_axis/reg_model/preprocess_reg_model.sv"
    `include "verif/uvm_axis/reg_model/preprocess_reg_adapter.sv"
    `include "verif/uvm_axis/axis_stream_item.sv"
    `include "verif/uvm_axis/axis_stream_sequencer.sv"
    `include "verif/uvm_axis/axis_stream_source_driver.sv"
    `include "verif/uvm_axis/axis_stream_source_agent.sv"
    `include "verif/uvm_axis/axis_stream_sink_driver.sv"
    `include "verif/uvm_axis/axis_stream_monitors.sv"
    `include "verif/uvm_axis/vector_dynamic_predictor.sv"
    `include "verif/uvm_axis/vector_stream_scoreboard.sv"
    `include "verif/uvm_axis/vector_stream_coverage.sv"
    `include "verif/uvm_axis/vector_stream_sequences.sv"
    `include "verif/uvm_axis/vector_stream_env.sv"
    `include "verif/uvm_axis/vector_stream_tests.sv"
endpackage
