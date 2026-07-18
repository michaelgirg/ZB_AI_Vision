`timescale 1 ns / 100 ps

// Module: vector_stream_uvm_top

module vector_stream_uvm_top;
    import uvm_pkg::*;
    import vector_stream_uvm_pkg::*;
    bit allow_malformed_input;
    logic irq;

    bind axis_conv3x3_vector4_preprocess vector_core_safety_sva #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .IMAGE_PIXELS(IMAGE_PIXELS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_PTR_WIDTH(FIFO_PTR_WIDTH),
        .FIFO_COUNT_WIDTH(FIFO_COUNT_WIDTH)
    ) vector_core_safety_sva_i (
        .aclk(aclk),
        .aresetn(aresetn),
        .clear_done(clear_done),
        .busy(busy),
        .done(done),
        .packet_error(packet_error),
        .input_fire(input_fire),
        .output_fire(output_fire),
        .fifo_rd_ptr(fifo_rd_ptr_r),
        .fifo_wr_ptr(fifo_wr_ptr_r),
        .fifo_count(fifo_count_r),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

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
    assign ctrl_if.irq = irq;

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
        .M_AXIS_TLAST(axis_if.m_tlast),
        .irq(irq)
    );

    production_diag_sva production_diag_sva_i (
        .clk(ctrl_if.clk),
        .rstn(ctrl_if.rstn),
        .irq(irq),
        .error_status(DUT.error_status_r),
        .int_status(DUT.int_status_r),
        .int_enable(DUT.int_enable_r),
        .frame_count(DUT.frame_count_r),
        .error_count(DUT.error_count_r),
        .input_stall_cycles(DUT.input_stall_cycles_r),
        .output_stall_cycles(DUT.output_stall_cycles_r),
        .perf_clear_pulse(DUT.perf_clear_pulse),
        .frame_done_event(DUT.frame_done_event),
        .packet_error_event(DUT.packet_error_event),
        .write_error_event(DUT.write_error_event),
        .read_error_event(DUT.read_error_event),
        .input_stall_event(DUT.stream_busy && axis_if.s_tvalid && !axis_if.s_tready),
        .output_stall_event(axis_if.m_tvalid && !axis_if.m_tready)
    );

    axis_vector_sva stream_sva (
        .clk(ctrl_if.clk),
        .rstn(ctrl_if.rstn),
        .allow_malformed_input(allow_malformed_input),
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

    axi_lite_vector_sva ctrl_sva (
        .clk(ctrl_if.clk),
        .rstn(ctrl_if.rstn),
        .awaddr(ctrl_if.s_axi_awaddr),
        .awvalid(ctrl_if.s_axi_awvalid),
        .awready(ctrl_if.s_axi_awready),
        .wdata(ctrl_if.s_axi_wdata),
        .wstrb(ctrl_if.s_axi_wstrb),
        .wvalid(ctrl_if.s_axi_wvalid),
        .wready(ctrl_if.s_axi_wready),
        .bresp(ctrl_if.s_axi_bresp),
        .bvalid(ctrl_if.s_axi_bvalid),
        .bready(ctrl_if.s_axi_bready),
        .araddr(ctrl_if.s_axi_araddr),
        .arvalid(ctrl_if.s_axi_arvalid),
        .arready(ctrl_if.s_axi_arready),
        .rdata(ctrl_if.s_axi_rdata),
        .rresp(ctrl_if.s_axi_rresp),
        .rvalid(ctrl_if.s_axi_rvalid),
        .rready(ctrl_if.s_axi_rready)
    );

    initial begin : generate_clock
        ctrl_if.clk = 1'b0;
        forever #5 ctrl_if.clk = ~ctrl_if.clk;
    end

    initial begin : generate_reset
        allow_malformed_input = $test$plusargs("ALLOW_MALFORMED_INPUT");
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
