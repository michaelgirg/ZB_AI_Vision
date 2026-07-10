`timescale 1 ns / 100 ps

// Module: axis_conv3x3_preprocess
// Description:
//AXI4-Stream learned INT8 3x3 convolution wrapper with fixed-point scaling.

module axis_conv3x3_preprocess #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int PIXEL_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int ADDR_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS),
    parameter int COUNT_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS + 1),
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                         aclk,
    input  logic                         aresetn,

    input  logic signed [7:0]            conv_k00,
    input  logic signed [7:0]            conv_k01,
    input  logic signed [7:0]            conv_k02,
    input  logic signed [7:0]            conv_k10,
    input  logic signed [7:0]            conv_k11,
    input  logic signed [7:0]            conv_k12,
    input  logic signed [7:0]            conv_k20,
    input  logic signed [7:0]            conv_k21,
    input  logic signed [7:0]            conv_k22,
    input  logic signed [31:0]           conv_bias,
    input  logic [4:0]                   conv_shift,
    input  logic                         conv_relu_enable,

    input  logic                         clear_done,
    output logic                         busy,
    output logic                         done,
    output logic                         packet_error,
    output logic [CYCLE_COUNT_WIDTH-1:0] processing_cycles,

    input  logic [DATA_WIDTH-1:0]        s_axis_tdata,
    input  logic [KEEP_WIDTH-1:0]        s_axis_tkeep,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,

    output logic [DATA_WIDTH-1:0]        m_axis_tdata,
    output logic [KEEP_WIDTH-1:0]        m_axis_tkeep,
    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,
    output logic                         m_axis_tlast
);

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_RECEIVE,
        STATE_PREPARE_PIXEL,
        STATE_READ_ACCUM,
        STATE_MULT_TAP,
        STATE_SCALE,
        STATE_RELU,
        STATE_CLAMP,
        STATE_OUTPUT
    } state_t;

    localparam logic [KEEP_WIDTH-1:0] PIXEL_KEEP = '1;
    localparam int ROW_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);
    localparam int COL_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);

    state_t state_r;

    (* ram_style = "block" *) logic [PIXEL_WIDTH-1:0] input_mem [0:IMAGE_PIXELS-1];

    logic [COUNT_WIDTH-1:0]       input_count_r;
    logic [COUNT_WIDTH-1:0]       stream_count_r;
    logic [ROW_WIDTH-1:0]         stream_row_r;
    logic [COL_WIDTH-1:0]         stream_col_r;
    logic [CYCLE_COUNT_WIDTH-1:0] cycle_count_r;
    logic [ADDR_WIDTH-1:0]        read_addr_r;
    logic [PIXEL_WIDTH-1:0]       read_pixel_r;
    logic [3:0]                   tap_index_r;
    logic                         product_valid_r;
    logic signed [31:0]           product_r;
    logic signed [31:0]           acc_r;
    logic signed [31:0]           shifted_r;
    logic signed [31:0]           relu_r;
    logic [PIXEL_WIDTH-1:0]       output_pixel_r;
    logic                         input_fire;
    logic                         output_fire;
    logic                         expected_input_last;
    logic                         early_input_last;
    logic                         final_input_beat;
    logic                         current_border;
    logic                         current_last_pixel;

    assign s_axis_tready = (state_r == STATE_IDLE) || (state_r == STATE_RECEIVE);
    assign input_fire = s_axis_tvalid && s_axis_tready;
    assign output_fire = m_axis_tvalid && m_axis_tready;
    assign busy = (state_r != STATE_IDLE);

    assign expected_input_last = (input_count_r == COUNT_WIDTH'(IMAGE_PIXELS - 1));
    assign early_input_last = input_fire && s_axis_tlast && !expected_input_last;
    assign final_input_beat = input_fire && expected_input_last;
    assign current_last_pixel = (stream_count_r == COUNT_WIDTH'(IMAGE_PIXELS - 1));
    assign current_border =
        (stream_row_r == ROW_WIDTH'(0)) ||
        (stream_row_r == ROW_WIDTH'(IMAGE_HEIGHT - 1)) ||
        (stream_col_r == COL_WIDTH'(0)) ||
        (stream_col_r == COL_WIDTH'(IMAGE_WIDTH - 1));

    function automatic logic [ADDR_WIDTH-1:0] tap_address(
        input logic [COUNT_WIDTH-1:0] pixel_index,
        input logic [3:0] tap_index
    );
        logic [COUNT_WIDTH-1:0] addr;
        begin
            unique case (tap_index)
                4'd0 : addr = pixel_index - COUNT_WIDTH'(IMAGE_WIDTH + 1);
                4'd1 : addr = pixel_index - COUNT_WIDTH'(IMAGE_WIDTH);
                4'd2 : addr = pixel_index - COUNT_WIDTH'(IMAGE_WIDTH - 1);
                4'd3 : addr = pixel_index - COUNT_WIDTH'(1);
                4'd4 : addr = pixel_index;
                4'd5 : addr = pixel_index + COUNT_WIDTH'(1);
                4'd6 : addr = pixel_index + COUNT_WIDTH'(IMAGE_WIDTH - 1);
                4'd7 : addr = pixel_index + COUNT_WIDTH'(IMAGE_WIDTH);
                default : addr = pixel_index + COUNT_WIDTH'(IMAGE_WIDTH + 1);
            endcase

            return addr[ADDR_WIDTH-1:0];
        end
    endfunction

    function automatic logic signed [7:0] tap_coeff(
        input logic [3:0] tap_index
    );
        begin
            unique case (tap_index)
                4'd0 : return conv_k00;
                4'd1 : return conv_k01;
                4'd2 : return conv_k02;
                4'd3 : return conv_k10;
                4'd4 : return conv_k11;
                4'd5 : return conv_k12;
                4'd6 : return conv_k20;
                4'd7 : return conv_k21;
                default : return conv_k22;
            endcase
        end
    endfunction

    function automatic logic signed [31:0] multiply_pixel_coeff(
        input logic [PIXEL_WIDTH-1:0] pixel,
        input logic signed [7:0] coeff
    );
        logic signed [8:0] pixel_signed;
        begin
            pixel_signed = $signed({1'b0, pixel});
            return pixel_signed * coeff;
        end
    endfunction

    function automatic logic [PIXEL_WIDTH-1:0] clamp_to_u8(
        input logic signed [31:0] value
    );
        begin
            if (value < 32'sd0) begin
                return '0;
            end

            if (value > 32'sd255) begin
                return '1;
            end

            return value[PIXEL_WIDTH-1:0];
        end
    endfunction

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_r <= STATE_IDLE;
            done <= 1'b0;
            packet_error <= 1'b0;
            processing_cycles <= '0;
            input_count_r <= '0;
            stream_count_r <= '0;
            stream_row_r <= '0;
            stream_col_r <= '0;
            cycle_count_r <= '0;
            read_addr_r <= '0;
            read_pixel_r <= '0;
            tap_index_r <= '0;
            product_valid_r <= 1'b0;
            product_r <= '0;
            acc_r <= '0;
            shifted_r <= '0;
            relu_r <= '0;
            output_pixel_r <= '0;
            m_axis_tdata <= '0;
            m_axis_tkeep <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            if (clear_done) begin
                done <= 1'b0;
                packet_error <= 1'b0;
            end

            if (state_r != STATE_IDLE) begin
                cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
            end

            unique case (state_r)
                STATE_IDLE : begin
                    input_count_r <= '0;
                    stream_count_r <= '0;
                    stream_row_r <= '0;
                    stream_col_r <= '0;
                    cycle_count_r <= '0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;

                    if (input_fire) begin
                        done <= 1'b0;
                        cycle_count_r <= CYCLE_COUNT_WIDTH'(1);
                        input_mem[input_count_r[ADDR_WIDTH-1:0]] <= s_axis_tdata[PIXEL_WIDTH-1:0];

                        if ((s_axis_tkeep != PIXEL_KEEP) || (s_axis_tlast != expected_input_last)) begin
                            packet_error <= 1'b1;
                        end

                        if (early_input_last) begin
                            done <= 1'b1;
                            processing_cycles <= CYCLE_COUNT_WIDTH'(1);
                        end else if (final_input_beat) begin
                            state_r <= STATE_PREPARE_PIXEL;
                            input_count_r <= '0;
                        end else begin
                            state_r <= STATE_RECEIVE;
                            input_count_r <= input_count_r + COUNT_WIDTH'(1);
                        end
                    end
                end

                STATE_RECEIVE : begin
                    if (input_fire) begin
                        input_mem[input_count_r[ADDR_WIDTH-1:0]] <= s_axis_tdata[PIXEL_WIDTH-1:0];

                        if ((s_axis_tkeep != PIXEL_KEEP) || (s_axis_tlast != expected_input_last)) begin
                            packet_error <= 1'b1;
                        end

                        if (early_input_last) begin
                            state_r <= STATE_IDLE;
                            input_count_r <= '0;
                            done <= 1'b1;
                            processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
                        end else if (final_input_beat) begin
                            state_r <= STATE_PREPARE_PIXEL;
                            input_count_r <= '0;
                            stream_count_r <= '0;
                            stream_row_r <= '0;
                            stream_col_r <= '0;
                        end else begin
                            input_count_r <= input_count_r + COUNT_WIDTH'(1);
                        end
                    end
                end

                STATE_PREPARE_PIXEL : begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;

                    if (current_border) begin
                        output_pixel_r <= '0;
                        state_r <= STATE_CLAMP;
                    end else begin
                        tap_index_r <= '0;
                        product_valid_r <= 1'b0;
                        acc_r <= conv_bias;
                        read_addr_r <= tap_address(stream_count_r, 4'd0);
                        state_r <= STATE_READ_ACCUM;
                    end
                end

                STATE_READ_ACCUM : begin
                    read_pixel_r <= input_mem[read_addr_r];

                    if (product_valid_r) begin
                        acc_r <= acc_r + product_r;

                        if (tap_index_r == 4'd9) begin
                            product_valid_r <= 1'b0;
                            state_r <= STATE_SCALE;
                        end else begin
                            state_r <= STATE_MULT_TAP;
                        end
                    end else begin
                        state_r <= STATE_MULT_TAP;
                    end
                end

                STATE_MULT_TAP : begin
                    product_r <= multiply_pixel_coeff(read_pixel_r, tap_coeff(tap_index_r));
                    product_valid_r <= 1'b1;

                    if (tap_index_r == 4'd8) begin
                        tap_index_r <= 4'd9;
                    end else begin
                        tap_index_r <= tap_index_r + 4'd1;
                        read_addr_r <= tap_address(stream_count_r, tap_index_r + 4'd1);
                    end

                    state_r <= STATE_READ_ACCUM;
                end

                STATE_SCALE : begin
                    if (conv_shift == 5'd0) begin
                        shifted_r <= acc_r;
                    end else begin
                        shifted_r <= acc_r >>> conv_shift;
                    end

                    state_r <= STATE_RELU;
                end

                STATE_RELU : begin
                    if (conv_relu_enable && (shifted_r < 32'sd0)) begin
                        relu_r <= 32'sd0;
                    end else begin
                        relu_r <= shifted_r;
                    end

                    state_r <= STATE_CLAMP;
                end

                STATE_CLAMP : begin
                    if (!current_border) begin
                        output_pixel_r <= clamp_to_u8(relu_r);
                    end

                    m_axis_tdata <= {{(DATA_WIDTH-PIXEL_WIDTH){1'b0}},
                                     (current_border ? {PIXEL_WIDTH{1'b0}} : clamp_to_u8(relu_r))};
                    m_axis_tkeep <= PIXEL_KEEP;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= current_last_pixel;
                    state_r <= STATE_OUTPUT;
                end

                STATE_OUTPUT : begin
                    if (output_fire) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;

                        if (current_last_pixel) begin
                            state_r <= STATE_IDLE;
                            stream_count_r <= '0;
                            stream_row_r <= '0;
                            stream_col_r <= '0;
                            done <= 1'b1;
                            processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
                        end else begin
                            state_r <= STATE_PREPARE_PIXEL;
                            stream_count_r <= stream_count_r + COUNT_WIDTH'(1);

                            if (stream_col_r == COL_WIDTH'(IMAGE_WIDTH - 1)) begin
                                stream_col_r <= '0;
                                stream_row_r <= stream_row_r + ROW_WIDTH'(1);
                            end else begin
                                stream_col_r <= stream_col_r + COL_WIDTH'(1);
                            end
                        end
                    end
                end

                default : begin
                    state_r <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
