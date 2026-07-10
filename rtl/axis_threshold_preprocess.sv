`timescale 1 ns / 100 ps

// Module: axis_threshold_preprocess
// Description:
//AXI4-Stream threshold preprocessing core for one-pixel-per-beat image packets.

module axis_threshold_preprocess #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int PIXEL_WIDTH = 8,
    parameter int IMAGE_PIXELS = 784,
    parameter int COUNT_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS + 1),
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                         aclk,
    input  logic                         aresetn,

    input  logic [PIXEL_WIDTH-1:0]       threshold,
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

    localparam logic [KEEP_WIDTH-1:0] PIXEL_KEEP = '1;

    logic [COUNT_WIDTH-1:0]       input_count_r;
    logic [CYCLE_COUNT_WIDTH-1:0] cycle_count_r;
    logic                         input_fire;
    logic                         output_fire;
    logic                         expected_input_last;
    logic [PIXEL_WIDTH-1:0]       threshold_pixel;

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;
    assign input_fire = s_axis_tvalid && s_axis_tready;
    assign output_fire = m_axis_tvalid && m_axis_tready;
    assign expected_input_last = (input_count_r == COUNT_WIDTH'(IMAGE_PIXELS - 1));
    assign threshold_pixel = (s_axis_tdata[PIXEL_WIDTH-1:0] >= threshold) ? '1 : '0;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            busy <= 1'b0;
            done <= 1'b0;
            packet_error <= 1'b0;
            processing_cycles <= '0;
            input_count_r <= '0;
            cycle_count_r <= '0;
            m_axis_tdata <= '0;
            m_axis_tkeep <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            if (clear_done) begin
                done <= 1'b0;
                packet_error <= 1'b0;
            end

            if (busy) begin
                cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
            end

            if (output_fire && m_axis_tlast) begin
                busy <= 1'b0;
                done <= 1'b1;
                processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
            end

            if (output_fire && !input_fire) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end

            if (input_fire) begin
                if (!busy) begin
                    busy <= 1'b1;
                    done <= 1'b0;
                    cycle_count_r <= CYCLE_COUNT_WIDTH'(1);
                end

                if ((s_axis_tkeep != PIXEL_KEEP) || (s_axis_tlast != expected_input_last)) begin
                    packet_error <= 1'b1;
                end

                if (s_axis_tlast) begin
                    input_count_r <= '0;
                end else begin
                    input_count_r <= input_count_r + COUNT_WIDTH'(1);
                end

                m_axis_tdata <= {{(DATA_WIDTH-PIXEL_WIDTH){1'b0}}, threshold_pixel};
                m_axis_tkeep <= PIXEL_KEEP;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= s_axis_tlast;
            end
        end
    end

endmodule
