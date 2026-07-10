`timescale 1 ns / 100 ps

// Module: test_axi_lite_control_coverage
// Description:
//Focused register/coverage test for threshold boundary values and control modes.

module test_axi_lite_control_coverage;

    import preprocess_verif_pkg::*;

    logic                                  clk = 1'b0;
    logic                                  rstn;
    logic [AXI_ADDR_WIDTH-1:0]             s_axi_awaddr;
    logic [2:0]                            s_axi_awprot;
    logic                                  s_axi_awvalid;
    logic                                  s_axi_awready;
    logic [AXI_DATA_WIDTH-1:0]             s_axi_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0]         s_axi_wstrb;
    logic                                  s_axi_wvalid;
    logic                                  s_axi_wready;
    logic [1:0]                            s_axi_bresp;
    logic                                  s_axi_bvalid;
    logic                                  s_axi_bready;
    logic [AXI_ADDR_WIDTH-1:0]             s_axi_araddr;
    logic [2:0]                            s_axi_arprot;
    logic                                  s_axi_arvalid;
    logic                                  s_axi_arready;
    logic [AXI_DATA_WIDTH-1:0]             s_axi_rdata;
    logic [1:0]                            s_axi_rresp;
    logic                                  s_axi_rvalid;
    logic                                  s_axi_rready;

    int mismatch_count = 0;
    int threshold_values [6] = '{0, 1, 127, 128, 254, 255};
    int mode_values [4] = '{0, 1, 2, 3};

    image_preprocess_axi_lite #(
        .C_S_AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(1)
    ) DUT (
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rstn),
        .S_AXI_AWADDR(s_axi_awaddr),
        .S_AXI_AWPROT(s_axi_awprot),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),
        .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WVALID(s_axi_wvalid),
        .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BRESP(s_axi_bresp),
        .S_AXI_BVALID(s_axi_bvalid),
        .S_AXI_BREADY(s_axi_bready),
        .S_AXI_ARADDR(s_axi_araddr),
        .S_AXI_ARPROT(s_axi_arprot),
        .S_AXI_ARVALID(s_axi_arvalid),
        .S_AXI_ARREADY(s_axi_arready),
        .S_AXI_RDATA(s_axi_rdata),
        .S_AXI_RRESP(s_axi_rresp),
        .S_AXI_RVALID(s_axi_rvalid),
        .S_AXI_RREADY(s_axi_rready)
    );

    axi_lite_master_bfm #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) master (
        .clk(clk),
        .rstn(rstn),
        .m_axi_awaddr(s_axi_awaddr),
        .m_axi_awprot(s_axi_awprot),
        .m_axi_awvalid(s_axi_awvalid),
        .m_axi_awready(s_axi_awready),
        .m_axi_wdata(s_axi_wdata),
        .m_axi_wstrb(s_axi_wstrb),
        .m_axi_wvalid(s_axi_wvalid),
        .m_axi_wready(s_axi_wready),
        .m_axi_bresp(s_axi_bresp),
        .m_axi_bvalid(s_axi_bvalid),
        .m_axi_bready(s_axi_bready),
        .m_axi_araddr(s_axi_araddr),
        .m_axi_arprot(s_axi_arprot),
        .m_axi_arvalid(s_axi_arvalid),
        .m_axi_arready(s_axi_arready),
        .m_axi_rdata(s_axi_rdata),
        .m_axi_rresp(s_axi_rresp),
        .m_axi_rvalid(s_axi_rvalid),
        .m_axi_rready(s_axi_rready)
    );

    axi_lite_protocol_sva #(
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH)
    ) axi_sva (
        .clk(clk),
        .rstn(rstn),
        .S_AXI_AWADDR(s_axi_awaddr),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),
        .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WVALID(s_axi_wvalid),
        .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BRESP(s_axi_bresp),
        .S_AXI_BVALID(s_axi_bvalid),
        .S_AXI_BREADY(s_axi_bready),
        .S_AXI_ARADDR(s_axi_araddr),
        .S_AXI_ARVALID(s_axi_arvalid),
        .S_AXI_ARREADY(s_axi_arready),
        .S_AXI_RDATA(s_axi_rdata),
        .S_AXI_RRESP(s_axi_rresp),
        .S_AXI_RVALID(s_axi_rvalid),
        .S_AXI_RREADY(s_axi_rready)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    task automatic checked_write(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data
    );
        bit ok;

        master.write(addr, data, ok);
        if (!ok) begin
            mismatch_count++;
        end
    endtask

    task automatic checked_read(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        output logic [AXI_DATA_WIDTH-1:0] data
    );
        bit ok;

        master.read(addr, data, ok);
        if (!ok) begin
            mismatch_count++;
        end
    endtask

    task automatic check_threshold_sweep();
        logic [AXI_DATA_WIDTH-1:0] read_value;

        foreach (threshold_values[index]) begin
            checked_write(ADDR_THRESHOLD, AXI_DATA_WIDTH'(threshold_values[index]));
            checked_read(ADDR_THRESHOLD, read_value);
            if (read_value[7:0] !== threshold_values[index][7:0]) begin
                mismatch_count++;
                $error(
                    "Threshold mismatch: actual=%0d expected=%0d",
                    read_value[7:0],
                    threshold_values[index]
                );
            end
        end
    endtask

    task automatic check_mode_sweep();
        logic [AXI_DATA_WIDTH-1:0] read_value;
        logic [1:0] expected_mode;

        foreach (mode_values[index]) begin
            expected_mode = (mode_values[index] <= MODE_SOBEL) ? mode_values[index][1:0] : 2'd0;
            checked_write(ADDR_MODE, AXI_DATA_WIDTH'(mode_values[index]));
            checked_read(ADDR_MODE, read_value);
            if (read_value[1:0] !== expected_mode) begin
                mismatch_count++;
                $error(
                    "Mode mismatch after writing %0d: actual=%0d expected=%0d",
                    mode_values[index],
                    read_value[1:0],
                    expected_mode
                );
            end
        end
    endtask

    task automatic load_zero_image();
        checked_write(ADDR_INPUT_WMASK, AXI_DATA_WIDTH'(1));
        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            checked_write(ADDR_INPUT_ADDR, AXI_DATA_WIDTH'(pixel));
            checked_write(ADDR_INPUT_WDATA, AXI_DATA_WIDTH'(0));
        end
    endtask

    task automatic poll_done();
        logic [AXI_DATA_WIDTH-1:0] status_value;

        status_value = '0;
        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            checked_read(ADDR_STATUS, status_value);
            if (status_value[1] === 1'b1) begin
                return;
            end
        end

        $fatal(1, "FAIL: control coverage test did not observe done.");
    endtask

    task automatic attempt_busy_writes();
        logic [AXI_DATA_WIDTH-1:0] status_value;

        checked_read(ADDR_STATUS, status_value);
        if (status_value[0] !== 1'b1) begin
            repeat (4) begin
                checked_read(ADDR_STATUS, status_value);
                if (status_value[0] === 1'b1) begin
                    break;
                end
            end
        end

        if (status_value[0] !== 1'b1) begin
            mismatch_count++;
            $error("Busy was not observed for busy-write coverage.");
            return;
        end

        checked_write(ADDR_THRESHOLD, AXI_DATA_WIDTH'(255));
        checked_write(ADDR_MODE, AXI_DATA_WIDTH'(3));
        checked_write(ADDR_INPUT_WDATA, AXI_DATA_WIDTH'(8'haa));
    endtask

    task automatic check_clear_done();
        logic [AXI_DATA_WIDTH-1:0] status_value;

        checked_write(ADDR_CTRL, AXI_DATA_WIDTH'(2));
        checked_read(ADDR_STATUS, status_value);
        if (status_value[1] !== 1'b0) begin
            mismatch_count++;
            $error("clear_done did not clear done status: status=0x%08h", status_value);
        end
    endtask

    initial begin : provide_stimulus
        master.init();
        rstn <= 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn <= 1'b1;

        check_threshold_sweep();
        check_mode_sweep();

        checked_write(ADDR_THRESHOLD, AXI_DATA_WIDTH'(128));
        checked_write(ADDR_MODE, AXI_DATA_WIDTH'(MODE_THRESHOLD));
        load_zero_image();

        checked_write(ADDR_CTRL, AXI_DATA_WIDTH'(1));
        attempt_busy_writes();
        poll_done();
        check_clear_done();

        checked_write(ADDR_CTRL, AXI_DATA_WIDTH'(3));
        poll_done();
        check_clear_done();

        if (mismatch_count == 0) begin
            $display("PASS: AXI-Lite control coverage test completed.");
            $finish;
        end

        $fatal(1, "FAIL: control coverage test found %0d issue(s).", mismatch_count);
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES * 12) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES * 12);
    end

endmodule
