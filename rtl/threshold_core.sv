`timescale 1 ns / 100 ps

// Module: threshold_core
// Description:
// One-cycle registered threshold stage for 8-bit image pixels.
//
// Circuit:
// pixel_in/threshold -> comparator/mux -> output register
//
// The AXI/BRAM wrapper will feed this core one pixel at a time after the
// standalone datapath passes simulation against the Python golden vectors.

module threshold_core #(
    parameter int DATA_WIDTH = 8
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_in,
    input  logic [DATA_WIDTH-1:0] pixel_in,
    input  logic [DATA_WIDTH-1:0] threshold,
    output logic                  valid_out,
    output logic [DATA_WIDTH-1:0] pixel_out
);

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            pixel_out <= '0;
        end else begin
            valid_out <= valid_in;
            pixel_out <= (pixel_in >= threshold) ? '1 : '0;
        end
    end

endmodule
