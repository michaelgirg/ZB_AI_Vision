`timescale 1 ns / 100 ps

// Interface: preprocess_if
// Description:
//AXI4-Lite signal bundle used by the UVM verification environment.

interface preprocess_if #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
);

    logic                              clk;
    logic                              rstn;

    logic [ADDR_WIDTH-1:0]             s_axi_awaddr;
    logic [2:0]                        s_axi_awprot;
    logic                              s_axi_awvalid;
    logic                              s_axi_awready;

    logic [DATA_WIDTH-1:0]             s_axi_wdata;
    logic [(DATA_WIDTH/8)-1:0]         s_axi_wstrb;
    logic                              s_axi_wvalid;
    logic                              s_axi_wready;

    logic [1:0]                        s_axi_bresp;
    logic                              s_axi_bvalid;
    logic                              s_axi_bready;

    logic [ADDR_WIDTH-1:0]             s_axi_araddr;
    logic [2:0]                        s_axi_arprot;
    logic                              s_axi_arvalid;
    logic                              s_axi_arready;

    logic [DATA_WIDTH-1:0]             s_axi_rdata;
    logic [1:0]                        s_axi_rresp;
    logic                              s_axi_rvalid;
    logic                              s_axi_rready;

endinterface
