`timescale 1 ns / 100 ps

// Module: vector_stream_uvm_top

module vector_stream_uvm_top;
    import uvm_pkg::*;
    import vector_stream_uvm_pkg::*;

    preprocess_if #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) ctrl_if();

    axis_stream_if #(
        .DATA_WIDTH(AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH)
    ) axis_if();

    assign axis_if.clk = ctrl_if.clk;
    assign axis_if.rstn = ctrl_if.rstn;

    axis_preprocess_vector_axi_lite DUT (
        .S_AXI_ACLK(ctrl_if.clk),
        .S_AXI_ARESETN(ctrl_if.rstn),
        .S_AXI_AWADDR(ctrl_if.s_axi_awaddr),
        .S_AXI_AWPROT(ctrl_if.s_axi_awprot),
        .S_AXI_AWVALID(ctrl_if.s_axi_awvalid),
        .S_AXI_AWREADY(ctrl_if.s_axi_awready),
        .S_AXI_WDATA(ctrl_if.s_axi_wdata),
        .S_AXI_WSTRB(ctrl_if.s_axi_wstrb),
        .S_AXI_WVALID(ctrl_if.s_axi_wvalid),
        .S_AXI_WREADY(ctrl_if.s_axi_wready),
        .S_AXI_BRESP(ctrl_if.s_axi_bresp),
        .S_AXI_BVALID(ctrl_if.s_axi_bvalid),
        .S_AXI_BREADY(ctrl_if.s_axi_bready),
        .S_AXI_ARADDR(ctrl_if.s_axi_araddr),
        .S_AXI_ARPROT(ctrl_if.s_axi_arprot),
        .S_AXI_ARVALID(ctrl_if.s_axi_arvalid),
        .S_AXI_ARREADY(ctrl_if.s_axi_arready),
        .S_AXI_RDATA(ctrl_if.s_axi_rdata),
        .S_AXI_RRESP(ctrl_if.s_axi_rresp),
        .S_AXI_RVALID(ctrl_if.s_axi_rvalid),
        .S_AXI_RREADY(ctrl_if.s_axi_rready),
        .S_AXIS_TDATA(axis_if.s_tdata),
        .S_AXIS_TKEEP(axis_if.s_tkeep),
        .S_AXIS_TVALID(axis_if.s_tvalid),
        .S_AXIS_TREADY(axis_if.s_tready),
        .S_AXIS_TLAST(axis_if.s_tlast),
        .M_AXIS_TDATA(axis_if.m_tdata),
        .M_AXIS_TKEEP(axis_if.m_tkeep),
        .M_AXIS_TVALID(axis_if.m_tvalid),
        .M_AXIS_TREADY(axis_if.m_tready),
        .M_AXIS_TLAST(axis_if.m_tlast)
    );

    axis_vector_sva stream_sva (
        .clk(ctrl_if.clk),
        .rstn(ctrl_if.rstn),
        .s_tdata(axis_if.s_tdata),
        .s_tkeep(axis_if.s_tkeep),
        .s_tvalid(axis_if.s_tvalid),
        .s_tready(axis_if.s_tready),
        .s_tlast(axis_if.s_tlast),
        .m_tdata(axis_if.m_tdata),
        .m_tkeep(axis_if.m_tkeep),
        .m_tvalid(axis_if.m_tvalid),
        .m_tready(axis_if.m_tready),
        .m_tlast(axis_if.m_tlast)
    );

    initial begin : generate_clock
        ctrl_if.clk = 1'b0;
        forever #5 ctrl_if.clk = ~ctrl_if.clk;
    end

    initial begin : generate_reset
        ctrl_if.rstn = 1'b0;
        repeat (5) @(posedge ctrl_if.clk);
        @(negedge ctrl_if.clk);
        ctrl_if.rstn = 1'b1;
    end

    initial begin : run_uvm
        uvm_config_db#(virtual preprocess_if)::set(null, "*", "vif", ctrl_if);
        uvm_config_db#(virtual preprocess_if)::set(null, "*", "ctrl_vif", ctrl_if);
        uvm_config_db#(virtual axis_stream_if)::set(null, "*", "axis_vif", axis_if);
        run_test();
    end
endmodule
