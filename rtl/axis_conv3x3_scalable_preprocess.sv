`timescale 1 ns / 100 ps

module axis_conv3x3_scalable_preprocess #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int PIXEL_WIDTH = 8,
    parameter int PARALLEL_FILTERS = 4,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int FIFO_DEPTH = 32,
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                              aclk,
    input  logic                              aresetn,
    input  wire signed [7:0]                  conv_weights [0:PARALLEL_FILTERS-1][0:8],
    input  wire signed [31:0]                 conv_bias [0:PARALLEL_FILTERS-1],
    input  wire [4:0]                         conv_shift [0:PARALLEL_FILTERS-1],
    input  wire                               conv_relu_enable [0:PARALLEL_FILTERS-1],
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

    localparam logic [KEEP_WIDTH-1:0] VALID_OUTPUT_KEEP =
        KEEP_WIDTH'((1 << PARALLEL_FILTERS) - 1);
    logic [KEEP_WIDTH-1:0] core_m_axis_tkeep;

    initial begin
        if (!((PARALLEL_FILTERS == 1) || (PARALLEL_FILTERS == 2) ||
              (PARALLEL_FILTERS == 4))) begin
            $fatal(1, "PARALLEL_FILTERS must be 1, 2, or 4");
        end
        if (DATA_WIDTH < PARALLEL_FILTERS * PIXEL_WIDTH) begin
            $fatal(1, "DATA_WIDTH cannot hold all packed filter outputs");
        end
    end

    axis_conv3x3_vector4_preprocess #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .FILTERS(PARALLEL_FILTERS),
        .TAPS(9),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .IMAGE_PIXELS(IMAGE_PIXELS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) scalable_core (
        .aclk(aclk),
        .aresetn(aresetn),
        .conv_weights(conv_weights),
        .conv_bias(conv_bias),
        .conv_shift(conv_shift),
        .conv_relu_enable(conv_relu_enable),
        .clear_done(clear_done),
        .busy(busy),
        .done(done),
        .packet_error(packet_error),
        .processing_cycles(processing_cycles),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(core_m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    assign m_axis_tkeep = core_m_axis_tkeep & VALID_OUTPUT_KEEP;
endmodule
