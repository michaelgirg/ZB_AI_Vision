`timescale 1 ns / 100 ps

// Module: image_preprocess_axi_lite
// Description:
//   AXI4-Lite slave wrapper for the register-controlled preprocessing block.
//
// The image_preprocess_reg_block module owns the software-visible register
// behavior. This wrapper only handles AXI4-Lite handshakes.

module image_preprocess_axi_lite #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int PIXELS_PER_CYCLE = 1
) (
    input  logic                                  S_AXI_ACLK,
    input  logic                                  S_AXI_ARESETN,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_AWADDR,
    input  logic [2:0]                            S_AXI_AWPROT,
    input  logic                                  S_AXI_AWVALID,
    output logic                                  S_AXI_AWREADY,

    input  logic [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]     S_AXI_WSTRB,
    input  logic                                  S_AXI_WVALID,
    output logic                                  S_AXI_WREADY,

    output logic [1:0]                            S_AXI_BRESP,
    output logic                                  S_AXI_BVALID,
    input  logic                                  S_AXI_BREADY,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_ARADDR,
    input  logic [2:0]                            S_AXI_ARPROT,
    input  logic                                  S_AXI_ARVALID,
    output logic                                  S_AXI_ARREADY,

    output logic [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_RDATA,
    output logic [1:0]                            S_AXI_RRESP,
    output logic                                  S_AXI_RVALID,
    input  logic                                  S_AXI_RREADY
);

    localparam int STRB_WIDTH = C_S_AXI_DATA_WIDTH / 8;

    logic                                      rst;
    logic                                      aw_captured_r;
    logic                                      w_captured_r;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             awaddr_r;
    logic [C_S_AXI_DATA_WIDTH-1:0]             wdata_r;
    logic [STRB_WIDTH-1:0]                     wstrb_r;
    logic                                      write_fire;
    logic [C_S_AXI_DATA_WIDTH-1:0]             write_data_masked;

    logic                                      reg_write_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             reg_write_addr;
    logic [C_S_AXI_DATA_WIDTH-1:0]             reg_write_data;
    logic                                      reg_read_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             reg_read_addr;
    logic [C_S_AXI_DATA_WIDTH-1:0]             reg_read_data;

    assign rst = ~S_AXI_ARESETN;
    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;

    assign S_AXI_AWREADY = !aw_captured_r && !S_AXI_BVALID;
    assign S_AXI_WREADY = !w_captured_r && !S_AXI_BVALID;
    assign S_AXI_ARREADY = !S_AXI_RVALID;

    assign write_fire = aw_captured_r && w_captured_r && !S_AXI_BVALID;
    assign reg_read_en = S_AXI_ARVALID && S_AXI_ARREADY;
    assign reg_read_addr = S_AXI_ARADDR;

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] apply_write_strobes(
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [STRB_WIDTH-1:0] strobes
    );
        logic [C_S_AXI_DATA_WIDTH-1:0] masked;

        masked = '0;
        for (int byte_index = 0; byte_index < STRB_WIDTH; byte_index++) begin
            if (strobes[byte_index]) begin
                masked[byte_index*8 +: 8] = data[byte_index*8 +: 8];
            end
        end

        return masked;
    endfunction

    assign write_data_masked = apply_write_strobes(wdata_r, wstrb_r);

    image_preprocess_reg_block #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(PIXELS_PER_CYCLE),
        .REG_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .REG_DATA_WIDTH(C_S_AXI_DATA_WIDTH)
    ) reg_block (
        .clk(S_AXI_ACLK),
        .rst(rst),
        .reg_write_en(reg_write_en),
        .reg_write_addr(reg_write_addr),
        .reg_write_data(reg_write_data),
        .reg_read_en(reg_read_en),
        .reg_read_addr(reg_read_addr),
        .reg_read_data(reg_read_data)
    );

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            aw_captured_r <= 1'b0;
            w_captured_r <= 1'b0;
            awaddr_r <= '0;
            wdata_r <= '0;
            wstrb_r <= '0;
            S_AXI_BVALID <= 1'b0;
            reg_write_en <= 1'b0;
            reg_write_addr <= '0;
            reg_write_data <= '0;
        end else begin
            reg_write_en <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_captured_r <= 1'b1;
                awaddr_r <= S_AXI_AWADDR;
            end

            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_captured_r <= 1'b1;
                wdata_r <= S_AXI_WDATA;
                wstrb_r <= S_AXI_WSTRB;
            end

            if (write_fire) begin
                reg_write_en <= 1'b1;
                reg_write_addr <= awaddr_r;
                reg_write_data <= write_data_masked;
                aw_captured_r <= 1'b0;
                w_captured_r <= 1'b0;
                S_AXI_BVALID <= 1'b1;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA <= '0;
        end else begin
            if (reg_read_en) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RDATA <= reg_read_data;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    // Mark protection fields as intentionally unused.
    logic unused_axi_prot;
    assign unused_axi_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};

endmodule
