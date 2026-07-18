`timescale 1 ns / 100 ps

module vector_core_safety_sva #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int IMAGE_PIXELS = 784,
    parameter int FIFO_DEPTH = 32,
    parameter int FIFO_PTR_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH),
    parameter int FIFO_COUNT_WIDTH = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH + 1)
) (
    input logic aclk,
    input logic aresetn,
    input logic clear_done,
    input logic busy,
    input logic done,
    input logic packet_error,
    input logic input_fire,
    input logic output_fire,
    input logic [FIFO_PTR_WIDTH-1:0] fifo_rd_ptr,
    input logic [FIFO_PTR_WIDTH-1:0] fifo_wr_ptr,
    input logic [FIFO_COUNT_WIDTH-1:0] fifo_count,
    input logic [DATA_WIDTH-1:0] m_axis_tdata,
    input logic [KEEP_WIDTH-1:0] m_axis_tkeep,
    input logic m_axis_tvalid,
    input logic m_axis_tready,
    input logic m_axis_tlast
);

    int unsigned accepted_input_count;
    int unsigned accepted_output_count;

    assert property (@(posedge aclk) !aresetn |=>
        (!busy && !done && !packet_error && !m_axis_tvalid)
    );

    assert property (@(posedge aclk) disable iff (!aresetn)
        fifo_count <= FIFO_DEPTH
    ) else $error("vector FIFO count exceeded depth");

    assert property (@(posedge aclk) disable iff (!aresetn)
        fifo_rd_ptr < FIFO_DEPTH
    ) else $error("vector FIFO read pointer exceeded depth");

    assert property (@(posedge aclk) disable iff (!aresetn)
        fifo_wr_ptr < FIFO_DEPTH
    ) else $error("vector FIFO write pointer exceeded depth");

    assert property (@(posedge aclk) disable iff (!aresetn)
        m_axis_tvalid && !m_axis_tready |=>
            m_axis_tvalid && $stable(m_axis_tdata) &&
            $stable(m_axis_tkeep) && $stable(m_axis_tlast)
    ) else $error("vector output changed while stalled");

    assert property (@(posedge aclk) disable iff (!aresetn)
        m_axis_tvalid |-> (m_axis_tkeep == '1)
    ) else $error("vector output TKEEP was not full");

    // done is sticky until clear_done or the next frame starts. Only its
    // rising edge must correspond to the preceding final output handshake.
    assert property (@(posedge aclk) disable iff (!aresetn)
        $rose(done) |-> $past(output_fire && m_axis_tlast)
    ) else $error("vector done rise did not follow final output acceptance");

    assert property (@(posedge aclk) disable iff (!aresetn)
        done |-> !busy
    ) else $error("vector done and busy were asserted together");

    assert property (@(posedge aclk) disable iff (!aresetn)
        packet_error && !clear_done |=> packet_error
    ) else $error("vector packet_error cleared without clear_done/reset");

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            accepted_input_count <= 0;
            accepted_output_count <= 0;
        end else begin
            if (input_fire) begin
                accepted_input_count <=
                    (accepted_input_count == IMAGE_PIXELS - 1) ? 0 : accepted_input_count + 1;
            end
            if (output_fire) begin
                assert (m_axis_tlast == (accepted_output_count == IMAGE_PIXELS - 1))
                    else $error("vector output TLAST position mismatch at %0d", accepted_output_count);
                accepted_output_count <=
                    (accepted_output_count == IMAGE_PIXELS - 1) ? 0 : accepted_output_count + 1;
            end
        end
    end

endmodule
