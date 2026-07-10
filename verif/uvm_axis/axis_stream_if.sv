`timescale 1 ns / 100 ps

// Interface: axis_stream_if
// Description:
//AXI4-Stream source and sink bundle for vector preprocessing verification.

interface axis_stream_if #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
);

    logic clk;
    logic rstn;

    logic [DATA_WIDTH-1:0] s_tdata;
    logic [KEEP_WIDTH-1:0] s_tkeep;
    logic s_tvalid;
    logic s_tready;
    logic s_tlast;

    logic [DATA_WIDTH-1:0] m_tdata;
    logic [KEEP_WIDTH-1:0] m_tkeep;
    logic m_tvalid;
    logic m_tready;
    logic m_tlast;

endinterface
