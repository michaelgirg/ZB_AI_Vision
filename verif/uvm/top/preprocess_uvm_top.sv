`timescale 1 ns / 100 ps

// Module: preprocess_uvm_top
// Description:
//Top-level UVM testbench for the AXI-Lite preprocessing accelerator.

module preprocess_uvm_top;

    import uvm_pkg::*;
    import preprocess_verif_pkg::*;
    import preprocess_uvm_pkg::*;

    preprocess_if #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) pif();

    image_preprocess_axi_lite #(
        .C_S_AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(1)
    ) DUT (
        .S_AXI_ACLK(pif.clk),
        .S_AXI_ARESETN(pif.rstn),
        .S_AXI_AWADDR(pif.s_axi_awaddr),
        .S_AXI_AWPROT(pif.s_axi_awprot),
        .S_AXI_AWVALID(pif.s_axi_awvalid),
        .S_AXI_AWREADY(pif.s_axi_awready),
        .S_AXI_WDATA(pif.s_axi_wdata),
        .S_AXI_WSTRB(pif.s_axi_wstrb),
        .S_AXI_WVALID(pif.s_axi_wvalid),
        .S_AXI_WREADY(pif.s_axi_wready),
        .S_AXI_BRESP(pif.s_axi_bresp),
        .S_AXI_BVALID(pif.s_axi_bvalid),
        .S_AXI_BREADY(pif.s_axi_bready),
        .S_AXI_ARADDR(pif.s_axi_araddr),
        .S_AXI_ARPROT(pif.s_axi_arprot),
        .S_AXI_ARVALID(pif.s_axi_arvalid),
        .S_AXI_ARREADY(pif.s_axi_arready),
        .S_AXI_RDATA(pif.s_axi_rdata),
        .S_AXI_RRESP(pif.s_axi_rresp),
        .S_AXI_RVALID(pif.s_axi_rvalid),
        .S_AXI_RREADY(pif.s_axi_rready)
    );

    initial begin : generate_clock
        pif.clk = 1'b0;
        forever #5 pif.clk = ~pif.clk;
    end

    initial begin : generate_reset
        pif.rstn = 1'b0;
        repeat (5) @(posedge pif.clk);
        @(negedge pif.clk);
        pif.rstn = 1'b1;
    end

    initial begin : run_uvm
        uvm_config_db#(virtual preprocess_if)::set(null, "*", "vif", pif);
        run_test();
    end

endmodule
