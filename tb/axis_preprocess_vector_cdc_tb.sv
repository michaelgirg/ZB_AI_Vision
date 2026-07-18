`timescale 1 ns / 1 ps

module axis_preprocess_vector_cdc_tb #(
    parameter int S_AXI_HALF_PERIOD_PS = 5000,
    parameter int AXIS_HALF_PERIOD_PS = 3500
);
    localparam int IMAGE_PIXELS = 784;
    localparam logic [7:0] ADDR_CTRL = 8'h00;
    localparam logic [7:0] ADDR_STATUS = 8'h04;
    localparam logic [7:0] ADDR_THRESHOLD = 8'h08;
    localparam logic [7:0] ADDR_IMAGE_PIXELS = 8'h0c;
    localparam logic [7:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam logic [7:0] ADDR_MODE = 8'h2c;
    localparam logic [7:0] ADDR_IP_ID = 8'h70;
    localparam logic [7:0] ADDR_ERROR_COUNT = 8'h80;
    localparam logic [7:0] ADDR_ERROR_STATUS = 8'h8c;
    localparam logic [7:0] ADDR_INT_STATUS = 8'h90;
    localparam logic [7:0] ADDR_INT_ENABLE = 8'h94;
    localparam logic [7:0] ADDR_PERF_CONTROL = 8'h98;

    logic s_axi_aclk = 1'b0;
    logic axis_aclk = 1'b0;
    logic s_axi_aresetn;
    logic axis_aresetn;

    logic [7:0] s_axi_awaddr;
    logic [2:0] s_axi_awprot;
    logic s_axi_awvalid;
    logic s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0] s_axi_wstrb;
    logic s_axi_wvalid;
    logic s_axi_wready;
    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready;
    logic [7:0] s_axi_araddr;
    logic [2:0] s_axi_arprot;
    logic s_axi_arvalid;
    logic s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready;

    logic [31:0] s_axis_tdata;
    logic [3:0] s_axis_tkeep;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic s_axis_tlast;
    logic [31:0] m_axis_tdata;
    logic [3:0] m_axis_tkeep;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic m_axis_tlast;
    logic irq;

    logic [7:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [7:0] expected_pixels [0:IMAGE_PIXELS-1];
    int unsigned output_count;
    int unsigned mismatch_count;
    logic debug_request_toggle_q;
    logic debug_response_toggle_q;

    always #(S_AXI_HALF_PERIOD_PS * 1ps) s_axi_aclk = ~s_axi_aclk;
    always #(AXIS_HALF_PERIOD_PS * 1ps) axis_aclk = ~axis_aclk;

    axis_preprocess_vector_cdc DUT (
        .S_AXI_ACLK(s_axi_aclk),
        .S_AXI_ARESETN(s_axi_aresetn),
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
        .S_AXI_RREADY(s_axi_rready),
        .AXIS_ACLK(axis_aclk),
        .AXIS_ARESETN(axis_aresetn),
        .S_AXIS_TDATA(s_axis_tdata),
        .S_AXIS_TKEEP(s_axis_tkeep),
        .S_AXIS_TVALID(s_axis_tvalid),
        .S_AXIS_TREADY(s_axis_tready),
        .S_AXIS_TLAST(s_axis_tlast),
        .M_AXIS_TDATA(m_axis_tdata),
        .M_AXIS_TKEEP(m_axis_tkeep),
        .M_AXIS_TVALID(m_axis_tvalid),
        .M_AXIS_TREADY(m_axis_tready),
        .M_AXIS_TLAST(m_axis_tlast),
        .irq(irq)
    );

    cdc_bridge_sva cdc_bridge_sva_i (
        .s_axi_clk(s_axi_aclk),
        .s_axi_resetn(
            DUT.s_axi_resetn && DUT.axis_up_axi &&
            s_axi_aresetn && axis_aresetn
        ),
        .request_pending(DUT.request_pending_r),
        .request_toggle(DUT.request_toggle_r),
        .request_write(DUT.request_write_r),
        .request_addr(DUT.request_addr_r),
        .request_data(DUT.request_data_r),
        .request_strb(DUT.request_strb_r),
        .s_awready(s_axi_awready),
        .s_wready(s_axi_wready),
        .s_arready(s_axi_arready),
        .s_bvalid(s_axi_bvalid),
        .s_bready(s_axi_bready),
        .s_bresp(s_axi_bresp),
        .s_rvalid(s_axi_rvalid),
        .s_rready(s_axi_rready),
        .s_rdata(s_axi_rdata),
        .s_rresp(s_axi_rresp),
        .axis_clk(axis_aclk),
        .axis_resetn(DUT.bridge_axis_resetn),
        .bridge_state(DUT.bridge_state_r),
        .core_awvalid(DUT.core_awvalid),
        .core_awready(DUT.core_awready),
        .core_awaddr(DUT.core_awaddr),
        .core_wvalid(DUT.core_wvalid),
        .core_wready(DUT.core_wready),
        .core_wdata(DUT.core_wdata),
        .core_wstrb(DUT.core_wstrb),
        .core_arvalid(DUT.core_arvalid),
        .core_arready(DUT.core_arready),
        .core_araddr(DUT.core_araddr),
        .response_toggle(DUT.response_toggle_axis_r),
        .response_code(DUT.response_code_axis_r),
        .response_data(DUT.response_data_axis_r)
    );

    task automatic axi_write(
        input logic [7:0] addr,
        input logic [31:0] data,
        input int unsigned aw_delay,
        input int unsigned w_delay,
        input logic [1:0] expected_resp
    );
        @(negedge s_axi_aclk);
        s_axi_bready <= 1'b0;
        fork
            begin
                repeat (aw_delay) @(posedge s_axi_aclk);
                @(negedge s_axi_aclk);
                s_axi_awaddr <= addr;
                s_axi_awvalid <= 1'b1;
                do @(posedge s_axi_aclk); while (!(s_axi_awvalid && s_axi_awready));
                @(negedge s_axi_aclk);
                s_axi_awvalid <= 1'b0;
            end
            begin
                repeat (w_delay) @(posedge s_axi_aclk);
                @(negedge s_axi_aclk);
                s_axi_wdata <= data;
                s_axi_wstrb <= 4'hf;
                s_axi_wvalid <= 1'b1;
                do @(posedge s_axi_aclk); while (!(s_axi_wvalid && s_axi_wready));
                @(negedge s_axi_aclk);
                s_axi_wvalid <= 1'b0;
            end
        join
        @(negedge s_axi_aclk);
        s_axi_bready <= 1'b1;
        do @(posedge s_axi_aclk); while (!s_axi_bvalid);
        if (s_axi_bresp !== expected_resp) begin
            mismatch_count++;
            $error("CDC write addr=%02h response=%0b expected=%0b", addr, s_axi_bresp, expected_resp);
        end
        @(negedge s_axi_aclk);
        s_axi_bready <= 1'b0;
        s_axi_awaddr <= '0;
        s_axi_wdata <= '0;
        s_axi_wstrb <= '0;
    endtask

    task automatic axi_read(
        input logic [7:0] addr,
        output logic [31:0] data,
        input logic [1:0] expected_resp = 2'b00
    );
        @(negedge s_axi_aclk);
        s_axi_araddr <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready <= 1'b0;
        do @(posedge s_axi_aclk); while (!(s_axi_arvalid && s_axi_arready));
        @(negedge s_axi_aclk);
        s_axi_arvalid <= 1'b0;
        s_axi_rready <= 1'b1;
        do @(posedge s_axi_aclk); while (!s_axi_rvalid);
        data = s_axi_rdata;
        if (s_axi_rresp !== expected_resp) begin
            mismatch_count++;
            $error("CDC read addr=%02h response=%0b expected=%0b", addr, s_axi_rresp, expected_resp);
        end
        @(negedge s_axi_aclk);
        s_axi_rready <= 1'b0;
        s_axi_araddr <= '0;
    endtask

    task automatic send_pixel(input int unsigned index);
        @(negedge axis_aclk);
        s_axis_tdata <= input_pixels[index];
        s_axis_tkeep <= 4'hf;
        s_axis_tvalid <= 1'b1;
        s_axis_tlast <= (index == IMAGE_PIXELS - 1);
        do @(posedge axis_aclk); while (!(s_axis_tvalid && s_axis_tready));
        @(negedge axis_aclk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        s_axis_tdata <= '0;
    endtask

    task automatic stress_control_bridge(output int unsigned expected_errors);
        logic [31:0] lfsr;
        logic [31:0] value;
        logic [7:0] expected_threshold;

        lfsr = 32'h1ace_b00c;
        expected_errors = 0;
        for (int iteration = 0; iteration < 48; iteration++) begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            expected_threshold = lfsr[7:0];
            axi_write(
                ADDR_THRESHOLD,
                {24'd0, expected_threshold},
                iteration % 5,
                (iteration * 3) % 5,
                2'b00
            );
            axi_read(ADDR_THRESHOLD, value);
            if (value[7:0] != expected_threshold) begin
                mismatch_count++;
                $error(
                    "CDC stress threshold iteration=%0d actual=%02h expected=%02h",
                    iteration,
                    value[7:0],
                    expected_threshold
                );
            end

            if ((iteration % 8) == 0) begin
                axi_write(ADDR_IP_ID, lfsr, iteration % 3, (iteration + 1) % 3, 2'b10);
                expected_errors++;
            end
            if ((iteration % 11) == 0) begin
                axi_read(8'h9c, value, 2'b10);
                expected_errors++;
            end
            if ((iteration % 7) == 0) begin
                axi_write(ADDR_INT_ENABLE, iteration[2:0], 0, 0, 2'b00);
                axi_read(ADDR_INT_ENABLE, value);
                if (value[2:0] != iteration[2:0]) begin
                    mismatch_count++;
                    $error("CDC stress INT_ENABLE readback mismatch at iteration %0d", iteration);
                end
            end
        end
        $display(
            "PASS: CDC control bridge completed 48 skewed read/write iterations with %0d expected errors.",
            expected_errors
        );
    endtask

    task automatic check_reset_abort_recovery;
        logic [31:0] value;

        // AXIS reset must discard an address that was accepted before its
        // matching write data arrived.
        @(negedge s_axi_aclk);
        s_axi_awaddr <= ADDR_THRESHOLD;
        s_axi_awvalid <= 1'b1;
        do @(posedge s_axi_aclk); while (!(s_axi_awvalid && s_axi_awready));
        @(negedge s_axi_aclk);
        s_axi_awvalid <= 1'b0;
        s_axi_awaddr <= '0;
        axis_aresetn <= 1'b0;
        repeat (4) @(posedge s_axi_aclk);
        axis_aresetn <= 1'b1;
        repeat (8) @(posedge s_axi_aclk);
        if (s_axi_bvalid || s_axi_rvalid) begin
            mismatch_count++;
            $error("CDC AXIS reset replayed a response after partial AW abort");
        end
        axi_read(ADDR_THRESHOLD, value);
        if (value[7:0] != 8'd128) begin
            mismatch_count++;
            $error("CDC partial-AW reset recovery threshold=%0d", value[7:0]);
        end

        // AXI reset must similarly discard a data beat that has no address.
        @(negedge s_axi_aclk);
        s_axi_wdata <= 32'h0000_0042;
        s_axi_wstrb <= 4'hf;
        s_axi_wvalid <= 1'b1;
        do @(posedge s_axi_aclk); while (!(s_axi_wvalid && s_axi_wready));
        @(negedge s_axi_aclk);
        s_axi_wvalid <= 1'b0;
        s_axi_wdata <= '0;
        s_axi_wstrb <= '0;
        s_axi_aresetn <= 1'b0;
        repeat (4) @(posedge s_axi_aclk);
        s_axi_aresetn <= 1'b1;
        repeat (8) @(posedge s_axi_aclk);
        axi_write(ADDR_THRESHOLD, 32'h0000_005c, 0, 0, 2'b00);
        axi_read(ADDR_THRESHOLD, value);
        if (value[7:0] != 8'h5c) begin
            mismatch_count++;
            $error("CDC partial-W reset recovery threshold=%0d", value[7:0]);
        end

        // Hold a completed read response at the AXI boundary, reset the
        // opposite domain, and prove that no stale response is replayed.
        @(negedge s_axi_aclk);
        s_axi_araddr <= ADDR_THRESHOLD;
        s_axi_arvalid <= 1'b1;
        s_axi_rready <= 1'b0;
        do @(posedge s_axi_aclk); while (!(s_axi_arvalid && s_axi_arready));
        @(negedge s_axi_aclk);
        s_axi_arvalid <= 1'b0;
        s_axi_araddr <= '0;
        do @(posedge s_axi_aclk); while (!s_axi_rvalid);
        axis_aresetn <= 1'b0;
        repeat (4) @(posedge s_axi_aclk);
        axis_aresetn <= 1'b1;
        repeat (8) @(posedge s_axi_aclk);
        if (s_axi_rvalid || s_axi_bvalid) begin
            mismatch_count++;
            $error("CDC reset failed to flush a held read response");
        end
        axi_write(ADDR_THRESHOLD, 32'h0000_006d, 3, 0, 2'b00);
        axi_read(ADDR_THRESHOLD, value);
        if (value[7:0] != 8'h6d) begin
            mismatch_count++;
            $error("CDC held-response reset recovery threshold=%0d", value[7:0]);
        end

        $display("PASS: CDC reset-abort recovery discarded partial requests and a held response.");
    endtask

    always @(posedge axis_aclk) begin
        if (!axis_aresetn) begin
            output_count <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (output_count >= IMAGE_PIXELS) begin
                mismatch_count++;
                $error("CDC wrapper produced extra output %0d", output_count);
            end else begin
                if (m_axis_tdata[7:0] !== expected_pixels[output_count]) begin
                    mismatch_count++;
                    $error(
                        "CDC pixel %0d actual=%02h expected=%02h",
                        output_count,
                        m_axis_tdata[7:0],
                        expected_pixels[output_count]
                    );
                end
                if (m_axis_tdata[31:8] !== 0 || m_axis_tkeep !== 4'hf) begin
                    mismatch_count++;
                    $error("CDC scalar output payload invalid at %0d", output_count);
                end
                if (m_axis_tlast !== (output_count == IMAGE_PIXELS - 1)) begin
                    mismatch_count++;
                    $error("CDC TLAST mismatch at %0d", output_count);
                end
            end
            output_count <= output_count + 1;
        end
    end

    always @(posedge axis_aclk) begin
        if ($test$plusargs("DEBUG_CDC") && DUT.stream_domain_core.reg_write_en) begin
            $display(
                "CDC_DEBUG write addr=%02h data=%08h resp=%0b threshold=%02h time=%0t",
                DUT.stream_domain_core.reg_write_addr,
                DUT.stream_domain_core.reg_write_data,
                DUT.stream_domain_core.S_AXI_BRESP,
                DUT.stream_domain_core.threshold_r,
                $time
            );
        end
        if ($test$plusargs("DEBUG_CDC") && DUT.stream_domain_core.reg_read_en) begin
            $display(
                "CDC_DEBUG read addr=%02h data=%08h resp=%0b threshold=%02h time=%0t",
                DUT.stream_domain_core.reg_read_addr,
                DUT.stream_domain_core.read_register(DUT.stream_domain_core.reg_read_addr),
                DUT.stream_domain_core.S_AXI_RRESP,
                DUT.stream_domain_core.threshold_r,
                $time
            );
        end
        if ($test$plusargs("DEBUG_CDC") &&
            (DUT.response_toggle_axis_r != debug_response_toggle_q)) begin
            $display(
                "CDC_DEBUG axis response toggle=%0b code=%0b data=%08h time=%0t",
                DUT.response_toggle_axis_r,
                DUT.response_code_axis_r,
                DUT.response_data_axis_r,
                $time
            );
        end
        debug_response_toggle_q <= DUT.response_toggle_axis_r;
    end

    always @(posedge s_axi_aclk) begin
        if ($test$plusargs("DEBUG_CDC") &&
            (DUT.request_toggle_r != debug_request_toggle_q)) begin
            $display(
                "CDC_DEBUG axi request toggle=%0b write=%0b addr=%02h data=%08h time=%0t",
                DUT.request_toggle_r,
                DUT.request_write_r,
                DUT.request_addr_r,
                DUT.request_data_r,
                $time
            );
        end
        if ($test$plusargs("DEBUG_CDC") && DUT.request_pending_r &&
            DUT.response_valid_axi) begin
            $display(
                "CDC_DEBUG axi consumes response valid=%0b write=%0b code=%0b data=%08h time=%0t",
                DUT.response_valid_axi,
                DUT.pending_write_r,
                DUT.response_payload_axi[DUT.RESPONSE_WIDTH-1 -: 2],
                DUT.response_payload_axi[31:0],
                $time
            );
        end
        debug_request_toggle_q <= DUT.request_toggle_r;
    end

    initial begin
        logic [31:0] value;
        int unsigned expected_stress_errors;
        $readmemh("generated/test_vectors/sample_000_input.mem", input_pixels);
        $readmemh("generated/test_vectors/sample_000_threshold.mem", expected_pixels);
        mismatch_count = 0;
        output_count = 0;
        debug_request_toggle_q = 1'b0;
        debug_response_toggle_q = 1'b0;
        s_axi_aresetn = 1'b0;
        axis_aresetn = 1'b0;
        s_axi_awaddr = '0;
        s_axi_awprot = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata = '0;
        s_axi_wstrb = '0;
        s_axi_wvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_araddr = '0;
        s_axi_arprot = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;
        s_axis_tdata = '0;
        s_axis_tkeep = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b0;

        repeat (8) @(posedge s_axi_aclk);
        s_axi_aresetn = 1'b1;
        repeat (5) @(posedge axis_aclk);
        axis_aresetn = 1'b1;
        repeat (8) @(posedge s_axi_aclk);

        axi_read(ADDR_IMAGE_PIXELS, value);
        if (value != IMAGE_PIXELS) begin
            mismatch_count++;
            $error("CDC IMAGE_PIXELS actual=%0d expected=%0d", value, IMAGE_PIXELS);
        end
        axi_read(ADDR_IP_ID, value);
        if (value != 32'h5a42_4156) begin
            mismatch_count++;
            $error("CDC IP_ID actual=%08h", value);
        end

        // Independent idle reset assertions must flush bridge toggle history
        // and permit the next transaction without replaying a stale request.
        axis_aresetn = 1'b0;
        repeat (4) @(posedge s_axi_aclk);
        axis_aresetn = 1'b1;
        repeat (8) @(posedge s_axi_aclk);
        axi_read(ADDR_IP_ID, value);
        if (value != 32'h5a42_4156) begin
            mismatch_count++;
            $error("CDC read failed after AXIS-only reset: %08h", value);
        end

        s_axi_aresetn = 1'b0;
        repeat (4) @(posedge s_axi_aclk);
        s_axi_aresetn = 1'b1;
        repeat (8) @(posedge s_axi_aclk);
        axi_read(ADDR_IP_ID, value);
        if (value != 32'h5a42_4156) begin
            mismatch_count++;
            $error("CDC read failed after AXI-only reset: %08h", value);
        end

        check_reset_abort_recovery();

        stress_control_bridge(expected_stress_errors);
        axi_read(ADDR_ERROR_COUNT, value);
        if (value != expected_stress_errors) begin
            mismatch_count++;
            $error(
                "CDC stress ERROR_COUNT actual=%0d expected=%0d",
                value,
                expected_stress_errors
            );
        end

        axis_aresetn = 1'b0;
        repeat (4) @(posedge s_axi_aclk);
        axis_aresetn = 1'b1;
        repeat (8) @(posedge s_axi_aclk);
        axi_read(ADDR_THRESHOLD, value);
        if (value[7:0] != 8'd128) begin
            mismatch_count++;
            $error("CDC stress reset did not restore threshold: %0d", value[7:0]);
        end

        axi_write(ADDR_ERROR_STATUS, 32'h0000_0007, 0, 0, 2'b00);
        axi_write(ADDR_INT_STATUS, 32'h0000_0007, 0, 0, 2'b00);
        axi_write(ADDR_PERF_CONTROL, 32'h0000_0001, 0, 0, 2'b00);
        axi_write(ADDR_THRESHOLD, 32'd96, 0, 4, 2'b00);
        axi_write(ADDR_THRESHOLD, 32'd128, 4, 0, 2'b00);
        axi_read(ADDR_THRESHOLD, value);
        if (value[7:0] != 8'd128) begin
            mismatch_count++;
            $error("CDC threshold readback actual=%0d", value[7:0]);
        end
        axi_write(ADDR_INT_ENABLE, 32'd1, 0, 0, 2'b00);
        axi_write(ADDR_MODE, 32'd0, 0, 0, 2'b00);
        axi_write(ADDR_CTRL, 32'd1, 0, 0, 2'b00);

        m_axis_tready = 1'b1;
        for (int index = 0; index < IMAGE_PIXELS; index++) begin
            send_pixel(index);
        end
        wait (output_count == IMAGE_PIXELS);
        repeat (8) @(posedge s_axi_aclk);
        if (!irq) begin
            mismatch_count++;
            $error("CDC synchronized done IRQ did not assert");
        end
        axi_read(ADDR_STATUS, value);
        if ((value[2:0] != 3'b010)) begin
            mismatch_count++;
            $error("CDC terminal status actual=%08h", value);
        end
        axi_read(ADDR_PROCESSING_CYCLES, value);
        if (value == 0) begin
            mismatch_count++;
            $error("CDC processing cycle count was zero");
        end
        axi_write(ADDR_INT_STATUS, 32'd1, 0, 0, 2'b00);
        repeat (4) @(posedge s_axi_aclk);
        if (irq) begin
            mismatch_count++;
            $error("CDC synchronized done IRQ did not clear");
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: dual-clock AXI-Lite bridge matched %0d threshold outputs with half-periods %0d/%0d ps.",
                IMAGE_PIXELS,
                S_AXI_HALF_PERIOD_PS,
                AXIS_HALF_PERIOD_PS
            );
            $finish;
        end
        $fatal(1, "FAIL: dual-clock wrapper found %0d mismatch(es)", mismatch_count);
    end

    initial begin
        repeat (100000) @(posedge axis_aclk);
        $fatal(1, "FAIL: dual-clock wrapper timeout");
    end
endmodule
