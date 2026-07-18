`timescale 1 ns / 100 ps

module cdc_bridge_sva #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input logic                  s_axi_clk,
    input logic                  s_axi_resetn,
    input logic                  request_pending,
    input logic                  request_toggle,
    input logic                  request_write,
    input logic [ADDR_WIDTH-1:0] request_addr,
    input logic [DATA_WIDTH-1:0] request_data,
    input logic [DATA_WIDTH/8-1:0] request_strb,
    input logic                  s_awready,
    input logic                  s_wready,
    input logic                  s_arready,
    input logic                  s_bvalid,
    input logic                  s_bready,
    input logic [1:0]            s_bresp,
    input logic                  s_rvalid,
    input logic                  s_rready,
    input logic [DATA_WIDTH-1:0] s_rdata,
    input logic [1:0]            s_rresp,

    input logic                  axis_clk,
    input logic                  axis_resetn,
    input logic [1:0]            bridge_state,
    input logic                  core_awvalid,
    input logic                  core_awready,
    input logic [ADDR_WIDTH-1:0] core_awaddr,
    input logic                  core_wvalid,
    input logic                  core_wready,
    input logic [DATA_WIDTH-1:0] core_wdata,
    input logic [DATA_WIDTH/8-1:0] core_wstrb,
    input logic                  core_arvalid,
    input logic                  core_arready,
    input logic [ADDR_WIDTH-1:0] core_araddr,
    input logic                  response_toggle,
    input logic [1:0]            response_code,
    input logic [DATA_WIDTH-1:0] response_data
);
    localparam logic [1:0] BRIDGE_IDLE = 2'd0;
    localparam logic [1:0] BRIDGE_WRITE = 2'd1;
    localparam logic [1:0] BRIDGE_READ = 2'd2;
    localparam logic [1:0] BRIDGE_RESPONSE = 2'd3;

    assert property (@(posedge s_axi_clk) disable iff (!s_axi_resetn)
        request_pending && $past(request_pending) |->
            $stable({request_toggle, request_write, request_addr, request_data, request_strb})
    ) else $error("CDC request payload changed before its response returned");

    assert property (@(posedge s_axi_clk) disable iff (!s_axi_resetn)
        request_pending |-> (!s_awready && !s_wready && !s_arready)
    ) else $error("CDC bridge accepted a second AXI request while one was pending");

    assert property (@(posedge s_axi_clk) disable iff (!s_axi_resetn)
        !(s_bvalid && s_rvalid)
    ) else $error("CDC bridge asserted read and write responses together");

    assert property (@(posedge s_axi_clk) disable iff (!s_axi_resetn)
        s_bvalid && !s_bready |=> s_bvalid && $stable(s_bresp)
    ) else $error("CDC write response changed while stalled");

    assert property (@(posedge s_axi_clk) disable iff (!s_axi_resetn)
        s_rvalid && !s_rready |=> s_rvalid && $stable({s_rdata, s_rresp})
    ) else $error("CDC read response changed while stalled");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        bridge_state inside {
            BRIDGE_IDLE, BRIDGE_WRITE, BRIDGE_READ, BRIDGE_RESPONSE
        }
    ) else $error("CDC bridge entered an illegal state");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        core_awvalid && !core_awready |=> core_awvalid && $stable(core_awaddr)
    ) else $error("CDC core AW payload changed before acceptance");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        core_wvalid && !core_wready |=>
            core_wvalid && $stable({core_wdata, core_wstrb})
    ) else $error("CDC core W payload changed before acceptance");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        core_arvalid && !core_arready |=> core_arvalid && $stable(core_araddr)
    ) else $error("CDC core AR payload changed before acceptance");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        $stable(response_toggle) |-> $stable({response_code, response_data})
    ) else $error("CDC response payload changed without a response event");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        (bridge_state == BRIDGE_WRITE) |-> !core_arvalid
    ) else $error("CDC read request asserted during a write transaction");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        (bridge_state == BRIDGE_READ) |-> !(core_awvalid || core_wvalid)
    ) else $error("CDC write request asserted during a read transaction");

    assert property (@(posedge axis_clk) disable iff (!axis_resetn)
        (bridge_state == BRIDGE_RESPONSE) |->
            !(core_awvalid || core_wvalid || core_arvalid)
    ) else $error("CDC core request remained active while returning a response");
endmodule
