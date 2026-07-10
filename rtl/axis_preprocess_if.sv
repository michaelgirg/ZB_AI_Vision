`timescale 1 ns / 100 ps

// Interface: axis_preprocess_if
// Description:
//AXI4-Stream signal contract for the future DMA preprocessing datapath.

interface axis_preprocess_if #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8
) (
    input logic aclk,
    input logic aresetn
);

    logic [DATA_WIDTH-1:0]      tdata;
    logic [KEEP_WIDTH-1:0]      tkeep;
    logic                       tvalid;
    logic                       tready;
    logic                       tlast;

    modport source (
        input  aclk,
        input  aresetn,
        output tdata,
        output tkeep,
        output tvalid,
        input  tready,
        output tlast
    );

    modport sink (
        input  aclk,
        input  aresetn,
        input  tdata,
        input  tkeep,
        input  tvalid,
        output tready,
        input  tlast
    );

    modport monitor (
        input aclk,
        input aresetn,
        input tdata,
        input tkeep,
        input tvalid,
        input tready,
        input tlast
    );

endinterface

