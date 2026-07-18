`timescale 1 ns / 100 ps

module production_diag_sva (
    input logic        clk,
    input logic        rstn,
    input logic        irq,
    input logic [2:0]  error_status,
    input logic [2:0]  int_status,
    input logic [2:0]  int_enable,
    input logic [31:0] frame_count,
    input logic [31:0] error_count,
    input logic [31:0] input_stall_cycles,
    input logic [31:0] output_stall_cycles,
    input logic        perf_clear_pulse,
    input logic        frame_done_event,
    input logic        packet_error_event,
    input logic        write_error_event,
    input logic        read_error_event,
    input logic        input_stall_event,
    input logic        output_stall_event
);
    localparam logic [31:0] COUNTER_MAX = 32'hffff_ffff;

    assert property (@(posedge clk) disable iff (!rstn)
        irq == |(int_status & int_enable)
    ) else $error("IRQ did not equal the enabled interrupt-status reduction");

    assert property (@(posedge clk) disable iff (!rstn)
        perf_clear_pulse |=>
            (frame_count == 0) &&
            (error_count == 0) &&
            (input_stall_cycles == 0) &&
            (output_stall_cycles == 0)
    ) else $error("PERF_CONTROL clear did not clear all production counters");

    assert property (@(posedge clk) disable iff (!rstn)
        frame_done_event && !perf_clear_pulse && (frame_count != COUNTER_MAX) |=>
            frame_count == ($past(frame_count) + 32'd1)
    ) else $error("FRAME_COUNT did not increment on frame completion");

    assert property (@(posedge clk) disable iff (!rstn)
        frame_done_event && !perf_clear_pulse && (frame_count == COUNTER_MAX) |=>
            frame_count == COUNTER_MAX
    ) else $error("FRAME_COUNT did not saturate");

    assert property (@(posedge clk) disable iff (!rstn)
        (packet_error_event || write_error_event || read_error_event) &&
        !perf_clear_pulse && (error_count != COUNTER_MAX) |=>
            error_count == ($past(error_count) + 32'd1)
    ) else $error("ERROR_COUNT did not increment on a production error event");

    assert property (@(posedge clk) disable iff (!rstn)
        input_stall_event && !perf_clear_pulse &&
        (input_stall_cycles != COUNTER_MAX) |=>
            input_stall_cycles == ($past(input_stall_cycles) + 32'd1)
    ) else $error("INPUT_STALL_CYCLES did not increment");

    assert property (@(posedge clk) disable iff (!rstn)
        output_stall_event && !perf_clear_pulse &&
        (output_stall_cycles != COUNTER_MAX) |=>
            output_stall_cycles == ($past(output_stall_cycles) + 32'd1)
    ) else $error("OUTPUT_STALL_CYCLES did not increment");

    assert property (@(posedge clk) disable iff (!rstn)
        frame_done_event |=> int_status[0]
    ) else $error("frame completion did not set INT_STATUS.done");

    assert property (@(posedge clk) disable iff (!rstn)
        packet_error_event |=> error_status[0] && int_status[1]
    ) else $error("packet error did not set diagnostic and interrupt status");

    assert property (@(posedge clk) disable iff (!rstn)
        write_error_event |=> error_status[1] && int_status[2]
    ) else $error("rejected write did not set diagnostic and interrupt status");

    assert property (@(posedge clk) disable iff (!rstn)
        read_error_event |=> error_status[2] && int_status[2]
    ) else $error("rejected read did not set diagnostic and interrupt status");
endmodule
