`timescale 1 ns / 100 ps

module zb_cdc_single #(
    parameter bit SRC_INPUT_REG = 1'b0
) (
    input  logic src_clk,
    input  logic src_resetn,
    input  logic src_in,
    input  logic dest_clk,
    input  logic dest_resetn,
    output logic dest_out
);
`ifdef SYNTHESIS
    logic unused_resets;
    assign unused_resets = src_resetn ^ dest_resetn;

    xpm_cdc_single #(
        .DEST_SYNC_FF(2),
        .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),
        .SRC_INPUT_REG(SRC_INPUT_REG)
    ) xpm_single_i (
        .src_clk(src_clk),
        .src_in(src_in),
        .dest_clk(dest_clk),
        .dest_out(dest_out)
    );
`else
    logic src_value_r;
    logic src_value;
    (* ASYNC_REG = "TRUE" *) logic [1:0] dest_sync_r;

    generate
        if (SRC_INPUT_REG) begin : gen_src_register
            always_ff @(posedge src_clk or negedge src_resetn) begin
                if (!src_resetn) src_value_r <= 1'b0;
                else src_value_r <= src_in;
            end
            assign src_value = src_value_r;
        end else begin : gen_src_wire
            assign src_value = src_in;
        end
    endgenerate

    always_ff @(posedge dest_clk or negedge dest_resetn) begin
        if (!dest_resetn) dest_sync_r <= '0;
        else dest_sync_r <= {dest_sync_r[0], src_value};
    end
    assign dest_out = dest_sync_r[1];
`endif
endmodule

// Portable wrapper around AMD's recognized bundled-data CDC primitive. Vivado
// synthesis uses XPM (including its scoped max-delay/bus-skew constraints);
// standalone Questa runs use the equivalent toggle-handshake model below.
module zb_cdc_handshake #(
    parameter int WIDTH = 1
) (
    input  logic                 src_clk,
    input  logic                 src_resetn,
    input  logic [WIDTH-1:0]     src_in,
    input  logic                 src_send,
    output logic                 src_rcv,
    input  logic                 dest_clk,
    input  logic                 dest_resetn,
    output logic [WIDTH-1:0]     dest_out,
    output logic                 dest_req
);
`ifdef SYNTHESIS
    logic unused_resets;
    assign unused_resets = src_resetn ^ dest_resetn;

    xpm_cdc_handshake #(
        .DEST_EXT_HSK(0),
        .DEST_SYNC_FF(2),
        .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),
        .SRC_SYNC_FF(2),
        .WIDTH(WIDTH)
    ) xpm_handshake_i (
        .src_clk(src_clk),
        .src_in(src_in),
        .src_send(src_send),
        .src_rcv(src_rcv),
        .dest_clk(dest_clk),
        .dest_out(dest_out),
        .dest_req(dest_req),
        .dest_ack(1'b0)
    );
`else
    logic [WIDTH-1:0] src_hold_r;
    logic src_send_q_r;
    logic request_toggle_r;
    logic ack_toggle_r;
    (* ASYNC_REG = "TRUE" *) logic [1:0] request_sync_r;
    (* ASYNC_REG = "TRUE" *) logic [1:0] ack_sync_r;
    logic request_seen_r;
    logic ack_seen_r;

    always_ff @(posedge src_clk or negedge src_resetn) begin
        if (!src_resetn) begin
            src_hold_r <= '0;
            src_send_q_r <= 1'b0;
            request_toggle_r <= 1'b0;
            ack_sync_r <= '0;
            ack_seen_r <= 1'b0;
            src_rcv <= 1'b0;
        end else begin
            ack_sync_r <= {ack_sync_r[0], ack_toggle_r};
            src_rcv <= 1'b0;
            if (src_send && !src_send_q_r) begin
                src_hold_r <= src_in;
                request_toggle_r <= ~request_toggle_r;
            end
            if (ack_sync_r[1] != ack_seen_r) begin
                ack_seen_r <= ack_sync_r[1];
                src_rcv <= 1'b1;
            end
            src_send_q_r <= src_send;
        end
    end

    always_ff @(posedge dest_clk or negedge dest_resetn) begin
        if (!dest_resetn) begin
            request_sync_r <= '0;
            request_seen_r <= 1'b0;
            ack_toggle_r <= 1'b0;
            dest_out <= '0;
            dest_req <= 1'b0;
        end else begin
            request_sync_r <= {request_sync_r[0], request_toggle_r};
            dest_req <= 1'b0;
            if (request_sync_r[1] != request_seen_r) begin
                request_seen_r <= request_sync_r[1];
                dest_out <= src_hold_r;
                dest_req <= 1'b1;
                ack_toggle_r <= ~ack_toggle_r;
            end
        end
    end
`endif
endmodule

// Dual-clock production wrapper. AXI4-Lite transactions cross into the stream
// clock domain through one-outstanding request/response bundled-data handshakes.
module axis_preprocess_vector_cdc #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int C_AXIS_DATA_WIDTH = 32,
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                                      S_AXI_ACLK,
    input  logic                                      S_AXI_ARESETN,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]             S_AXI_AWADDR,
    input  logic [2:0]                                S_AXI_AWPROT,
    input  logic                                      S_AXI_AWVALID,
    output logic                                      S_AXI_AWREADY,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]             S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]         S_AXI_WSTRB,
    input  logic                                      S_AXI_WVALID,
    output logic                                      S_AXI_WREADY,
    output logic [1:0]                                S_AXI_BRESP,
    output logic                                      S_AXI_BVALID,
    input  logic                                      S_AXI_BREADY,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]             S_AXI_ARADDR,
    input  logic [2:0]                                S_AXI_ARPROT,
    input  logic                                      S_AXI_ARVALID,
    output logic                                      S_AXI_ARREADY,
    output logic [C_S_AXI_DATA_WIDTH-1:0]             S_AXI_RDATA,
    output logic [1:0]                                S_AXI_RRESP,
    output logic                                      S_AXI_RVALID,
    input  logic                                      S_AXI_RREADY,

    input  logic                                      AXIS_ACLK,
    input  logic                                      AXIS_ARESETN,
    input  logic [C_AXIS_DATA_WIDTH-1:0]              S_AXIS_TDATA,
    input  logic [(C_AXIS_DATA_WIDTH/8)-1:0]          S_AXIS_TKEEP,
    input  logic                                      S_AXIS_TVALID,
    output logic                                      S_AXIS_TREADY,
    input  logic                                      S_AXIS_TLAST,
    output logic [C_AXIS_DATA_WIDTH-1:0]              M_AXIS_TDATA,
    output logic [(C_AXIS_DATA_WIDTH/8)-1:0]          M_AXIS_TKEEP,
    output logic                                      M_AXIS_TVALID,
    input  logic                                      M_AXIS_TREADY,
    output logic                                      M_AXIS_TLAST,
    output logic                                      irq
);

    localparam int AXI_STRB_WIDTH = C_S_AXI_DATA_WIDTH / 8;
    localparam int REQUEST_WIDTH =
        1 + C_S_AXI_ADDR_WIDTH + C_S_AXI_DATA_WIDTH + AXI_STRB_WIDTH;
    localparam int RESPONSE_WIDTH = 2 + C_S_AXI_DATA_WIDTH;
    localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

    (* ASYNC_REG = "TRUE" *) logic [1:0] s_axi_reset_sync_r;
    (* ASYNC_REG = "TRUE" *) logic [1:0] axis_reset_sync_r;
    logic axis_up_axi;
    logic axi_up_axis;
    logic s_axi_resetn;
    logic axis_resetn;
    logic bridge_axis_resetn;

    logic aw_captured_r;
    logic w_captured_r;
    logic ar_captured_r;
    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr_r;
    logic [C_S_AXI_DATA_WIDTH-1:0] wdata_r;
    logic [AXI_STRB_WIDTH-1:0] wstrb_r;
    logic [C_S_AXI_ADDR_WIDTH-1:0] araddr_r;
    logic request_pending_r;
    logic pending_write_r;

    logic request_toggle_r;
    logic request_write_r;
    logic [C_S_AXI_ADDR_WIDTH-1:0] request_addr_r;
    logic [C_S_AXI_DATA_WIDTH-1:0] request_data_r;
    logic [AXI_STRB_WIDTH-1:0] request_strb_r;
    logic request_launch_r;
    logic request_send_r;
    logic request_rcv_axi;
    logic [REQUEST_WIDTH-1:0] request_payload_axi;
    logic [REQUEST_WIDTH-1:0] request_payload_axis;
    logic request_valid_axis;
    logic request_write_axis;
    logic [C_S_AXI_ADDR_WIDTH-1:0] request_addr_axis;
    logic [C_S_AXI_DATA_WIDTH-1:0] request_data_axis;
    logic [AXI_STRB_WIDTH-1:0] request_strb_axis;

    logic response_toggle_axis_r;
    logic [1:0] response_code_axis_r;
    logic [C_S_AXI_DATA_WIDTH-1:0] response_data_axis_r;
    logic response_launch_axis_r;
    logic response_send_axis_r;
    logic response_rcv_axis;
    logic [RESPONSE_WIDTH-1:0] response_payload_axis;
    logic [RESPONSE_WIDTH-1:0] response_payload_axi;
    logic response_valid_axi;

    logic [C_S_AXI_ADDR_WIDTH-1:0] core_awaddr;
    logic core_awvalid;
    logic core_awready;
    logic [C_S_AXI_DATA_WIDTH-1:0] core_wdata;
    logic [AXI_STRB_WIDTH-1:0] core_wstrb;
    logic core_wvalid;
    logic core_wready;
    logic [1:0] core_bresp;
    logic core_bvalid;
    logic core_bready;
    logic [C_S_AXI_ADDR_WIDTH-1:0] core_araddr;
    logic core_arvalid;
    logic core_arready;
    logic [C_S_AXI_DATA_WIDTH-1:0] core_rdata;
    logic [1:0] core_rresp;
    logic core_rvalid;
    logic core_rready;
    logic core_irq_axis;

    typedef enum logic [1:0] {
        BRIDGE_IDLE,
        BRIDGE_WRITE,
        BRIDGE_READ,
        BRIDGE_RESPONSE
    } bridge_state_t;
    bridge_state_t bridge_state_r;

    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            s_axi_reset_sync_r <= '0;
        end else begin
            s_axi_reset_sync_r <= {s_axi_reset_sync_r[0], 1'b1};
        end
    end
    assign s_axi_resetn = s_axi_reset_sync_r[1];

    always_ff @(posedge AXIS_ACLK or negedge AXIS_ARESETN) begin
        if (!AXIS_ARESETN) begin
            axis_reset_sync_r <= '0;
        end else begin
            axis_reset_sync_r <= {axis_reset_sync_r[0], 1'b1};
        end
    end
    assign axis_resetn = axis_reset_sync_r[1];

    // A reset in either external clock domain flushes both halves of the
    // transaction bridge after synchronization. Software must not expect an
    // outstanding AXI-Lite transaction to survive either reset assertion.
    zb_cdc_single #(.SRC_INPUT_REG(1'b1)) axis_up_cdc_i (
        .src_clk(AXIS_ACLK),
        .src_resetn(AXIS_ARESETN),
        .src_in(AXIS_ARESETN),
        .dest_clk(S_AXI_ACLK),
        .dest_resetn(S_AXI_ARESETN),
        .dest_out(axis_up_axi)
    );

    zb_cdc_single #(.SRC_INPUT_REG(1'b1)) axi_up_cdc_i (
        .src_clk(S_AXI_ACLK),
        .src_resetn(S_AXI_ARESETN),
        .src_in(S_AXI_ARESETN),
        .dest_clk(AXIS_ACLK),
        .dest_resetn(AXIS_ARESETN),
        .dest_out(axi_up_axis)
    );
    assign bridge_axis_resetn = axis_resetn && axi_up_axis;

    assign request_payload_axi = {
        request_write_r, request_addr_r, request_data_r, request_strb_r
    };
    assign {
        request_write_axis, request_addr_axis,
        request_data_axis, request_strb_axis
    } = request_payload_axis;
    assign response_payload_axis = {response_code_axis_r, response_data_axis_r};

    zb_cdc_handshake #(.WIDTH(REQUEST_WIDTH)) request_cdc_i (
        .src_clk(S_AXI_ACLK),
        .src_resetn(s_axi_resetn && axis_up_axi),
        .src_in(request_payload_axi),
        .src_send(request_send_r),
        .src_rcv(request_rcv_axi),
        .dest_clk(AXIS_ACLK),
        .dest_resetn(bridge_axis_resetn),
        .dest_out(request_payload_axis),
        .dest_req(request_valid_axis)
    );

    zb_cdc_handshake #(.WIDTH(RESPONSE_WIDTH)) response_cdc_i (
        .src_clk(AXIS_ACLK),
        .src_resetn(bridge_axis_resetn),
        .src_in(response_payload_axis),
        .src_send(response_send_axis_r),
        .src_rcv(response_rcv_axis),
        .dest_clk(S_AXI_ACLK),
        .dest_resetn(s_axi_resetn && axis_up_axi),
        .dest_out(response_payload_axi),
        .dest_req(response_valid_axi)
    );

    zb_cdc_single #(.SRC_INPUT_REG(1'b1)) irq_cdc_i (
        .src_clk(AXIS_ACLK),
        .src_resetn(bridge_axis_resetn),
        .src_in(core_irq_axis),
        .dest_clk(S_AXI_ACLK),
        .dest_resetn(s_axi_resetn && axis_up_axi),
        .dest_out(irq)
    );

    always_comb begin
        S_AXI_AWREADY = 1'b0;
        S_AXI_WREADY = 1'b0;
        S_AXI_ARREADY = 1'b0;
        if (s_axi_resetn && axis_up_axi &&
            !request_pending_r && !request_launch_r && !request_send_r &&
            !request_rcv_axi && !S_AXI_BVALID && !S_AXI_RVALID) begin
            S_AXI_AWREADY = !aw_captured_r && !ar_captured_r;
            S_AXI_WREADY = !w_captured_r && !ar_captured_r;
            S_AXI_ARREADY =
                !ar_captured_r && !aw_captured_r && !w_captured_r &&
                !S_AXI_AWVALID && !S_AXI_WVALID;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!s_axi_resetn || !axis_up_axi) begin
            aw_captured_r <= 1'b0;
            w_captured_r <= 1'b0;
            ar_captured_r <= 1'b0;
            awaddr_r <= '0;
            wdata_r <= '0;
            wstrb_r <= '0;
            araddr_r <= '0;
            request_pending_r <= 1'b0;
            pending_write_r <= 1'b0;
            request_toggle_r <= 1'b0;
            request_write_r <= 1'b0;
            request_addr_r <= '0;
            request_data_r <= '0;
            request_strb_r <= '0;
            request_launch_r <= 1'b0;
            request_send_r <= 1'b0;
            S_AXI_BRESP <= AXI_RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
            S_AXI_RDATA <= '0;
            S_AXI_RRESP <= AXI_RESP_OKAY;
            S_AXI_RVALID <= 1'b0;
        end else begin
            if (request_launch_r && !request_rcv_axi) begin
                request_launch_r <= 1'b0;
                request_send_r <= 1'b1;
            end
            if (request_send_r && request_rcv_axi) begin
                request_send_r <= 1'b0;
            end

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_captured_r <= 1'b1;
                awaddr_r <= S_AXI_AWADDR;
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_captured_r <= 1'b1;
                wdata_r <= S_AXI_WDATA;
                wstrb_r <= S_AXI_WSTRB;
            end
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                ar_captured_r <= 1'b1;
                araddr_r <= S_AXI_ARADDR;
            end

            if (!request_pending_r && aw_captured_r && w_captured_r) begin
                request_write_r <= 1'b1;
                request_addr_r <= awaddr_r;
                request_data_r <= wdata_r;
                request_strb_r <= wstrb_r;
                request_toggle_r <= ~request_toggle_r;
                request_launch_r <= 1'b1;
                request_pending_r <= 1'b1;
                pending_write_r <= 1'b1;
                aw_captured_r <= 1'b0;
                w_captured_r <= 1'b0;
            end else if (!request_pending_r && ar_captured_r) begin
                request_write_r <= 1'b0;
                request_addr_r <= araddr_r;
                request_data_r <= '0;
                request_strb_r <= '0;
                request_toggle_r <= ~request_toggle_r;
                request_launch_r <= 1'b1;
                request_pending_r <= 1'b1;
                pending_write_r <= 1'b0;
                ar_captured_r <= 1'b0;
            end

            if (request_pending_r && response_valid_axi) begin
                request_pending_r <= 1'b0;
                if (pending_write_r) begin
                    S_AXI_BRESP <= response_payload_axi[RESPONSE_WIDTH-1 -: 2];
                    S_AXI_BVALID <= 1'b1;
                end else begin
                    S_AXI_RDATA <= response_payload_axi[C_S_AXI_DATA_WIDTH-1:0];
                    S_AXI_RRESP <= response_payload_axi[RESPONSE_WIDTH-1 -: 2];
                    S_AXI_RVALID <= 1'b1;
                end
            end

            if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    always_ff @(posedge AXIS_ACLK) begin
        if (!bridge_axis_resetn) begin
            response_toggle_axis_r <= 1'b0;
            response_code_axis_r <= AXI_RESP_OKAY;
            response_data_axis_r <= '0;
            response_launch_axis_r <= 1'b0;
            response_send_axis_r <= 1'b0;
            bridge_state_r <= BRIDGE_IDLE;
            core_awaddr <= '0;
            core_awvalid <= 1'b0;
            core_wdata <= '0;
            core_wstrb <= '0;
            core_wvalid <= 1'b0;
            core_bready <= 1'b0;
            core_araddr <= '0;
            core_arvalid <= 1'b0;
            core_rready <= 1'b0;
        end else begin
            if (response_launch_axis_r && !response_rcv_axis) begin
                response_launch_axis_r <= 1'b0;
                response_send_axis_r <= 1'b1;
            end
            if (response_send_axis_r && response_rcv_axis) begin
                response_send_axis_r <= 1'b0;
            end

            unique case (bridge_state_r)
                BRIDGE_IDLE: begin
                    core_awvalid <= 1'b0;
                    core_wvalid <= 1'b0;
                    core_bready <= 1'b0;
                    core_arvalid <= 1'b0;
                    core_rready <= 1'b0;
                    if (request_valid_axis) begin
                        if (request_write_axis) begin
                            core_awaddr <= request_addr_axis;
                            core_awvalid <= 1'b1;
                            core_wdata <= request_data_axis;
                            core_wstrb <= request_strb_axis;
                            core_wvalid <= 1'b1;
                            core_bready <= 1'b1;
                            bridge_state_r <= BRIDGE_WRITE;
                        end else begin
                            core_araddr <= request_addr_axis;
                            core_arvalid <= 1'b1;
                            core_rready <= 1'b1;
                            bridge_state_r <= BRIDGE_READ;
                        end
                    end
                end

                BRIDGE_WRITE: begin
                    if (core_awvalid && core_awready) core_awvalid <= 1'b0;
                    if (core_wvalid && core_wready) core_wvalid <= 1'b0;
                    if (core_bvalid && core_bready) begin
                        response_code_axis_r <= core_bresp;
                        response_data_axis_r <= '0;
                        response_toggle_axis_r <= ~response_toggle_axis_r;
                        response_launch_axis_r <= 1'b1;
                        core_bready <= 1'b0;
                        bridge_state_r <= BRIDGE_RESPONSE;
                    end
                end

                BRIDGE_READ: begin
                    if (core_arvalid && core_arready) core_arvalid <= 1'b0;
                    if (core_rvalid && core_rready) begin
                        response_code_axis_r <= core_rresp;
                        response_data_axis_r <= core_rdata;
                        response_toggle_axis_r <= ~response_toggle_axis_r;
                        response_launch_axis_r <= 1'b1;
                        core_rready <= 1'b0;
                        bridge_state_r <= BRIDGE_RESPONSE;
                    end
                end

                BRIDGE_RESPONSE: begin
                    if (!response_launch_axis_r &&
                        !response_send_axis_r && !response_rcv_axis) begin
                        bridge_state_r <= BRIDGE_IDLE;
                    end
                end

                default: bridge_state_r <= BRIDGE_IDLE;
            endcase
        end
    end

    axis_preprocess_vector_axi_lite #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_AXIS_DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .IMAGE_PIXELS(IMAGE_PIXELS),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) stream_domain_core (
        .S_AXI_ACLK(AXIS_ACLK),
        .S_AXI_ARESETN(bridge_axis_resetn),
        .S_AXI_AWADDR(core_awaddr),
        .S_AXI_AWPROT(3'b000),
        .S_AXI_AWVALID(core_awvalid),
        .S_AXI_AWREADY(core_awready),
        .S_AXI_WDATA(core_wdata),
        .S_AXI_WSTRB(core_wstrb),
        .S_AXI_WVALID(core_wvalid),
        .S_AXI_WREADY(core_wready),
        .S_AXI_BRESP(core_bresp),
        .S_AXI_BVALID(core_bvalid),
        .S_AXI_BREADY(core_bready),
        .S_AXI_ARADDR(core_araddr),
        .S_AXI_ARPROT(3'b000),
        .S_AXI_ARVALID(core_arvalid),
        .S_AXI_ARREADY(core_arready),
        .S_AXI_RDATA(core_rdata),
        .S_AXI_RRESP(core_rresp),
        .S_AXI_RVALID(core_rvalid),
        .S_AXI_RREADY(core_rready),
        .S_AXIS_TDATA(S_AXIS_TDATA),
        .S_AXIS_TKEEP(S_AXIS_TKEEP),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .S_AXIS_TLAST(S_AXIS_TLAST),
        .M_AXIS_TDATA(M_AXIS_TDATA),
        .M_AXIS_TKEEP(M_AXIS_TKEEP),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        .M_AXIS_TREADY(M_AXIS_TREADY),
        .M_AXIS_TLAST(M_AXIS_TLAST),
        .irq(core_irq_axis)
    );

    logic unused_axi_prot;
    assign unused_axi_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};

endmodule
