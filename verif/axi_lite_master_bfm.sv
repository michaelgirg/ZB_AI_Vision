`timescale 1 ns / 100 ps

// Module: axi_lite_master_bfm
// Description:
//Reusable AXI4-Lite master bus-functional model for verification tests.

module axi_lite_master_bfm #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
) (
    input  logic                              clk,
    input  logic                              rstn,

    output logic [ADDR_WIDTH-1:0]             m_axi_awaddr,
    output logic [2:0]                        m_axi_awprot,
    output logic                              m_axi_awvalid,
    input  logic                              m_axi_awready,

    output logic [DATA_WIDTH-1:0]             m_axi_wdata,
    output logic [(DATA_WIDTH/8)-1:0]         m_axi_wstrb,
    output logic                              m_axi_wvalid,
    input  logic                              m_axi_wready,

    input  logic [1:0]                        m_axi_bresp,
    input  logic                              m_axi_bvalid,
    output logic                              m_axi_bready,

    output logic [ADDR_WIDTH-1:0]             m_axi_araddr,
    output logic [2:0]                        m_axi_arprot,
    output logic                              m_axi_arvalid,
    input  logic                              m_axi_arready,

    input  logic [DATA_WIDTH-1:0]             m_axi_rdata,
    input  logic [1:0]                        m_axi_rresp,
    input  logic                              m_axi_rvalid,
    output logic                              m_axi_rready
);

    task automatic init();
        m_axi_awaddr <= '0;
        m_axi_awprot <= '0;
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= '0;
        m_axi_wstrb <= '0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        m_axi_araddr <= '0;
        m_axi_arprot <= '0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
    endtask

    task automatic write(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        output bit ok
    );
        bit aw_done;
        bit w_done;

        ok = 1'b1;
        aw_done = 1'b0;
        w_done = 1'b0;

        @(negedge clk);
        m_axi_awaddr <= addr;
        m_axi_awvalid <= 1'b1;
        m_axi_wdata <= data;
        m_axi_wstrb <= '1;
        m_axi_wvalid <= 1'b1;
        m_axi_bready <= 1'b1;

        while (!aw_done || !w_done) begin
            @(posedge clk);
            if (m_axi_awvalid && m_axi_awready) begin
                aw_done = 1'b1;
            end
            if (m_axi_wvalid && m_axi_wready) begin
                w_done = 1'b1;
            end

            @(negedge clk);
            if (aw_done) begin
                m_axi_awvalid <= 1'b0;
            end
            if (w_done) begin
                m_axi_wvalid <= 1'b0;
            end
        end

        while (m_axi_bvalid !== 1'b1) begin
            @(posedge clk);
        end

        if (m_axi_bresp !== 2'b00) begin
            ok = 1'b0;
            $error("AXI write response error at addr 0x%02h: bresp=%0b", addr, m_axi_bresp);
        end

        @(negedge clk);
        m_axi_bready <= 1'b0;
        m_axi_awaddr <= '0;
        m_axi_wdata <= '0;
        m_axi_wstrb <= '0;
    endtask

    task automatic write_with_response_stall(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input int stall_cycles,
        output bit ok
    );
        bit aw_done;
        bit w_done;

        ok = 1'b1;
        aw_done = 1'b0;
        w_done = 1'b0;

        @(negedge clk);
        m_axi_awaddr <= addr;
        m_axi_awvalid <= 1'b1;
        m_axi_wdata <= data;
        m_axi_wstrb <= '1;
        m_axi_wvalid <= 1'b1;
        m_axi_bready <= 1'b0;

        while (!aw_done || !w_done) begin
            @(posedge clk);
            if (m_axi_awvalid && m_axi_awready) begin
                aw_done = 1'b1;
            end
            if (m_axi_wvalid && m_axi_wready) begin
                w_done = 1'b1;
            end

            @(negedge clk);
            if (aw_done) begin
                m_axi_awvalid <= 1'b0;
            end
            if (w_done) begin
                m_axi_wvalid <= 1'b0;
            end
        end

        repeat (stall_cycles) @(posedge clk);

        @(negedge clk);
        m_axi_bready <= 1'b1;
        while (m_axi_bvalid !== 1'b1) begin
            @(posedge clk);
        end

        if (m_axi_bresp !== 2'b00) begin
            ok = 1'b0;
            $error("AXI write response error at addr 0x%02h: bresp=%0b", addr, m_axi_bresp);
        end

        @(negedge clk);
        m_axi_bready <= 1'b0;
        m_axi_awaddr <= '0;
        m_axi_wdata <= '0;
        m_axi_wstrb <= '0;
    endtask

    task automatic read(
        input logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output bit ok
    );
        ok = 1'b1;

        @(negedge clk);
        m_axi_araddr <= addr;
        m_axi_arvalid <= 1'b1;
        m_axi_rready <= 1'b1;

        do begin
            @(posedge clk);
        end while (!(m_axi_arvalid && m_axi_arready));

        @(negedge clk);
        m_axi_arvalid <= 1'b0;

        while (m_axi_rvalid !== 1'b1) begin
            @(posedge clk);
        end

        data = m_axi_rdata;
        if (m_axi_rresp !== 2'b00) begin
            ok = 1'b0;
            $error("AXI read response error at addr 0x%02h: rresp=%0b", addr, m_axi_rresp);
        end

        @(negedge clk);
        m_axi_rready <= 1'b0;
        m_axi_araddr <= '0;
    endtask

    task automatic read_with_response_stall(
        input logic [ADDR_WIDTH-1:0] addr,
        input int stall_cycles,
        output logic [DATA_WIDTH-1:0] data,
        output bit ok
    );
        ok = 1'b1;

        @(negedge clk);
        m_axi_araddr <= addr;
        m_axi_arvalid <= 1'b1;
        m_axi_rready <= 1'b0;

        do begin
            @(posedge clk);
        end while (!(m_axi_arvalid && m_axi_arready));

        @(negedge clk);
        m_axi_arvalid <= 1'b0;

        repeat (stall_cycles) @(posedge clk);

        @(negedge clk);
        m_axi_rready <= 1'b1;
        while (m_axi_rvalid !== 1'b1) begin
            @(posedge clk);
        end

        data = m_axi_rdata;
        if (m_axi_rresp !== 2'b00) begin
            ok = 1'b0;
            $error("AXI read response error at addr 0x%02h: rresp=%0b", addr, m_axi_rresp);
        end

        @(negedge clk);
        m_axi_rready <= 1'b0;
        m_axi_araddr <= '0;
    endtask

endmodule
