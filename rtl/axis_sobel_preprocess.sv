`timescale 1 ns / 100 ps

// Module: axis_sobel_preprocess
// Description:
//AXI4-Stream packet wrapper that reuses the full-image Sobel preprocessing engine.

module axis_sobel_preprocess #(
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

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_RECEIVE,
        STATE_PROCESS,
        STATE_STREAM
    } state_t;

    localparam logic [KEEP_WIDTH-1:0] PIXEL_KEEP = '1;

    state_t state_r;

    (* ram_style = "block" *) logic [PIXEL_WIDTH-1:0] input_mem [0:IMAGE_PIXELS-1];
    (* ram_style = "block" *) logic [PIXEL_WIDTH-1:0] output_mem [0:IMAGE_PIXELS-1];

    logic [COUNT_WIDTH-1:0]       input_count_r;
    logic [COUNT_WIDTH-1:0]       stream_count_r;
    logic [CYCLE_COUNT_WIDTH-1:0] cycle_count_r;
    logic                         input_fire;
    logic                         output_fire;
    logic                         expected_input_last;
    logic                         early_input_last;
    logic                         final_input_beat;

    logic                         sobel_start_r;
    logic                         sobel_busy;
    logic                         sobel_done;
    logic [CYCLE_COUNT_WIDTH-1:0] sobel_cycles;
    logic                         sobel_read_en;
    logic [ADDR_WIDTH-1:0]        sobel_read_addr;
    logic [PIXEL_WIDTH-1:0]       sobel_read_data;
    logic                         sobel_write_en;
    logic [ADDR_WIDTH-1:0]        sobel_write_addr;
    logic [PIXEL_WIDTH-1:0]       sobel_write_data;

    assign s_axis_tready = (state_r == STATE_IDLE) || (state_r == STATE_RECEIVE);
    assign input_fire = s_axis_tvalid && s_axis_tready;
    assign output_fire = m_axis_tvalid && m_axis_tready;
    assign busy = (state_r != STATE_IDLE);

    assign expected_input_last = (input_count_r == COUNT_WIDTH'(IMAGE_PIXELS - 1));
    assign early_input_last = input_fire && s_axis_tlast && !expected_input_last;
    assign final_input_beat = input_fire && expected_input_last;

    image_sobel_engine #(
        .DATA_WIDTH(PIXEL_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) sobel_engine (
        .clk(aclk),
        .rst(!aresetn),
        .start(sobel_start_r),
        .busy(sobel_busy),
        .done(sobel_done),
        .processing_cycles(sobel_cycles),
        .read_en(sobel_read_en),
        .read_addr(sobel_read_addr),
        .read_data(sobel_read_data),
        .write_en(sobel_write_en),
        .write_addr(sobel_write_addr),
        .write_data(sobel_write_data)
    );

    always_ff @(posedge aclk) begin
        if (sobel_read_en) begin
            sobel_read_data <= input_mem[sobel_read_addr];
        end
    end

    always_ff @(posedge aclk) begin
        if (sobel_write_en) begin
            output_mem[sobel_write_addr] <= sobel_write_data;
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            state_r <= STATE_IDLE;
            done <= 1'b0;
            packet_error <= 1'b0;
            processing_cycles <= '0;
            input_count_r <= '0;
            stream_count_r <= '0;
            cycle_count_r <= '0;
            sobel_start_r <= 1'b0;
            m_axis_tdata <= '0;
            m_axis_tkeep <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            sobel_start_r <= 1'b0;

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
                            state_r <= STATE_PROCESS;
                            input_count_r <= '0;
                            sobel_start_r <= 1'b1;
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
                            state_r <= STATE_PROCESS;
                            input_count_r <= '0;
                            sobel_start_r <= 1'b1;
                        end else begin
                            input_count_r <= input_count_r + COUNT_WIDTH'(1);
                        end
                    end
                end

                STATE_PROCESS : begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast <= 1'b0;

                    if (sobel_done) begin
                        state_r <= STATE_STREAM;
                        stream_count_r <= '0;
                    end
                end

                STATE_STREAM : begin
                    if (output_fire && m_axis_tlast) begin
                        state_r <= STATE_IDLE;
                        stream_count_r <= '0;
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast <= 1'b0;
                        done <= 1'b1;
                        processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
                    end else if (!m_axis_tvalid || m_axis_tready) begin
                        m_axis_tdata <= {{(DATA_WIDTH-PIXEL_WIDTH){1'b0}},
                                         output_mem[stream_count_r[ADDR_WIDTH-1:0]]};
                        m_axis_tkeep <= PIXEL_KEEP;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast <= (stream_count_r == COUNT_WIDTH'(IMAGE_PIXELS - 1));
                        stream_count_r <= stream_count_r + COUNT_WIDTH'(1);
                    end
                end

                default : begin
                    state_r <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
