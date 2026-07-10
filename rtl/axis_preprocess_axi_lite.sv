`timescale 1 ns / 100 ps

// Module: axis_preprocess_axi_lite
// Description:
//AXI4-Lite configured AXI4-Stream preprocessing top for DMA-based image movement.

module axis_preprocess_axi_lite #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int C_AXIS_DATA_WIDTH = 32,
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                                      S_AXI_ACLK,
    input  logic                                      S_AXI_ARESETN,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]             S_AXI_AWADDR,
    input  logic [2:0]                                S_AXI_AWPROT,
    input  logic                                      S_AXI_AWVALID,
    output logic                                      S_AXI_AWREADY,

    input  logic [C_S_AXI_DATA_WIDTH-1:0]             S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]         S_AXI_WSTRB,
    input  logic                                      S_AXI_WVALID,
    output logic                                      S_AXI_WREADY,

    output logic [1:0]                                S_AXI_BRESP,
    output logic                                      S_AXI_BVALID,
    input  logic                                      S_AXI_BREADY,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]             S_AXI_ARADDR,
    input  logic [2:0]                                S_AXI_ARPROT,
    input  logic                                      S_AXI_ARVALID,
    output logic                                      S_AXI_ARREADY,

    output logic [C_S_AXI_DATA_WIDTH-1:0]             S_AXI_RDATA,
    output logic [1:0]                                S_AXI_RRESP,
    output logic                                      S_AXI_RVALID,
    input  logic                                      S_AXI_RREADY,

    input  logic [C_AXIS_DATA_WIDTH-1:0]              S_AXIS_TDATA,
    input  logic [(C_AXIS_DATA_WIDTH/8)-1:0]          S_AXIS_TKEEP,
    input  logic                                      S_AXIS_TVALID,
    output logic                                      S_AXIS_TREADY,
    input  logic                                      S_AXIS_TLAST,

    output logic [C_AXIS_DATA_WIDTH-1:0]              M_AXIS_TDATA,
    output logic [(C_AXIS_DATA_WIDTH/8)-1:0]          M_AXIS_TKEEP,
    output logic                                      M_AXIS_TVALID,
    input  logic                                      M_AXIS_TREADY,
    output logic                                      M_AXIS_TLAST
);

    localparam int AXI_STRB_WIDTH = C_S_AXI_DATA_WIDTH / 8;
    localparam int AXIS_KEEP_WIDTH = C_AXIS_DATA_WIDTH / 8;

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

    localparam logic [1:0] MODE_THRESHOLD = 2'd0;
    localparam logic [1:0] MODE_SOBEL     = 2'd1;
    localparam logic [1:0] MODE_CONV3X3   = 2'd2;

    logic                                      rst;
    logic                                      aw_captured_r;
    logic                                      w_captured_r;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             awaddr_r;
    logic [C_S_AXI_DATA_WIDTH-1:0]             wdata_r;
    logic [AXI_STRB_WIDTH-1:0]                 wstrb_r;
    logic                                      write_fire;
    logic [C_S_AXI_DATA_WIDTH-1:0]             write_data_masked;

    logic                                      reg_write_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             reg_write_addr;
    logic [C_S_AXI_DATA_WIDTH-1:0]             reg_write_data;
    logic                                      reg_read_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             reg_read_addr;
    logic [C_S_AXI_DATA_WIDTH-1:0]             reg_read_data;

    logic [DATA_WIDTH-1:0]                     threshold_r;
    logic [DATA_WIDTH-1:0]                     active_threshold_r;
    logic [1:0]                                mode_r;
    logic [1:0]                                active_mode_r;
    logic signed [7:0]                         conv_k00_r;
    logic signed [7:0]                         conv_k01_r;
    logic signed [7:0]                         conv_k02_r;
    logic signed [7:0]                         conv_k10_r;
    logic signed [7:0]                         conv_k11_r;
    logic signed [7:0]                         conv_k12_r;
    logic signed [7:0]                         conv_k20_r;
    logic signed [7:0]                         conv_k21_r;
    logic signed [7:0]                         conv_k22_r;
    logic signed [31:0]                        conv_bias_r;
    logic [4:0]                                conv_shift_r;
    logic                                      conv_relu_enable_r;
    logic signed [7:0]                         active_conv_k00_r;
    logic signed [7:0]                         active_conv_k01_r;
    logic signed [7:0]                         active_conv_k02_r;
    logic signed [7:0]                         active_conv_k10_r;
    logic signed [7:0]                         active_conv_k11_r;
    logic signed [7:0]                         active_conv_k12_r;
    logic signed [7:0]                         active_conv_k20_r;
    logic signed [7:0]                         active_conv_k21_r;
    logic signed [7:0]                         active_conv_k22_r;
    logic signed [31:0]                        active_conv_bias_r;
    logic [4:0]                                active_conv_shift_r;
    logic                                      active_conv_relu_enable_r;
    logic                                      armed_r;
    logic                                      done_latched_r;
    logic                                      packet_error_latched_r;
    logic [CYCLE_COUNT_WIDTH-1:0]              processing_cycles_latched_r;
    logic                                      start_pulse;
    logic                                      clear_done_pulse;
    logic                                      stream_busy;

    logic                                      threshold_clear_done;
    logic                                      threshold_busy;
    logic                                      threshold_done;
    logic                                      threshold_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              threshold_cycles;
    logic                                      threshold_s_tvalid;
    logic                                      threshold_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              threshold_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                threshold_m_tkeep;
    logic                                      threshold_m_tvalid;
    logic                                      threshold_m_tready;
    logic                                      threshold_m_tlast;

    logic                                      sobel_clear_done;
    logic                                      sobel_busy;
    logic                                      sobel_done;
    logic                                      sobel_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              sobel_cycles;
    logic                                      sobel_s_tvalid;
    logic                                      sobel_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              sobel_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                sobel_m_tkeep;
    logic                                      sobel_m_tvalid;
    logic                                      sobel_m_tready;
    logic                                      sobel_m_tlast;

    logic                                      conv_clear_done;
    logic                                      conv_busy;
    logic                                      conv_done;
    logic                                      conv_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              conv_cycles;
    logic                                      conv_s_tvalid;
    logic                                      conv_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              conv_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                conv_m_tkeep;
    logic                                      conv_m_tvalid;
    logic                                      conv_m_tready;
    logic                                      conv_m_tlast;

    assign rst = ~S_AXI_ARESETN;
    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;

    assign S_AXI_AWREADY = !aw_captured_r && !S_AXI_BVALID;
    assign S_AXI_WREADY = !w_captured_r && !S_AXI_BVALID;
    assign S_AXI_ARREADY = !S_AXI_RVALID;

    assign write_fire = aw_captured_r && w_captured_r && !S_AXI_BVALID;
    assign reg_read_en = S_AXI_ARVALID && S_AXI_ARREADY;
    assign reg_read_addr = S_AXI_ARADDR;

    assign start_pulse =
        reg_write_en && (reg_write_addr == ADDR_CTRL) && reg_write_data[0] && !stream_busy;

    assign clear_done_pulse =
        reg_write_en && (reg_write_addr == ADDR_CTRL) && reg_write_data[1];

    assign stream_busy = armed_r;

    assign threshold_clear_done = clear_done_pulse || start_pulse;
    assign sobel_clear_done = clear_done_pulse || start_pulse;
    assign conv_clear_done = clear_done_pulse || start_pulse;

    assign threshold_s_tvalid =
        armed_r && (active_mode_r == MODE_THRESHOLD) && S_AXIS_TVALID;

    assign sobel_s_tvalid =
        armed_r && (active_mode_r == MODE_SOBEL) && S_AXIS_TVALID;

    assign conv_s_tvalid =
        armed_r && (active_mode_r == MODE_CONV3X3) && S_AXIS_TVALID;

    assign S_AXIS_TREADY =
        !armed_r                         ? 1'b0 :
        (active_mode_r == MODE_THRESHOLD) ? threshold_s_tready :
        (active_mode_r == MODE_SOBEL)     ? sobel_s_tready :
        (active_mode_r == MODE_CONV3X3)   ? conv_s_tready :
                                            1'b0;

    assign threshold_m_tready =
        armed_r && (active_mode_r == MODE_THRESHOLD) && M_AXIS_TREADY;

    assign sobel_m_tready =
        armed_r && (active_mode_r == MODE_SOBEL) && M_AXIS_TREADY;

    assign conv_m_tready =
        armed_r && (active_mode_r == MODE_CONV3X3) && M_AXIS_TREADY;

    assign M_AXIS_TDATA =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tdata :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tdata :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tdata :
                                                          '0;

    assign M_AXIS_TKEEP =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tkeep :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tkeep :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tkeep :
                                                          '0;

    assign M_AXIS_TVALID =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tvalid :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tvalid :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tvalid :
                                                          1'b0;

    assign M_AXIS_TLAST =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tlast :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tlast :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tlast :
                                                          1'b0;

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] apply_write_strobes(
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [AXI_STRB_WIDTH-1:0] strobes
    );
        logic [C_S_AXI_DATA_WIDTH-1:0] masked;

        masked = '0;
        for (int byte_index = 0; byte_index < AXI_STRB_WIDTH; byte_index++) begin
            if (strobes[byte_index]) begin
                masked[byte_index*8 +: 8] = data[byte_index*8 +: 8];
            end
        end

        return masked;
    endfunction

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] read_register(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr
    );
        logic [C_S_AXI_DATA_WIDTH-1:0] value;

        value = '0;
        unique case (addr)
            ADDR_STATUS : begin
                value[0] = stream_busy;
                value[1] = done_latched_r;
                value[2] = packet_error_latched_r;
                value[3] = armed_r;
            end

            ADDR_THRESHOLD : begin
                value[DATA_WIDTH-1:0] = threshold_r;
            end

            ADDR_IMAGE_PIXELS : begin
                value = C_S_AXI_DATA_WIDTH'(IMAGE_PIXELS);
            end

            ADDR_PIXELS_PER_CYCLE : begin
                value = C_S_AXI_DATA_WIDTH'(1);
            end

            ADDR_PROCESSING_CYCLES : begin
                value[CYCLE_COUNT_WIDTH-1:0] = processing_cycles_latched_r;
            end

            ADDR_MODE : begin
                value[1:0] = mode_r;
            end

            ADDR_CONV_K00 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k00_r[7]}}, conv_k00_r};
            end

            ADDR_CONV_K01 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k01_r[7]}}, conv_k01_r};
            end

            ADDR_CONV_K02 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k02_r[7]}}, conv_k02_r};
            end

            ADDR_CONV_K10 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k10_r[7]}}, conv_k10_r};
            end

            ADDR_CONV_K11 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k11_r[7]}}, conv_k11_r};
            end

            ADDR_CONV_K12 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k12_r[7]}}, conv_k12_r};
            end

            ADDR_CONV_K20 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k20_r[7]}}, conv_k20_r};
            end

            ADDR_CONV_K21 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k21_r[7]}}, conv_k21_r};
            end

            ADDR_CONV_K22 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k22_r[7]}}, conv_k22_r};
            end

            ADDR_CONV_BIAS : begin
                value = conv_bias_r;
            end

            ADDR_CONV_SHIFT : begin
                value[4:0] = conv_shift_r;
            end

            ADDR_CONV_RELU_EN : begin
                value[0] = conv_relu_enable_r;
            end

            default : begin
                value = '0;
            end
        endcase

        return value;
    endfunction

    assign write_data_masked = apply_write_strobes(wdata_r, wstrb_r);
    assign reg_read_data = read_register(reg_read_addr);

    axis_threshold_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .IMAGE_PIXELS(IMAGE_PIXELS),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) threshold_path (
        .aclk(S_AXI_ACLK),
        .aresetn(S_AXI_ARESETN),
        .threshold(active_threshold_r),
        .clear_done(threshold_clear_done),
        .busy(threshold_busy),
        .done(threshold_done),
        .packet_error(threshold_packet_error),
        .processing_cycles(threshold_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(threshold_s_tvalid),
        .s_axis_tready(threshold_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(threshold_m_tdata),
        .m_axis_tkeep(threshold_m_tkeep),
        .m_axis_tvalid(threshold_m_tvalid),
        .m_axis_tready(threshold_m_tready),
        .m_axis_tlast(threshold_m_tlast)
    );

    axis_sobel_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) sobel_path (
        .aclk(S_AXI_ACLK),
        .aresetn(S_AXI_ARESETN),
        .clear_done(sobel_clear_done),
        .busy(sobel_busy),
        .done(sobel_done),
        .packet_error(sobel_packet_error),
        .processing_cycles(sobel_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(sobel_s_tvalid),
        .s_axis_tready(sobel_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(sobel_m_tdata),
        .m_axis_tkeep(sobel_m_tkeep),
        .m_axis_tvalid(sobel_m_tvalid),
        .m_axis_tready(sobel_m_tready),
        .m_axis_tlast(sobel_m_tlast)
    );

    axis_conv3x3_parallel_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) conv_path (
        .aclk(S_AXI_ACLK),
        .aresetn(S_AXI_ARESETN),
        .conv_k00(active_conv_k00_r),
        .conv_k01(active_conv_k01_r),
        .conv_k02(active_conv_k02_r),
        .conv_k10(active_conv_k10_r),
        .conv_k11(active_conv_k11_r),
        .conv_k12(active_conv_k12_r),
        .conv_k20(active_conv_k20_r),
        .conv_k21(active_conv_k21_r),
        .conv_k22(active_conv_k22_r),
        .conv_bias(active_conv_bias_r),
        .conv_shift(active_conv_shift_r),
        .conv_relu_enable(active_conv_relu_enable_r),
        .clear_done(conv_clear_done),
        .busy(conv_busy),
        .done(conv_done),
        .packet_error(conv_packet_error),
        .processing_cycles(conv_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(conv_s_tvalid),
        .s_axis_tready(conv_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(conv_m_tdata),
        .m_axis_tkeep(conv_m_tkeep),
        .m_axis_tvalid(conv_m_tvalid),
        .m_axis_tready(conv_m_tready),
        .m_axis_tlast(conv_m_tlast)
    );

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            aw_captured_r <= 1'b0;
            w_captured_r <= 1'b0;
            awaddr_r <= '0;
            wdata_r <= '0;
            wstrb_r <= '0;
            S_AXI_BVALID <= 1'b0;
            reg_write_en <= 1'b0;
            reg_write_addr <= '0;
            reg_write_data <= '0;
        end else begin
            reg_write_en <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_captured_r <= 1'b1;
                awaddr_r <= S_AXI_AWADDR;
            end

            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_captured_r <= 1'b1;
                wdata_r <= S_AXI_WDATA;
                wstrb_r <= S_AXI_WSTRB;
            end

            if (write_fire) begin
                reg_write_en <= 1'b1;
                reg_write_addr <= awaddr_r;
                reg_write_data <= write_data_masked;
                aw_captured_r <= 1'b0;
                w_captured_r <= 1'b0;
                S_AXI_BVALID <= 1'b1;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA <= '0;
        end else begin
            if (reg_read_en) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RDATA <= reg_read_data;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            threshold_r <= DATA_WIDTH'(128);
            active_threshold_r <= DATA_WIDTH'(128);
            mode_r <= MODE_THRESHOLD;
            active_mode_r <= MODE_THRESHOLD;
            conv_k00_r <= -8'sd2;
            conv_k01_r <= -8'sd1;
            conv_k02_r <= 8'sd0;
            conv_k10_r <= -8'sd1;
            conv_k11_r <= 8'sd6;
            conv_k12_r <= 8'sd1;
            conv_k20_r <= 8'sd0;
            conv_k21_r <= 8'sd1;
            conv_k22_r <= 8'sd2;
            conv_bias_r <= -32'sd128;
            conv_shift_r <= 5'd3;
            conv_relu_enable_r <= 1'b1;
            active_conv_k00_r <= -8'sd2;
            active_conv_k01_r <= -8'sd1;
            active_conv_k02_r <= 8'sd0;
            active_conv_k10_r <= -8'sd1;
            active_conv_k11_r <= 8'sd6;
            active_conv_k12_r <= 8'sd1;
            active_conv_k20_r <= 8'sd0;
            active_conv_k21_r <= 8'sd1;
            active_conv_k22_r <= 8'sd2;
            active_conv_bias_r <= -32'sd128;
            active_conv_shift_r <= 5'd3;
            active_conv_relu_enable_r <= 1'b1;
            armed_r <= 1'b0;
            done_latched_r <= 1'b0;
            packet_error_latched_r <= 1'b0;
            processing_cycles_latched_r <= '0;
        end else begin
            if (clear_done_pulse || start_pulse) begin
                done_latched_r <= 1'b0;
                packet_error_latched_r <= 1'b0;
            end

            if (start_pulse) begin
                armed_r <= 1'b1;
                active_mode_r <= mode_r;
                active_threshold_r <= threshold_r;
                active_conv_k00_r <= conv_k00_r;
                active_conv_k01_r <= conv_k01_r;
                active_conv_k02_r <= conv_k02_r;
                active_conv_k10_r <= conv_k10_r;
                active_conv_k11_r <= conv_k11_r;
                active_conv_k12_r <= conv_k12_r;
                active_conv_k20_r <= conv_k20_r;
                active_conv_k21_r <= conv_k21_r;
                active_conv_k22_r <= conv_k22_r;
                active_conv_bias_r <= conv_bias_r;
                active_conv_shift_r <= conv_shift_r;
                active_conv_relu_enable_r <= conv_relu_enable_r;
            end

            if (armed_r && (active_mode_r == MODE_THRESHOLD) && threshold_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= threshold_packet_error;
                processing_cycles_latched_r <= threshold_cycles;
            end else if (armed_r && (active_mode_r == MODE_SOBEL) && sobel_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= sobel_packet_error;
                processing_cycles_latched_r <= sobel_cycles;
            end else if (armed_r && (active_mode_r == MODE_CONV3X3) && conv_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= conv_packet_error;
                processing_cycles_latched_r <= conv_cycles;
            end

            if (reg_write_en && !stream_busy) begin
                unique case (reg_write_addr)
                    ADDR_THRESHOLD : begin
                        threshold_r <= reg_write_data[DATA_WIDTH-1:0];
                    end

                    ADDR_MODE : begin
                        unique case (reg_write_data[1:0])
                            MODE_THRESHOLD,
                            MODE_SOBEL,
                            MODE_CONV3X3 : begin
                                mode_r <= reg_write_data[1:0];
                            end

                            default : begin
                                mode_r <= MODE_THRESHOLD;
                            end
                        endcase
                    end

                    ADDR_CONV_K00 : begin
                        conv_k00_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K01 : begin
                        conv_k01_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K02 : begin
                        conv_k02_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K10 : begin
                        conv_k10_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K11 : begin
                        conv_k11_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K12 : begin
                        conv_k12_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K20 : begin
                        conv_k20_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K21 : begin
                        conv_k21_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K22 : begin
                        conv_k22_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_BIAS : begin
                        conv_bias_r <= reg_write_data;
                    end

                    ADDR_CONV_SHIFT : begin
                        conv_shift_r <= reg_write_data[4:0];
                    end

                    ADDR_CONV_RELU_EN : begin
                        conv_relu_enable_r <= reg_write_data[0];
                    end

                    default : begin
                    end
                endcase
            end
        end
    end

    // Mark protection fields as intentionally unused.
    logic unused_axi_prot;
    logic unused_core_status;
    assign unused_axi_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};
    assign unused_core_status = ^{threshold_busy, sobel_busy, conv_busy};

endmodule

