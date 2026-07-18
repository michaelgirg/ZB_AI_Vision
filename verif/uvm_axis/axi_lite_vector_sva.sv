`timescale 1 ns / 100 ps

module axi_lite_vector_sva #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rstn,
    input logic [ADDR_WIDTH-1:0] awaddr,
    input logic awvalid,
    input logic awready,
    input logic [DATA_WIDTH-1:0] wdata,
    input logic [(DATA_WIDTH/8)-1:0] wstrb,
    input logic wvalid,
    input logic wready,
    input logic [1:0] bresp,
    input logic bvalid,
    input logic bready,
    input logic [ADDR_WIDTH-1:0] araddr,
    input logic arvalid,
    input logic arready,
    input logic [DATA_WIDTH-1:0] rdata,
    input logic [1:0] rresp,
    input logic rvalid,
    input logic rready
);

    assert property (@(posedge clk) !rstn |=> (!bvalid && !rvalid));

    assert property (@(posedge clk) disable iff (!rstn)
        bvalid && !bready |=> bvalid && $stable(bresp)
    ) else $error("AXI4-Lite write response changed while stalled");

    assert property (@(posedge clk) disable iff (!rstn)
        rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp)
    ) else $error("AXI4-Lite read response changed while stalled");

    assert property (@(posedge clk) disable iff (!rstn)
        bvalid |-> (bresp inside {2'b00, 2'b10})
    ) else $error("AXI4-Lite produced unsupported BRESP");

    assert property (@(posedge clk) disable iff (!rstn)
        rvalid |-> (rresp inside {2'b00, 2'b10})
    ) else $error("AXI4-Lite produced unsupported RRESP");

    assert property (@(posedge clk) disable iff (!rstn)
        awvalid && !awready |=> $stable(awaddr)
    ) else $error("AXI4-Lite AWADDR changed before acceptance");

    assert property (@(posedge clk) disable iff (!rstn)
        wvalid && !wready |=> $stable(wdata) && $stable(wstrb)
    ) else $error("AXI4-Lite W payload changed before acceptance");

    assert property (@(posedge clk) disable iff (!rstn)
        arvalid && !arready |=> $stable(araddr)
    ) else $error("AXI4-Lite ARADDR changed before acceptance");

endmodule
