`timescale 1 ns / 100 ps

// Module: axi_lite_protocol_sva
// Description:
//Protocol assertions for the AXI4-Lite wrapper boundary.

module axi_lite_protocol_sva #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input logic                          clk,
    input logic                          rstn,

    input logic [ADDR_WIDTH-1:0]         S_AXI_AWADDR,
    input logic                          S_AXI_AWVALID,
    input logic                          S_AXI_AWREADY,
    input logic [DATA_WIDTH-1:0]         S_AXI_WDATA,
    input logic [(DATA_WIDTH/8)-1:0]     S_AXI_WSTRB,
    input logic                          S_AXI_WVALID,
    input logic                          S_AXI_WREADY,
    input logic [1:0]                    S_AXI_BRESP,
    input logic                          S_AXI_BVALID,
    input logic                          S_AXI_BREADY,
    input logic [ADDR_WIDTH-1:0]         S_AXI_ARADDR,
    input logic                          S_AXI_ARVALID,
    input logic                          S_AXI_ARREADY,
    input logic [DATA_WIDTH-1:0]         S_AXI_RDATA,
    input logic [1:0]                    S_AXI_RRESP,
    input logic                          S_AXI_RVALID,
    input logic                          S_AXI_RREADY
);

    default clocking cb @(posedge clk);
    endclocking

    ap_reset_clears_responses:
        assert property (!rstn |=> (!S_AXI_BVALID && !S_AXI_RVALID));

    ap_bvalid_holds_until_ready:
        assert property (disable iff (!rstn)
            (S_AXI_BVALID && !S_AXI_BREADY) |=> S_AXI_BVALID
        );

    ap_rvalid_holds_until_ready:
        assert property (disable iff (!rstn)
            (S_AXI_RVALID && !S_AXI_RREADY) |=>
                (S_AXI_RVALID && $stable(S_AXI_RDATA) && $stable(S_AXI_RRESP))
        );

    ap_write_response_okay:
        assert property (disable iff (!rstn)
            S_AXI_BVALID |-> (S_AXI_BRESP == 2'b00)
        );

    ap_read_response_okay:
        assert property (disable iff (!rstn)
            S_AXI_RVALID |-> (S_AXI_RRESP == 2'b00)
        );

    ap_write_address_stable_until_accept:
        assert property (disable iff (!rstn)
            (S_AXI_AWVALID && !S_AXI_AWREADY) |=> $stable(S_AXI_AWADDR)
        );

    ap_write_data_stable_until_accept:
        assert property (disable iff (!rstn)
            (S_AXI_WVALID && !S_AXI_WREADY) |=> ($stable(S_AXI_WDATA) && $stable(S_AXI_WSTRB))
        );

    ap_read_address_stable_until_accept:
        assert property (disable iff (!rstn)
            (S_AXI_ARVALID && !S_AXI_ARREADY) |=> $stable(S_AXI_ARADDR)
        );

endmodule

// Module: preprocess_reg_block_sva
// Description:
//Assertions bound into the software-visible preprocessing register block.

module preprocess_reg_block_sva #(
    parameter int DATA_WIDTH = 8,
    parameter int REG_ADDR_WIDTH = 8,
    parameter int REG_DATA_WIDTH = 32,
    parameter int CYCLE_COUNT_WIDTH = 32
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
    input logic [CYCLE_COUNT_WIDTH-1:0]      processing_cycles,
    input logic [DATA_WIDTH-1:0]             threshold_r,
    input logic [1:0]                        mode_r,
    input logic                              done_latched_r,
    input logic [CYCLE_COUNT_WIDTH-1:0]      processing_cycles_latched_r,
    input logic                              input_data_write
);

    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_THRESHOLD = 8'h08;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_MODE = 8'h2c;
    localparam logic [1:0] MODE_THRESHOLD = 2'd0;
    localparam logic [1:0] MODE_SOBEL = 2'd1;

    default clocking cb @(posedge clk);
    endclocking

    ap_reset_defaults:
        assert property (rst |=> (
            !done_latched_r &&
            (threshold_r == DATA_WIDTH'(128)) &&
            (mode_r == MODE_THRESHOLD)
        ));

    ap_no_input_buffer_write_while_busy:
        assert property (disable iff (rst)
            busy |-> !input_data_write
        );

    ap_done_has_nonzero_cycle_count:
        assert property (disable iff (rst)
            done_pulse |-> (processing_cycles != '0)
        );

    ap_done_latches_status:
        assert property (disable iff (rst)
            done_pulse |=> done_latched_r
        );

    ap_latched_cycles_match_done_cycles:
        assert property (disable iff (rst)
            done_pulse |=> (processing_cycles_latched_r == $past(processing_cycles))
        );

    ap_done_stays_latched_until_clear_or_restart:
        assert property (disable iff (rst)
            (done_latched_r && !clear_done_pulse && !start_pulse) |=> done_latched_r
        );

    ap_clear_done_clears_latched_done:
        assert property (disable iff (rst)
            clear_done_pulse |=> !done_latched_r
        );

    ap_invalid_mode_defaults_to_threshold:
        assert property (disable iff (rst)
            (reg_write_en && (reg_write_addr == ADDR_MODE) && !busy &&
             !((reg_write_data[1:0] == MODE_THRESHOLD) || (reg_write_data[1:0] == MODE_SOBEL)))
            |=> (mode_r == MODE_THRESHOLD)
        );

    ap_mode_write_ignored_while_busy:
        assert property (disable iff (rst)
            (reg_write_en && (reg_write_addr == ADDR_MODE) && busy) |=> $stable(mode_r)
        );

    ap_threshold_write_ignored_while_busy:
        assert property (disable iff (rst)
            (reg_write_en && (reg_write_addr == ADDR_THRESHOLD) && busy) |=> $stable(threshold_r)
        );

endmodule

bind image_preprocess_reg_block preprocess_reg_block_sva #(
    .DATA_WIDTH(DATA_WIDTH),
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
    .REG_DATA_WIDTH(REG_DATA_WIDTH),
    .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
) reg_block_sva_i (
    .clk(clk),
    .rst(rst),
    .reg_write_en(reg_write_en),
    .reg_write_addr(reg_write_addr),
    .reg_write_data(reg_write_data),
    .start_pulse(start_pulse),
    .clear_done_pulse(clear_done_pulse),
    .busy(busy),
    .done_pulse(done_pulse),
    .processing_cycles(processing_cycles),
    .threshold_r(threshold_r),
    .mode_r(mode_r),
    .done_latched_r(done_latched_r),
    .processing_cycles_latched_r(processing_cycles_latched_r),
    .input_data_write(input_data_write)
);
