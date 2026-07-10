`timescale 1 ns / 100 ps

// Module: image_preprocess_axi_lite_tb
// Description:
//   Verifies the AXI4-Lite wrapper using the same register flow expected from
//   the ARM software.

module image_preprocess_axi_lite_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int TIMEOUT_CYCLES = 20000
);

    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CTRL              = 8'h00;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATUS            = 8'h04;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_THRESHOLD         = 8'h08;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IMAGE_PIXELS      = 8'h0c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PIXELS_PER_CYCLE  = 8'h10;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_INPUT_ADDR        = 8'h18;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_INPUT_WDATA       = 8'h1c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_INPUT_WMASK       = 8'h20;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_ADDR       = 8'h24;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_RDATA      = 8'h28;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_MODE              = 8'h2c;

    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_SOBEL = 1;
    localparam int SOBEL_BORDER_PIXELS = (2 * IMAGE_WIDTH) + (2 * (IMAGE_HEIGHT - 2));
    localparam int SOBEL_EXPECTED_CYCLES = SOBEL_BORDER_PIXELS + IMAGE_PIXELS + 6;

    logic                                  clk = 1'b0;
    logic                                  rstn;
    logic [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_awaddr;
    logic [2:0]                            s_axi_awprot;
    logic                                  s_axi_awvalid;
    logic                                  s_axi_awready;
    logic [C_S_AXI_DATA_WIDTH-1:0]         s_axi_wdata;
    logic [(C_S_AXI_DATA_WIDTH/8)-1:0]     s_axi_wstrb;
    logic                                  s_axi_wvalid;
    logic                                  s_axi_wready;
    logic [1:0]                            s_axi_bresp;
    logic                                  s_axi_bvalid;
    logic                                  s_axi_bready;
    logic [C_S_AXI_ADDR_WIDTH-1:0]         s_axi_araddr;
    logic [2:0]                            s_axi_arprot;
    logic                                  s_axi_arvalid;
    logic                                  s_axi_arready;
    logic [C_S_AXI_DATA_WIDTH-1:0]         s_axi_rdata;
    logic [1:0]                            s_axi_rresp;
    logic                                  s_axi_rvalid;
    logic                                  s_axi_rready;

    logic [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int mismatch_count = 0;
    int preprocess_mode = MODE_THRESHOLD;

    image_preprocess_axi_lite #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
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

    initial begin : provide_stimulus
        logic [C_S_AXI_DATA_WIDTH-1:0] read_value;
        logic [C_S_AXI_DATA_WIDTH-1:0] status_value;

        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));
        void'($value$plusargs("MODE=%d", preprocess_mode));

        $timeformat(-9, 0, " ns");
        $display("AXI input MEM:    %s", input_mem_path);
        $display("AXI expected MEM: %s", expected_mem_path);

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

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn <= 1'b1;

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
        axi_write(ADDR_INPUT_WMASK, C_S_AXI_DATA_WIDTH'(1));

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_INPUT_ADDR, C_S_AXI_DATA_WIDTH'(pixel));
            axi_write(ADDR_INPUT_WDATA, C_S_AXI_DATA_WIDTH'(input_pixels[pixel]));
        end

        axi_write(ADDR_CTRL, C_S_AXI_DATA_WIDTH'(1));

        status_value = '0;
        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            axi_read(ADDR_STATUS, status_value);
            if (status_value[1] === 1'b1) begin
                break;
            end
        end

        if (status_value[1] !== 1'b1) begin
            $fatal(1, "FAIL: AXI wrapper did not report done.");
        end

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        if (preprocess_mode == MODE_SOBEL) begin
            if (read_value !== C_S_AXI_DATA_WIDTH'(SOBEL_EXPECTED_CYCLES)) begin
                mismatch_count++;
                $error("Expected %0d Sobel cycles, saw %0d.", SOBEL_EXPECTED_CYCLES, read_value);
            end
        end else if (read_value !== C_S_AXI_DATA_WIDTH'(IMAGE_PIXELS + 2)) begin
            mismatch_count++;
            $error("Expected %0d cycles, saw %0d.", IMAGE_PIXELS + 2, read_value);
        end

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_OUTPUT_ADDR, C_S_AXI_DATA_WIDTH'(pixel));
            axi_read(ADDR_OUTPUT_RDATA, read_value);

            if (read_value[DATA_WIDTH-1:0] !== expected_pixels[pixel]) begin
                mismatch_count++;
                $error(
                    "AXI output mismatch at pixel %0d: actual=0x%02h expected=0x%02h",
                    pixel,
                    read_value[DATA_WIDTH-1:0],
                    expected_pixels[pixel]
                );
            end
        end

        if (mismatch_count == 0) begin
            $display("PASS: AXI wrapper matched %0d pixels.", IMAGE_PIXELS);
            $finish;
        end

        $fatal(1, "FAIL: AXI wrapper test found %0d issue(s).", mismatch_count);
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES * 10) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES * 10);
    end

endmodule
