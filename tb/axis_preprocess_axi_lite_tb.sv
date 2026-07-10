`timescale 1 ns / 100 ps

// Module: axis_preprocess_axi_lite_tb
// Description:
//Verifies the selectable AXI4-Stream preprocessing top with AXI4-Lite control.

module axis_preprocess_axi_lite_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int C_AXIS_DATA_WIDTH = 32,
    parameter int C_AXIS_KEEP_WIDTH = C_AXIS_DATA_WIDTH / 8,
    parameter int TIMEOUT_CYCLES = 50000
);

    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CTRL              = 8'h00;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATUS            = 8'h04;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_THRESHOLD         = 8'h08;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IMAGE_PIXELS      = 8'h0c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PIXELS_PER_CYCLE  = 8'h10;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_MODE              = 8'h2c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K00          = 8'h30;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K01          = 8'h34;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K02          = 8'h38;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K10          = 8'h3c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K11          = 8'h40;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K12          = 8'h44;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K20          = 8'h48;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K21          = 8'h4c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K22          = 8'h50;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_BIAS         = 8'h54;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_SHIFT        = 8'h58;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_RELU_EN      = 8'h5c;

    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_SOBEL = 1;
    localparam int MODE_CONV3X3 = 2;
    localparam logic [C_AXIS_KEEP_WIDTH-1:0] PIXEL_KEEP = '1;

    logic                                      clk = 1'b0;
    logic                                      rstn;

    logic [C_S_AXI_ADDR_WIDTH-1:0]             s_axi_awaddr;
    logic [2:0]                                s_axi_awprot;
    logic                                      s_axi_awvalid;
    logic                                      s_axi_awready;
    logic [C_S_AXI_DATA_WIDTH-1:0]             s_axi_wdata;
    logic [(C_S_AXI_DATA_WIDTH/8)-1:0]         s_axi_wstrb;
    logic                                      s_axi_wvalid;
    logic                                      s_axi_wready;
    logic [1:0]                                s_axi_bresp;
    logic                                      s_axi_bvalid;
    logic                                      s_axi_bready;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             s_axi_araddr;
    logic [2:0]                                s_axi_arprot;
    logic                                      s_axi_arvalid;
    logic                                      s_axi_arready;
    logic [C_S_AXI_DATA_WIDTH-1:0]             s_axi_rdata;
    logic [1:0]                                s_axi_rresp;
    logic                                      s_axi_rvalid;
    logic                                      s_axi_rready;

    logic [C_AXIS_DATA_WIDTH-1:0]              s_axis_tdata;
    logic [C_AXIS_KEEP_WIDTH-1:0]              s_axis_tkeep;
    logic                                      s_axis_tvalid;
    logic                                      s_axis_tready;
    logic                                      s_axis_tlast;

    logic [C_AXIS_DATA_WIDTH-1:0]              m_axis_tdata;
    logic [C_AXIS_KEEP_WIDTH-1:0]              m_axis_tkeep;
    logic                                      m_axis_tvalid;
    logic                                      m_axis_tready;
    logic                                      m_axis_tlast;

    logic [DATA_WIDTH-1:0]                     input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0]                     expected_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int preprocess_mode = MODE_THRESHOLD;
    int output_count = 0;
    int mismatch_count = 0;

    logic [C_AXIS_DATA_WIDTH-1:0] held_tdata;
    logic [C_AXIS_KEEP_WIDTH-1:0] held_tkeep;
    logic                         held_tlast;
    logic                         was_stalled;
    logic                         ready_enable;
    int                           ready_pattern_count = 0;

    axis_preprocess_axi_lite #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_AXIS_DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
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
        .S_AXI_RREADY(s_axi_rready),
        .S_AXIS_TDATA(s_axis_tdata),
        .S_AXIS_TKEEP(s_axis_tkeep),
        .S_AXIS_TVALID(s_axis_tvalid),
        .S_AXIS_TREADY(s_axis_tready),
        .S_AXIS_TLAST(s_axis_tlast),
        .M_AXIS_TDATA(m_axis_tdata),
        .M_AXIS_TKEEP(m_axis_tkeep),
        .M_AXIS_TVALID(m_axis_tvalid),
        .M_AXIS_TREADY(m_axis_tready),
        .M_AXIS_TLAST(m_axis_tlast)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    task automatic axi_write(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        s_axi_awaddr <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata <= data;
        s_axi_wstrb <= '1;
        s_axi_wvalid <= 1'b1;
        s_axi_bready <= 1'b1;

        @(posedge clk);
        @(negedge clk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid <= 1'b0;

        while (s_axi_bvalid !== 1'b1) begin
            @(posedge clk);
        end

        if (s_axi_bresp !== 2'b00) begin
            mismatch_count++;
            $error("AXI write response error at addr 0x%02h: bresp=%0b", addr, s_axi_bresp);
        end

        @(posedge clk);
        @(negedge clk);
        s_axi_bready <= 1'b0;
        s_axi_awaddr <= '0;
        s_axi_wdata <= '0;
        s_axi_wstrb <= '0;
    endtask

    task automatic axi_read(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        output logic [C_S_AXI_DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        s_axi_araddr <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready <= 1'b1;

        @(posedge clk);
        @(negedge clk);
        s_axi_arvalid <= 1'b0;

        while (s_axi_rvalid !== 1'b1) begin
            @(posedge clk);
        end

        data = s_axi_rdata;
        if (s_axi_rresp !== 2'b00) begin
            mismatch_count++;
            $error("AXI read response error at addr 0x%02h: rresp=%0b", addr, s_axi_rresp);
        end

        @(posedge clk);
        @(negedge clk);
        s_axi_rready <= 1'b0;
        s_axi_araddr <= '0;
    endtask

    task automatic send_pixel(
        input int pixel_index
    );
        begin
            s_axis_tdata  <= {{(C_AXIS_DATA_WIDTH-DATA_WIDTH){1'b0}}, input_pixels[pixel_index]};
            s_axis_tkeep  <= PIXEL_KEEP;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (pixel_index == IMAGE_PIXELS - 1);

            do begin
                @(posedge clk);
            end while (s_axis_tready !== 1'b1);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;

            if (((pixel_index % 31) == 9) || ((pixel_index % 47) == 16)) begin
                @(posedge clk);
            end
        end
    endtask

    initial begin : provide_stimulus
        logic [C_S_AXI_DATA_WIDTH-1:0] read_value;
        logic [C_S_AXI_DATA_WIDTH-1:0] status_value;

        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));
        void'($value$plusargs("MODE=%d", preprocess_mode));

        $timeformat(-9, 0, " ns");
        $display("AXI4-Stream top input MEM:    %s", input_mem_path);
        $display("AXI4-Stream top expected MEM: %s", expected_mem_path);
        $display("AXI4-Stream top mode:         %0d", preprocess_mode);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_pixels);

        rstn <= 1'b0;
        s_axi_awaddr <= '0;
        s_axi_awprot <= '0;
        s_axi_awvalid <= 1'b0;
        s_axi_wdata <= '0;
        s_axi_wstrb <= '0;
        s_axi_wvalid <= 1'b0;
        s_axi_bready <= 1'b0;
        s_axi_araddr <= '0;
        s_axi_arprot <= '0;
        s_axi_arvalid <= 1'b0;
        s_axi_rready <= 1'b0;
        s_axis_tdata <= '0;
        s_axis_tkeep <= '0;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        ready_enable <= 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn <= 1'b1;

        repeat (2) @(posedge clk);
        if (s_axis_tready !== 1'b0) begin
            mismatch_count++;
            $error("S_AXIS_TREADY was high before CTRL.start armed the stream core.");
        end

        axi_read(ADDR_IMAGE_PIXELS, read_value);
        if (read_value !== C_S_AXI_DATA_WIDTH'(IMAGE_PIXELS)) begin
            mismatch_count++;
            $error("IMAGE_PIXELS mismatch: actual=%0d expected=%0d", read_value, IMAGE_PIXELS);
        end

        axi_read(ADDR_PIXELS_PER_CYCLE, read_value);
        if (read_value !== C_S_AXI_DATA_WIDTH'(1)) begin
            mismatch_count++;
            $error("PIXELS_PER_CYCLE mismatch: actual=%0d expected=1", read_value);
        end

        axi_write(ADDR_THRESHOLD, C_S_AXI_DATA_WIDTH'(128));
        axi_write(ADDR_MODE, C_S_AXI_DATA_WIDTH'(preprocess_mode));

        if (preprocess_mode == MODE_CONV3X3) begin
            axi_write(ADDR_CONV_K00, C_S_AXI_DATA_WIDTH'(-2));
            axi_write(ADDR_CONV_K01, C_S_AXI_DATA_WIDTH'(-1));
            axi_write(ADDR_CONV_K02, C_S_AXI_DATA_WIDTH'(0));
            axi_write(ADDR_CONV_K10, C_S_AXI_DATA_WIDTH'(-1));
            axi_write(ADDR_CONV_K11, C_S_AXI_DATA_WIDTH'(6));
            axi_write(ADDR_CONV_K12, C_S_AXI_DATA_WIDTH'(1));
            axi_write(ADDR_CONV_K20, C_S_AXI_DATA_WIDTH'(0));
            axi_write(ADDR_CONV_K21, C_S_AXI_DATA_WIDTH'(1));
            axi_write(ADDR_CONV_K22, C_S_AXI_DATA_WIDTH'(2));
            axi_write(ADDR_CONV_BIAS, C_S_AXI_DATA_WIDTH'(-128));
            axi_write(ADDR_CONV_SHIFT, C_S_AXI_DATA_WIDTH'(3));
            axi_write(ADDR_CONV_RELU_EN, C_S_AXI_DATA_WIDTH'(1));
        end

        axi_write(ADDR_CTRL, C_S_AXI_DATA_WIDTH'(1));

        axi_read(ADDR_STATUS, status_value);
        if (status_value[0] !== 1'b1 || status_value[3] !== 1'b1) begin
            mismatch_count++;
            $error("STATUS did not report busy/armed after start: status=0x%08h", status_value);
        end

        ready_enable <= 1'b1;

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            send_pixel(pixel);
        end

        wait (output_count == IMAGE_PIXELS);
        repeat (3) @(posedge clk);

        axi_read(ADDR_STATUS, status_value);
        if (status_value[0] !== 1'b0) begin
            mismatch_count++;
            $error("STATUS.busy stayed high after output packet: status=0x%08h", status_value);
        end

        if (status_value[1] !== 1'b1) begin
            mismatch_count++;
            $error("STATUS.done did not latch after output packet: status=0x%08h", status_value);
        end

        if (status_value[2] !== 1'b0) begin
            mismatch_count++;
            $error("STATUS.packet_error asserted for legal packet: status=0x%08h", status_value);
        end

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        if (read_value == 0) begin
            mismatch_count++;
            $error("PROCESSING_CYCLES was zero after stream operation.");
        end

        axi_write(ADDR_CTRL, C_S_AXI_DATA_WIDTH'(2));
        axi_read(ADDR_STATUS, status_value);
        if (status_value[1] !== 1'b0) begin
            mismatch_count++;
            $error("STATUS.done did not clear after CTRL.clear_done: status=0x%08h", status_value);
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: AXI4-Stream selectable top mode %0d matched %0d pixels in %0d cycles.",
                preprocess_mode,
                IMAGE_PIXELS,
                read_value
            );
            $finish;
        end

        $fatal(1, "FAIL: AXI4-Stream selectable top found %0d issue(s).", mismatch_count);
    end

    initial begin : drive_output_backpressure
        forever begin
            @(posedge clk);

            if (rstn === 1'b0) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (ready_enable !== 1'b1) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (((ready_pattern_count % 19) == 4) ||
                         ((ready_pattern_count % 37) == 15)) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= ready_pattern_count + 1;
            end else begin
                m_axis_tready <= 1'b1;
                ready_pattern_count <= ready_pattern_count + 1;
            end
        end
    end

    initial begin : check_output_stream
        forever begin
            @(posedge clk);

            if (rstn === 1'b0) begin
                output_count <= 0;
            end else if ((m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b1)) begin
                if (output_count >= IMAGE_PIXELS) begin
                    mismatch_count++;
                    $error("Received extra output beat %0d.", output_count);
                end else begin
                    if (m_axis_tkeep !== PIXEL_KEEP) begin
                        mismatch_count++;
                        $error(
                            "tkeep mismatch at output %0d: actual=0x%0h expected=0x%0h",
                            output_count,
                            m_axis_tkeep,
                            PIXEL_KEEP
                        );
                    end

                    if (m_axis_tdata[C_AXIS_DATA_WIDTH-1:DATA_WIDTH] !== '0) begin
                        mismatch_count++;
                        $error(
                            "upper tdata bits were nonzero at output %0d: actual=0x%0h",
                            output_count,
                            m_axis_tdata
                        );
                    end

                    if (m_axis_tdata[DATA_WIDTH-1:0] !== expected_pixels[output_count]) begin
                        mismatch_count++;
                        $error(
                            "pixel mismatch at output %0d: actual=0x%02h expected=0x%02h",
                            output_count,
                            m_axis_tdata[DATA_WIDTH-1:0],
                            expected_pixels[output_count]
                        );
                    end

                    if (m_axis_tlast !== (output_count == IMAGE_PIXELS - 1)) begin
                        mismatch_count++;
                        $error(
                            "tlast mismatch at output %0d: actual=%0b expected=%0b",
                            output_count,
                            m_axis_tlast,
                            (output_count == IMAGE_PIXELS - 1)
                        );
                    end
                end

                output_count <= output_count + 1;
            end
        end
    end

    initial begin : check_stall_stability
        was_stalled <= 1'b0;
        held_tdata  <= '0;
        held_tkeep  <= '0;
        held_tlast  <= 1'b0;

        forever begin
            @(posedge clk);

            if (rstn === 1'b0) begin
                was_stalled <= 1'b0;
            end else begin
                if (was_stalled && (m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b0)) begin
                    if ((m_axis_tdata !== held_tdata) ||
                        (m_axis_tkeep !== held_tkeep) ||
                        (m_axis_tlast !== held_tlast)) begin
                        mismatch_count++;
                        $error("AXI4-Stream selectable top output changed while stalled.");
                    end
                end

                if ((m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b0)) begin
                    held_tdata  <= m_axis_tdata;
                    held_tkeep  <= m_axis_tkeep;
                    held_tlast  <= m_axis_tlast;
                    was_stalled <= 1'b1;
                end else begin
                    was_stalled <= 1'b0;
                end
            end
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule
