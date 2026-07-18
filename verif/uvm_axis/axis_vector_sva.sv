`timescale 1 ns / 100 ps

// Module: axis_vector_sva
// Description:
//Protocol and frame-accounting assertions for the vector stream data plane.

module axis_vector_sva #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int IMAGE_PIXELS = 784
) (
    input logic clk,
    input logic rstn,
    input logic allow_malformed_input,
    input logic [DATA_WIDTH-1:0] s_tdata,
    input logic [KEEP_WIDTH-1:0] s_tkeep,
    input logic s_tvalid,
    input logic s_tready,
    input logic s_tlast,
    input logic [DATA_WIDTH-1:0] m_tdata,
    input logic [KEEP_WIDTH-1:0] m_tkeep,
    input logic m_tvalid,
    input logic m_tready,
    input logic m_tlast
);

    int unsigned input_count;
    int unsigned output_count;

    property p_output_stable_while_stalled;
        @(posedge clk) disable iff (!rstn)
        m_tvalid && !m_tready |=> m_tvalid &&
            $stable(m_tdata) && $stable(m_tkeep) && $stable(m_tlast);
    endproperty

    property p_output_keep_full;
        @(posedge clk) disable iff (!rstn)
        m_tvalid |-> (m_tkeep == '1);
    endproperty

    property p_input_keep_full;
        @(posedge clk) disable iff (!rstn)
        s_tvalid && s_tready && !allow_malformed_input |-> (s_tkeep == '1);
    endproperty

    assert property (p_output_stable_while_stalled)
        else $error("AXI4-Stream output changed while stalled");
    assert property (p_output_keep_full)
        else $error("AXI4-Stream output TKEEP was not full");
    assert property (p_input_keep_full)
        else $error("AXI4-Stream input TKEEP was not full");

    always_ff @(posedge clk) begin
        if (!rstn) begin
            input_count <= 0;
            output_count <= 0;
        end else begin
            if (s_tvalid && s_tready) begin
                if (!allow_malformed_input) begin
                    assert (s_tlast == (input_count == IMAGE_PIXELS - 1))
                        else $error("input TLAST mismatch at beat %0d", input_count);
                end
                input_count <= (input_count == IMAGE_PIXELS - 1) ? 0 : (input_count + 1);
            end
            if (m_tvalid && m_tready) begin
                assert (m_tlast == (output_count == IMAGE_PIXELS - 1))
                    else $error("output TLAST mismatch at beat %0d", output_count);
                output_count <= m_tlast ? 0 : (output_count + 1);
            end
        end
    end

    logic unused_input_data;
    assign unused_input_data = ^s_tdata;

endmodule
