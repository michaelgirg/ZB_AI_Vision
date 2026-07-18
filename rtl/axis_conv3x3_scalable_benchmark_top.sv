`timescale 1 ns / 100 ps

module axis_conv3x3_scalable_benchmark_top #(
    parameter int PARALLEL_FILTERS = 4
) (
    input  logic         aclk,
    input  logic         aresetn,
    input  logic [31:0]  s_axis_tdata,
    input  logic [3:0]   s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic         s_axis_tlast,
    output logic [31:0]  m_axis_tdata,
    output logic [3:0]   m_axis_tkeep,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast,
    output logic         busy,
    output logic         done,
    output logic         packet_error
);

    localparam logic signed [7:0] DEFAULT_WEIGHTS [0:3][0:8] = '{
        '{29, 104, 127, -115, -76, 58, -78, -92, -114},
        '{13, -13, -116, -49, -79, 15, -127, -26, 11},
        '{48, -11, -127, -111, -76, -35, 39, 126, 94},
        '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
    };
    localparam logic signed [31:0] DEFAULT_BIAS [0:3] = '{11029, 17936, 257, -131};
    localparam logic [4:0] DEFAULT_SHIFT [0:3] = '{9, 7, 9, 9};

    wire signed [7:0] weights [0:PARALLEL_FILTERS-1][0:8];
    wire signed [31:0] biases [0:PARALLEL_FILTERS-1];
    wire [4:0] shifts [0:PARALLEL_FILTERS-1];
    wire relu_enables [0:PARALLEL_FILTERS-1];
    logic [31:0] processing_cycles;

    generate
        for (genvar filter_index = 0; filter_index < PARALLEL_FILTERS; filter_index++) begin : g_cfg
            assign biases[filter_index] = DEFAULT_BIAS[filter_index];
            assign shifts[filter_index] = DEFAULT_SHIFT[filter_index];
            assign relu_enables[filter_index] = 1'b1;
            for (genvar tap_index = 0; tap_index < 9; tap_index++) begin : g_tap
                assign weights[filter_index][tap_index] = DEFAULT_WEIGHTS[filter_index][tap_index];
            end
        end
    endgenerate

    axis_conv3x3_scalable_preprocess #(
        .PARALLEL_FILTERS(PARALLEL_FILTERS)
    ) DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .conv_weights(weights),
        .conv_bias(biases),
        .conv_shift(shifts),
        .conv_relu_enable(relu_enables),
        .clear_done(1'b0),
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
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );
endmodule
