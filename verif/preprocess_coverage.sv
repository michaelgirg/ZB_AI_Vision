`timescale 1 ns / 100 ps

// Module: axi_lite_protocol_coverage
// Description:
//Functional coverage for AXI4-Lite handshakes and backpressure.

module axi_lite_protocol_coverage #(
    parameter int ADDR_WIDTH = 8
) (
    input logic                          clk,
    input logic                          rstn,
    input logic [ADDR_WIDTH-1:0]         S_AXI_AWADDR,
    input logic                          S_AXI_AWVALID,
    input logic                          S_AXI_AWREADY,
    input logic                          S_AXI_WVALID,
    input logic                          S_AXI_WREADY,
    input logic                          S_AXI_BVALID,
    input logic                          S_AXI_BREADY,
    input logic [ADDR_WIDTH-1:0]         S_AXI_ARADDR,
    input logic                          S_AXI_ARVALID,
    input logic                          S_AXI_ARREADY,
    input logic                          S_AXI_RVALID,
    input logic                          S_AXI_RREADY
);

    covergroup axi_cg @(posedge clk);
        option.per_instance = 1;

        cp_aw_handshake: coverpoint (S_AXI_AWVALID && S_AXI_AWREADY) iff (rstn) {
            bins hit = {1'b1};
        }

        cp_w_handshake: coverpoint (S_AXI_WVALID && S_AXI_WREADY) iff (rstn) {
            bins hit = {1'b1};
        }

        cp_b_handshake: coverpoint (S_AXI_BVALID && S_AXI_BREADY) iff (rstn) {
            bins hit = {1'b1};
        }

        cp_ar_handshake: coverpoint (S_AXI_ARVALID && S_AXI_ARREADY) iff (rstn) {
            bins hit = {1'b1};
        }

        cp_r_handshake: coverpoint (S_AXI_RVALID && S_AXI_RREADY) iff (rstn) {
            bins hit = {1'b1};
        }

        cp_write_response_stall: coverpoint (S_AXI_BVALID && !S_AXI_BREADY) iff (rstn) {
            bins stalled = {1'b1};
        }

        cp_read_response_stall: coverpoint (S_AXI_RVALID && !S_AXI_RREADY) iff (rstn) {
            bins stalled = {1'b1};
        }

        cp_write_addr: coverpoint S_AXI_AWADDR iff (rstn && S_AXI_AWVALID && S_AXI_AWREADY) {
            bins ctrl = {8'h00};
            bins threshold = {8'h08};
            bins input_addr = {8'h18};
            bins input_wdata = {8'h1c};
            bins input_wmask = {8'h20};
            bins output_addr = {8'h24};
            bins mode = {8'h2c};
        }

        cp_read_addr: coverpoint S_AXI_ARADDR iff (rstn && S_AXI_ARVALID && S_AXI_ARREADY) {
            bins status = {8'h04};
            bins image_pixels = {8'h0c};
            bins pixels_per_cycle = {8'h10};
            bins processing_cycles = {8'h14};
            bins output_rdata = {8'h28};
            bins mode = {8'h2c};
        }
    endgroup

    axi_cg axi_cg_i = new();

endmodule

// Module: preprocess_reg_block_coverage
// Description:
//Functional coverage bound into the preprocessing register block.

module preprocess_reg_block_coverage #(
    parameter int DATA_WIDTH = 8,
    parameter int REG_ADDR_WIDTH = 8,
    parameter int REG_DATA_WIDTH = 32
) (
    input logic                              clk,
    input logic                              rst,
    input logic                              reg_write_en,
    input logic [REG_ADDR_WIDTH-1:0]         reg_write_addr,
    input logic [REG_DATA_WIDTH-1:0]         reg_write_data,
    input logic                              start_pulse,
    input logic                              clear_done_pulse,
    input logic                              busy,
    input logic                              done_pulse,
    input logic [DATA_WIDTH-1:0]             threshold_r,
    input logic [1:0]                        mode_r
);

    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CTRL = 8'h00;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_THRESHOLD = 8'h08;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_INPUT_WDATA = 8'h1c;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_MODE = 8'h2c;

    covergroup reg_cg @(posedge clk);
        option.per_instance = 1;

        cp_mode: coverpoint mode_r iff (!rst) {
            bins threshold = {2'd0};
            bins sobel = {2'd1};
        }

        cp_mode_write: coverpoint reg_write_data[1:0]
            iff (!rst && reg_write_en && (reg_write_addr == ADDR_MODE)) {
            bins threshold = {2'd0};
            bins sobel = {2'd1};
            bins invalid[] = {[2:3]};
        }

        cp_threshold_write: coverpoint reg_write_data[7:0]
            iff (!rst && reg_write_en && (reg_write_addr == ADDR_THRESHOLD)) {
            bins zero = {8'd0};
            bins one = {8'd1};
            bins mid_low = {8'd127};
            bins mid = {8'd128};
            bins high = {8'd254};
            bins max = {8'd255};
        }

        cp_threshold_active: coverpoint threshold_r iff (!rst) {
            bins default_128 = {8'd128};
            bins other = default;
        }

        cp_start: coverpoint start_pulse iff (!rst) {
            bins start = {1'b1};
        }

        cp_clear_done: coverpoint clear_done_pulse iff (!rst) {
            bins clear = {1'b1};
        }

        cp_done: coverpoint done_pulse iff (!rst) {
            bins done = {1'b1};
        }

        cp_busy_input_write_attempt: coverpoint (reg_write_en && (reg_write_addr == ADDR_INPUT_WDATA) && busy)
            iff (!rst) {
            bins attempted = {1'b1};
        }

        cp_busy_mode_write_attempt: coverpoint (reg_write_en && (reg_write_addr == ADDR_MODE) && busy)
            iff (!rst) {
            bins attempted = {1'b1};
        }

        cp_busy_threshold_write_attempt: coverpoint (reg_write_en && (reg_write_addr == ADDR_THRESHOLD) && busy)
            iff (!rst) {
            bins attempted = {1'b1};
        }

        cp_ctrl_write: coverpoint reg_write_data[1:0]
            iff (!rst && reg_write_en && (reg_write_addr == ADDR_CTRL)) {
            bins start_only = {2'b01};
            bins clear_only = {2'b10};
            bins start_and_clear = {2'b11};
        }
    endgroup

    reg_cg reg_cg_i = new();

endmodule

bind image_preprocess_reg_block preprocess_reg_block_coverage #(
    .DATA_WIDTH(DATA_WIDTH),
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
    .REG_DATA_WIDTH(REG_DATA_WIDTH)
) reg_block_coverage_i (
    .clk(clk),
    .rst(rst),
    .reg_write_en(reg_write_en),
    .reg_write_addr(reg_write_addr),
    .reg_write_data(reg_write_data),
    .start_pulse(start_pulse),
    .clear_done_pulse(clear_done_pulse),
    .busy(busy),
    .done_pulse(done_pulse),
    .threshold_r(threshold_r),
    .mode_r(mode_r)
);
