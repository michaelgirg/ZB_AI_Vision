`timescale 1 ns / 100 ps

// Module: axis_conv3x3_vector4_preprocess
// Description:
//Four-filter INT8 3x3 convolution with shared line buffers and packed outputs.

module axis_conv3x3_vector4_preprocess #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int PIXEL_WIDTH = 8,
    parameter int FILTERS = 4,
    parameter int TAPS = 9,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int COUNT_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS + 1),
    parameter int ROW_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT),
    parameter int COL_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH),
    parameter int FIFO_DEPTH = 32,
    parameter int FIFO_PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH),
    parameter int FIFO_COUNT_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1),
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                              aclk,
    input  logic                              aresetn,

    input  wire signed [7:0]                  conv_weights [0:FILTERS-1][0:TAPS-1],
    input  wire signed [31:0]                 conv_bias [0:FILTERS-1],
    input  wire [4:0]                         conv_shift [0:FILTERS-1],
    input  wire                               conv_relu_enable [0:FILTERS-1],

    input  logic                              clear_done,
    output logic                              busy,
    output logic                              done,
    output logic                              packet_error,
    output logic [CYCLE_COUNT_WIDTH-1:0]      processing_cycles,

    input  logic [DATA_WIDTH-1:0]             s_axis_tdata,
    input  logic [KEEP_WIDTH-1:0]             s_axis_tkeep,
    input  logic                              s_axis_tvalid,
    output logic                              s_axis_tready,
    input  logic                              s_axis_tlast,

    output logic [DATA_WIDTH-1:0]             m_axis_tdata,
    output logic [KEEP_WIDTH-1:0]             m_axis_tkeep,
    output logic                              m_axis_tvalid,
    input  logic                              m_axis_tready,
    output logic                              m_axis_tlast
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_RUN,
        STATE_DRAIN,
        STATE_FLUSH_BOTTOM
    } state_t;

    localparam logic [KEEP_WIDTH-1:0] PIXEL_KEEP = '1;
    localparam int FIFO_HEADROOM = 8;

    state_t state_r;
    logic [PIXEL_WIDTH-1:0] line_mem [0:2][0:IMAGE_WIDTH-1];
    logic [DATA_WIDTH:0] fifo_mem [0:FIFO_DEPTH-1];

    logic [COUNT_WIDTH-1:0] input_count_r;
    logic [ROW_WIDTH-1:0] input_row_r;
    logic [COL_WIDTH-1:0] input_col_r;
    logic [1:0] row_mod_r;
    logic [COL_WIDTH-1:0] bottom_col_r;
    logic [CYCLE_COUNT_WIDTH-1:0] cycle_count_r;
    logic bottom_flushed_r;

    logic [FIFO_PTR_WIDTH-1:0] fifo_rd_ptr_r;
    logic [FIFO_PTR_WIDTH-1:0] fifo_wr_ptr_r;
    logic [FIFO_COUNT_WIDTH-1:0] fifo_count_r;

    logic p0_valid_r;
    logic p0_zero_r;
    logic p0_emit_right_r;
    logic [PIXEL_WIDTH-1:0] p0_pixel_r [0:TAPS-1];

    logic p1_valid_r;
    logic p1_zero_r;
    logic p1_emit_right_r;
    (* use_dsp = "yes" *) logic signed [31:0] p1_product_r [0:FILTERS-1][0:TAPS-1];

    logic p2_valid_r;
    logic p2_zero_r;
    logic p2_emit_right_r;
    logic signed [31:0] p2_sum_r [0:FILTERS-1][0:2];

    logic p3_valid_r;
    logic p3_zero_r;
    logic p3_emit_right_r;
    logic signed [31:0] p3_acc_r [0:FILTERS-1];

    logic p4_valid_r;
    logic p4_emit_right_r;
    logic [PIXEL_WIDTH-1:0] p4_pixel_r [0:FILTERS-1];
    logic [DATA_WIDTH-1:0] packed_features;

    logic input_fire;
    logic output_fire;
    logic expected_input_last;
    logic final_input_beat;
    logic input_slot_ready;
    logic pipeline_empty;
    logic [1:0] prev_row_mod;
    logic [1:0] prev2_row_mod;

    assign prev_row_mod = (row_mod_r == 2'd0) ? 2'd2 : (row_mod_r - 2'd1);
    assign prev2_row_mod = (row_mod_r == 2'd0) ? 2'd1 :
                           (row_mod_r == 2'd1) ? 2'd2 : 2'd0;
    assign input_slot_ready =
        (fifo_count_r <= FIFO_COUNT_WIDTH'(FIFO_DEPTH - FIFO_HEADROOM));
    assign s_axis_tready = ((state_r == STATE_IDLE) || (state_r == STATE_RUN)) && input_slot_ready;
    assign input_fire = s_axis_tvalid && s_axis_tready;
    assign output_fire = m_axis_tvalid && m_axis_tready;
    assign expected_input_last = (input_count_r == COUNT_WIDTH'(IMAGE_PIXELS - 1));
    assign final_input_beat = input_fire && expected_input_last;
    assign pipeline_empty =
        !p0_valid_r && !p1_valid_r && !p2_valid_r && !p3_valid_r && !p4_valid_r;
    assign busy = (state_r != STATE_IDLE);

    always_comb begin
        packed_features = '0;
        for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
            packed_features[filter_index*PIXEL_WIDTH +: PIXEL_WIDTH] = p4_pixel_r[filter_index];
        end
    end

    function automatic logic [FIFO_PTR_WIDTH-1:0] incr_fifo_ptr(
        input logic [FIFO_PTR_WIDTH-1:0] ptr
    );
        if (ptr == FIFO_PTR_WIDTH'(FIFO_DEPTH - 1)) begin
            return '0;
        end
        return ptr + FIFO_PTR_WIDTH'(1);
    endfunction

    function automatic logic signed [31:0] multiply_pixel_coeff(
        input logic [PIXEL_WIDTH-1:0] pixel,
        input logic signed [7:0] coeff
    );
        logic signed [8:0] pixel_signed;
        pixel_signed = $signed({1'b0, pixel});
        return pixel_signed * coeff;
    endfunction

    function automatic logic [PIXEL_WIDTH-1:0] finalize_pixel(
        input logic zero_event,
        input logic signed [31:0] acc,
        input logic [4:0] shift,
        input logic relu_enable
    );
        logic signed [31:0] shifted;
        if (zero_event) begin
            return '0;
        end
        shifted = (shift == 0) ? acc : (acc >>> shift);
        if (relu_enable && (shifted < 0)) begin
            return '0;
        end
        if (shifted < 0) begin
            return '0;
        end
        if (shifted > 32'sd255) begin
            return '1;
        end
        return shifted[PIXEL_WIDTH-1:0];
    endfunction

    task automatic push_fifo_entry(
        inout logic [FIFO_PTR_WIDTH-1:0] wr_ptr,
        inout logic [FIFO_COUNT_WIDTH-1:0] count,
        input logic [DATA_WIDTH-1:0] data,
        input logic last
    );
        fifo_mem[wr_ptr] <= {last, data};
        wr_ptr = incr_fifo_ptr(wr_ptr);
        count = count + FIFO_COUNT_WIDTH'(1);
    endtask

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_r <= STATE_IDLE;
            done <= 1'b0;
            packet_error <= 1'b0;
            processing_cycles <= '0;
            input_count_r <= '0;
            input_row_r <= '0;
            input_col_r <= '0;
            row_mod_r <= '0;
            bottom_col_r <= '0;
            cycle_count_r <= '0;
            bottom_flushed_r <= 1'b0;
            fifo_rd_ptr_r <= '0;
            fifo_wr_ptr_r <= '0;
            fifo_count_r <= '0;
            p0_valid_r <= 1'b0;
            p0_zero_r <= 1'b0;
            p0_emit_right_r <= 1'b0;
            p1_valid_r <= 1'b0;
            p1_zero_r <= 1'b0;
            p1_emit_right_r <= 1'b0;
            p2_valid_r <= 1'b0;
            p2_zero_r <= 1'b0;
            p2_emit_right_r <= 1'b0;
            p3_valid_r <= 1'b0;
            p3_zero_r <= 1'b0;
            p3_emit_right_r <= 1'b0;
            p4_valid_r <= 1'b0;
            p4_emit_right_r <= 1'b0;
            m_axis_tdata <= '0;
            m_axis_tkeep <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            for (int tap_index = 0; tap_index < TAPS; tap_index++) begin
                p0_pixel_r[tap_index] <= '0;
            end
            for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
                p3_acc_r[filter_index] <= '0;
                p4_pixel_r[filter_index] <= '0;
                for (int tap_index = 0; tap_index < TAPS; tap_index++) begin
                    p1_product_r[filter_index][tap_index] <= '0;
                end
                for (int row_index = 0; row_index < 3; row_index++) begin
                    p2_sum_r[filter_index][row_index] <= '0;
                end
            end
        end else begin
            logic [FIFO_PTR_WIDTH-1:0] next_wr_ptr;
            logic [FIFO_PTR_WIDTH-1:0] next_rd_ptr;
            logic [FIFO_COUNT_WIDTH-1:0] next_count;

            next_wr_ptr = fifo_wr_ptr_r;
            next_rd_ptr = fifo_rd_ptr_r;
            next_count = fifo_count_r;

            if (clear_done) begin
                done <= 1'b0;
                packet_error <= 1'b0;
            end
            if (state_r != STATE_IDLE) begin
                cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
            end

            p4_valid_r <= p3_valid_r;
            p4_emit_right_r <= p3_emit_right_r;
            for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
                p4_pixel_r[filter_index] <= finalize_pixel(
                    p3_zero_r,
                    p3_acc_r[filter_index],
                    conv_shift[filter_index],
                    conv_relu_enable[filter_index]
                );
            end

            p3_valid_r <= p2_valid_r;
            p3_zero_r <= p2_zero_r;
            p3_emit_right_r <= p2_emit_right_r;
            for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
                p3_acc_r[filter_index] <=
                    p2_sum_r[filter_index][0] +
                    p2_sum_r[filter_index][1] +
                    p2_sum_r[filter_index][2] +
                    conv_bias[filter_index];
            end

            p2_valid_r <= p1_valid_r;
            p2_zero_r <= p1_zero_r;
            p2_emit_right_r <= p1_emit_right_r;
            for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
                p2_sum_r[filter_index][0] <=
                    p1_product_r[filter_index][0] +
                    p1_product_r[filter_index][1] +
                    p1_product_r[filter_index][2];
                p2_sum_r[filter_index][1] <=
                    p1_product_r[filter_index][3] +
                    p1_product_r[filter_index][4] +
                    p1_product_r[filter_index][5];
                p2_sum_r[filter_index][2] <=
                    p1_product_r[filter_index][6] +
                    p1_product_r[filter_index][7] +
                    p1_product_r[filter_index][8];
            end

            p1_valid_r <= p0_valid_r;
            p1_zero_r <= p0_zero_r;
            p1_emit_right_r <= p0_emit_right_r;
            for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
                for (int tap_index = 0; tap_index < TAPS; tap_index++) begin
                    p1_product_r[filter_index][tap_index] <= multiply_pixel_coeff(
                        p0_pixel_r[tap_index],
                        conv_weights[filter_index][tap_index]
                    );
                end
            end

            p0_valid_r <= 1'b0;
            p0_zero_r <= 1'b0;
            p0_emit_right_r <= 1'b0;

            if (p4_valid_r) begin
                push_fifo_entry(next_wr_ptr, next_count, packed_features, 1'b0);
                if (p4_emit_right_r) begin
                    push_fifo_entry(next_wr_ptr, next_count, '0, 1'b0);
                end
            end

            unique case (state_r)
                STATE_IDLE : begin
                    input_count_r <= '0;
                    input_row_r <= '0;
                    input_col_r <= '0;
                    row_mod_r <= '0;
                    bottom_col_r <= '0;
                    cycle_count_r <= '0;
                    bottom_flushed_r <= 1'b0;
                    fifo_rd_ptr_r <= '0;
                    fifo_wr_ptr_r <= '0;
                    fifo_count_r <= '0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;

                    if (input_fire) begin
                        done <= 1'b0;
                        cycle_count_r <= CYCLE_COUNT_WIDTH'(1);
                        state_r <= STATE_RUN;
                        line_mem[row_mod_r][input_col_r] <= s_axis_tdata[PIXEL_WIDTH-1:0];
                        p0_valid_r <= 1'b1;
                        p0_zero_r <= 1'b1;
                        if ((s_axis_tkeep != PIXEL_KEEP) || (s_axis_tlast != expected_input_last)) begin
                            packet_error <= 1'b1;
                        end
                        input_count_r <= input_count_r + COUNT_WIDTH'(1);
                        input_col_r <= input_col_r + COL_WIDTH'(1);
                    end
                end

                STATE_RUN : begin
                    if (input_fire) begin
                        line_mem[row_mod_r][input_col_r] <= s_axis_tdata[PIXEL_WIDTH-1:0];
                        if ((s_axis_tkeep != PIXEL_KEEP) || (s_axis_tlast != expected_input_last)) begin
                            packet_error <= 1'b1;
                        end

                        if (input_row_r == 0) begin
                            p0_valid_r <= 1'b1;
                            p0_zero_r <= 1'b1;
                        end else if ((input_row_r >= 2) && (input_col_r == 0)) begin
                            p0_valid_r <= 1'b1;
                            p0_zero_r <= 1'b1;
                        end else if ((input_row_r >= 2) && (input_col_r >= 2)) begin
                            p0_valid_r <= 1'b1;
                            p0_zero_r <= 1'b0;
                            p0_emit_right_r <= (input_col_r == IMAGE_WIDTH - 1);
                            p0_pixel_r[0] <= line_mem[prev2_row_mod][input_col_r - 2];
                            p0_pixel_r[1] <= line_mem[prev2_row_mod][input_col_r - 1];
                            p0_pixel_r[2] <= line_mem[prev2_row_mod][input_col_r];
                            p0_pixel_r[3] <= line_mem[prev_row_mod][input_col_r - 2];
                            p0_pixel_r[4] <= line_mem[prev_row_mod][input_col_r - 1];
                            p0_pixel_r[5] <= line_mem[prev_row_mod][input_col_r];
                            p0_pixel_r[6] <= line_mem[row_mod_r][input_col_r - 2];
                            p0_pixel_r[7] <= line_mem[row_mod_r][input_col_r - 1];
                            p0_pixel_r[8] <= s_axis_tdata[PIXEL_WIDTH-1:0];
                        end

                        if (final_input_beat) begin
                            state_r <= STATE_DRAIN;
                            input_count_r <= '0;
                        end else begin
                            input_count_r <= input_count_r + COUNT_WIDTH'(1);
                            if (input_col_r == IMAGE_WIDTH - 1) begin
                                input_col_r <= '0;
                                input_row_r <= input_row_r + ROW_WIDTH'(1);
                                row_mod_r <= (row_mod_r == 2) ? 0 : (row_mod_r + 1);
                            end else begin
                                input_col_r <= input_col_r + COL_WIDTH'(1);
                            end
                        end
                    end
                end

                STATE_DRAIN : begin
                    if (pipeline_empty && !bottom_flushed_r) begin
                        state_r <= STATE_FLUSH_BOTTOM;
                        bottom_col_r <= '0;
                    end
                end

                STATE_FLUSH_BOTTOM : begin
                    if (next_count <= FIFO_COUNT_WIDTH'(FIFO_DEPTH - 2)) begin
                        push_fifo_entry(
                            next_wr_ptr,
                            next_count,
                            '0,
                            (bottom_col_r == IMAGE_WIDTH - 1)
                        );
                        if (bottom_col_r == IMAGE_WIDTH - 1) begin
                            state_r <= STATE_DRAIN;
                            bottom_flushed_r <= 1'b1;
                            bottom_col_r <= '0;
                        end else begin
                            bottom_col_r <= bottom_col_r + COL_WIDTH'(1);
                        end
                    end
                end

                default : state_r <= STATE_IDLE;
            endcase

            if (output_fire && m_axis_tlast) begin
                state_r <= STATE_IDLE;
                done <= 1'b1;
                processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end else if (output_fire) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end

            if ((!m_axis_tvalid || output_fire) && (fifo_count_r != 0)) begin
                m_axis_tdata <= fifo_mem[next_rd_ptr][DATA_WIDTH-1:0];
                m_axis_tkeep <= PIXEL_KEEP;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= fifo_mem[next_rd_ptr][DATA_WIDTH];
                next_rd_ptr = incr_fifo_ptr(next_rd_ptr);
                next_count = next_count - FIFO_COUNT_WIDTH'(1);
            end

            fifo_wr_ptr_r <= next_wr_ptr;
            fifo_rd_ptr_r <= next_rd_ptr;
            fifo_count_r <= next_count;
        end
    end

endmodule
