`timescale 1 ns / 100 ps

// Module: image_sobel_engine
// Description:
//   Full-image Sobel preprocessing engine with one input pixel read per clock.
//
// Timing intent:
//   - stream input pixels through two line buffers
//   - keep Sobel arithmetic inside sobel_core pipeline
//   - write border pixels as zero
//   - reset control/valid state, not line-buffer datapath storage

module image_sobel_engine #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int ADDR_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS),
    parameter int ROW_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT),
    parameter int COL_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH),
    parameter int COUNT_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS + 1),
    parameter int BORDER_PIXELS = (2 * IMAGE_WIDTH) + (2 * (IMAGE_HEIGHT - 2)),
    parameter int INTERIOR_PIXELS = (IMAGE_WIDTH - 2) * (IMAGE_HEIGHT - 2),
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         start,
    output logic                         busy,
    output logic                         done,
    output logic [CYCLE_COUNT_WIDTH-1:0] processing_cycles,

    output logic                         read_en,
    output logic [ADDR_WIDTH-1:0]        read_addr,
    input  logic [DATA_WIDTH-1:0]        read_data,

    output logic                         write_en,
    output logic [ADDR_WIDTH-1:0]        write_addr,
    output logic [DATA_WIDTH-1:0]        write_data
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_BORDER,
        STATE_READ,
        STATE_FLUSH
    } state_t;

    localparam int CENTER_ADDR_OFFSET = IMAGE_WIDTH + 1;
    localparam int BORDER_TOP_LAST_INDEX = IMAGE_WIDTH - 1;
    localparam int BORDER_BOTTOM_LAST_INDEX = (2 * IMAGE_WIDTH) - 1;
    localparam int BORDER_LEFT_LAST_INDEX = (2 * IMAGE_WIDTH) + (IMAGE_HEIGHT - 3);
    localparam int BORDER_BOTTOM_START_ADDR = (IMAGE_HEIGHT - 1) * IMAGE_WIDTH;
    localparam int BORDER_LEFT_START_ADDR = IMAGE_WIDTH;
    localparam int BORDER_RIGHT_START_ADDR = (2 * IMAGE_WIDTH) - 1;

    state_t state_r;

    logic [DATA_WIDTH-1:0] line_two_back_r [0:IMAGE_WIDTH-1];
    logic [DATA_WIDTH-1:0] line_one_back_r [0:IMAGE_WIDTH-1];
    logic [DATA_WIDTH-1:0] top_left2_r;
    logic [DATA_WIDTH-1:0] top_left1_r;
    logic [DATA_WIDTH-1:0] middle_left2_r;
    logic [DATA_WIDTH-1:0] middle_left1_r;
    logic [DATA_WIDTH-1:0] current_left2_r;
    logic [DATA_WIDTH-1:0] current_left1_r;

    logic [ADDR_WIDTH-1:0]        next_read_addr_r;
    logic [COUNT_WIDTH-1:0]       reads_remaining_r;
    logic [COUNT_WIDTH-1:0]       pixels_seen_r;
    logic [COUNT_WIDTH-1:0]       border_remaining_r;
    logic [COUNT_WIDTH-1:0]       interior_remaining_r;
    logic [COUNT_WIDTH-1:0]       border_index_r;
    logic [ADDR_WIDTH-1:0]        border_addr_r;
    logic [ROW_WIDTH-1:0]         pixel_row_r;
    logic [COL_WIDTH-1:0]         pixel_col_r;
    logic [CYCLE_COUNT_WIDTH-1:0] cycle_count_r;
    logic                         read_valid_r;

    logic                         start_accepted;
    logic                         issue_read;
    logic                         sobel_valid_in;
    logic                         sobel_valid_out;
    logic [DATA_WIDTH-1:0]        sobel_pixel_out;
    logic [ADDR_WIDTH-1:0]        center_addr;
    logic [ADDR_WIDTH-1:0]        center_addr_pipe_r [0:3];

    logic [DATA_WIDTH-1:0]        pixel_top_left;
    logic [DATA_WIDTH-1:0]        pixel_top;
    logic [DATA_WIDTH-1:0]        pixel_top_right;
    logic [DATA_WIDTH-1:0]        pixel_left;
    logic [DATA_WIDTH-1:0]        pixel_right;
    logic [DATA_WIDTH-1:0]        pixel_bottom_left;
    logic [DATA_WIDTH-1:0]        pixel_bottom;
    logic [DATA_WIDTH-1:0]        pixel_bottom_right;

    assign start_accepted = (state_r == STATE_IDLE) && start;
    assign issue_read = (state_r == STATE_READ) && (reads_remaining_r != '0);
    assign busy = (state_r != STATE_IDLE) || start_accepted;
    assign read_en = issue_read;
    assign read_addr = next_read_addr_r;

    assign sobel_valid_in = read_valid_r
                           && (pixel_row_r >= ROW_WIDTH'(2))
                           && (pixel_col_r >= COL_WIDTH'(2));

    assign write_en = (state_r == STATE_BORDER) || sobel_valid_out;
    assign write_addr = (state_r == STATE_BORDER) ? border_addr_r : center_addr_pipe_r[3];
    assign write_data = (state_r == STATE_BORDER) ? '0 : sobel_pixel_out;

    always_comb begin
        pixel_top_left = '0;
        pixel_top = '0;
        pixel_top_right = line_two_back_r[pixel_col_r];
        pixel_left = middle_left2_r;
        pixel_right = line_one_back_r[pixel_col_r];
        pixel_bottom_left = current_left2_r;
        pixel_bottom = current_left1_r;
        pixel_bottom_right = read_data;
        center_addr = '0;

        if ((pixel_row_r >= ROW_WIDTH'(2)) && (pixel_col_r >= COL_WIDTH'(2))) begin
            pixel_top_left = top_left2_r;
            pixel_top = top_left1_r;
            center_addr = ADDR_WIDTH'(pixels_seen_r - COUNT_WIDTH'(CENTER_ADDR_OFFSET));
        end
    end

    sobel_core #(
        .DATA_WIDTH(DATA_WIDTH)
    ) sobel_datapath (
        .clk(clk),
        .rst(rst),
        .valid_in(sobel_valid_in),
        .border_in(1'b0),
        .pixel_top_left(pixel_top_left),
        .pixel_top(pixel_top),
        .pixel_top_right(pixel_top_right),
        .pixel_left(pixel_left),
        .pixel_right(pixel_right),
        .pixel_bottom_left(pixel_bottom_left),
        .pixel_bottom(pixel_bottom),
        .pixel_bottom_right(pixel_bottom_right),
        .valid_out(sobel_valid_out),
        .pixel_out(sobel_pixel_out)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= STATE_IDLE;
            done <= 1'b0;
            processing_cycles <= '0;
            next_read_addr_r <= '0;
            reads_remaining_r <= '0;
            pixels_seen_r <= '0;
            border_remaining_r <= '0;
            interior_remaining_r <= '0;
            border_index_r <= '0;
            border_addr_r <= '0;
            pixel_row_r <= '0;
            pixel_col_r <= '0;
            cycle_count_r <= '0;
            read_valid_r <= 1'b0;
            top_left2_r <= '0;
            top_left1_r <= '0;
            middle_left2_r <= '0;
            middle_left1_r <= '0;
            current_left2_r <= '0;
            current_left1_r <= '0;
            center_addr_pipe_r[0] <= '0;
            center_addr_pipe_r[1] <= '0;
            center_addr_pipe_r[2] <= '0;
            center_addr_pipe_r[3] <= '0;
        end else begin
            done <= 1'b0;
            read_valid_r <= issue_read;

            center_addr_pipe_r[0] <= center_addr;
            center_addr_pipe_r[1] <= center_addr_pipe_r[0];
            center_addr_pipe_r[2] <= center_addr_pipe_r[1];
            center_addr_pipe_r[3] <= center_addr_pipe_r[2];

            if (read_valid_r) begin
                line_two_back_r[pixel_col_r] <= line_one_back_r[pixel_col_r];
                line_one_back_r[pixel_col_r] <= read_data;

                if (pixel_col_r == COL_WIDTH'(IMAGE_WIDTH - 1)) begin
                    pixel_col_r <= '0;
                    pixel_row_r <= pixel_row_r + ROW_WIDTH'(1);
                    top_left2_r <= '0;
                    top_left1_r <= '0;
                    middle_left2_r <= '0;
                    middle_left1_r <= '0;
                    current_left2_r <= '0;
                    current_left1_r <= '0;
                end else begin
                    pixel_col_r <= pixel_col_r + COL_WIDTH'(1);

                    if (pixel_col_r == '0) begin
                        top_left2_r <= '0;
                        top_left1_r <= line_two_back_r[pixel_col_r];
                        middle_left2_r <= '0;
                        middle_left1_r <= line_one_back_r[pixel_col_r];
                        current_left2_r <= '0;
                        current_left1_r <= read_data;
                    end else begin
                        top_left2_r <= top_left1_r;
                        top_left1_r <= line_two_back_r[pixel_col_r];
                        middle_left2_r <= middle_left1_r;
                        middle_left1_r <= line_one_back_r[pixel_col_r];
                        current_left2_r <= current_left1_r;
                        current_left1_r <= read_data;
                    end
                end

                pixels_seen_r <= pixels_seen_r + COUNT_WIDTH'(1);
            end

            unique case (state_r)
                STATE_IDLE : begin
                    cycle_count_r <= '0;
                    read_valid_r <= 1'b0;

                    if (start_accepted) begin
                        state_r <= STATE_BORDER;
                        border_remaining_r <= COUNT_WIDTH'(BORDER_PIXELS);
                        interior_remaining_r <= COUNT_WIDTH'(INTERIOR_PIXELS);
                        reads_remaining_r <= COUNT_WIDTH'(IMAGE_PIXELS);
                        next_read_addr_r <= '0;
                        border_index_r <= '0;
                        border_addr_r <= '0;
                        pixels_seen_r <= '0;
                        pixel_row_r <= '0;
                        pixel_col_r <= '0;
                        top_left2_r <= '0;
                        top_left1_r <= '0;
                        middle_left2_r <= '0;
                        middle_left1_r <= '0;
                        current_left2_r <= '0;
                        current_left1_r <= '0;
                        cycle_count_r <= CYCLE_COUNT_WIDTH'(1);
                    end
                end

                STATE_BORDER : begin
                    cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
                    border_remaining_r <= border_remaining_r - COUNT_WIDTH'(1);
                    border_index_r <= border_index_r + COUNT_WIDTH'(1);

                    if (border_index_r < COUNT_WIDTH'(BORDER_TOP_LAST_INDEX)) begin
                        border_addr_r <= border_addr_r + ADDR_WIDTH'(1);
                    end else if (border_index_r == COUNT_WIDTH'(BORDER_TOP_LAST_INDEX)) begin
                        border_addr_r <= ADDR_WIDTH'(BORDER_BOTTOM_START_ADDR);
                    end else if (border_index_r < COUNT_WIDTH'(BORDER_BOTTOM_LAST_INDEX)) begin
                        border_addr_r <= border_addr_r + ADDR_WIDTH'(1);
                    end else if (border_index_r == COUNT_WIDTH'(BORDER_BOTTOM_LAST_INDEX)) begin
                        border_addr_r <= ADDR_WIDTH'(BORDER_LEFT_START_ADDR);
                    end else if (border_index_r < COUNT_WIDTH'(BORDER_LEFT_LAST_INDEX)) begin
                        border_addr_r <= border_addr_r + ADDR_WIDTH'(IMAGE_WIDTH);
                    end else if (border_index_r == COUNT_WIDTH'(BORDER_LEFT_LAST_INDEX)) begin
                        border_addr_r <= ADDR_WIDTH'(BORDER_RIGHT_START_ADDR);
                    end else begin
                        border_addr_r <= border_addr_r + ADDR_WIDTH'(IMAGE_WIDTH);
                    end

                    if (border_remaining_r == COUNT_WIDTH'(1)) begin
                        state_r <= STATE_READ;
                    end
                end

                STATE_READ : begin
                    cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);

                    if (issue_read) begin
                        reads_remaining_r <= reads_remaining_r - COUNT_WIDTH'(1);
                        next_read_addr_r <= next_read_addr_r + ADDR_WIDTH'(1);
                    end

                    if (read_valid_r && (pixels_seen_r == COUNT_WIDTH'(IMAGE_PIXELS - 1))) begin
                        state_r <= STATE_FLUSH;
                    end

                    if (sobel_valid_out) begin
                        interior_remaining_r <= interior_remaining_r - COUNT_WIDTH'(1);
                    end
                end

                STATE_FLUSH : begin
                    cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);

                    if (sobel_valid_out) begin
                        interior_remaining_r <= interior_remaining_r - COUNT_WIDTH'(1);

                        if (interior_remaining_r == COUNT_WIDTH'(1)) begin
                            state_r <= STATE_IDLE;
                            done <= 1'b1;
                            processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
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
