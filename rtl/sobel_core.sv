`timescale 1 ns / 100 ps

// Module: sobel_core
// Description:
//   Pipelined 3x3 Sobel edge stage for 8-bit grayscale pixels.
//
// Timing intent:
//   - stage 0 registers the incoming 3x3 window
//   - stage 1 registers Gx/Gy gradient sums
//   - stage 2 registers abs(Gx) + abs(Gy)
//   - stage 3 registers saturated uint8 output
//   - reset only valid/control state; invalid datapath values are ignored

module sobel_core #(
    parameter int DATA_WIDTH = 8,
    parameter int GRAD_WIDTH = DATA_WIDTH + 4,
    parameter int EDGE_SUM_WIDTH = GRAD_WIDTH + 1
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_in,
    input  logic                  border_in,
    input  logic [DATA_WIDTH-1:0] pixel_top_left,
    input  logic [DATA_WIDTH-1:0] pixel_top,
    input  logic [DATA_WIDTH-1:0] pixel_top_right,
    input  logic [DATA_WIDTH-1:0] pixel_left,
    input  logic [DATA_WIDTH-1:0] pixel_right,
    input  logic [DATA_WIDTH-1:0] pixel_bottom_left,
    input  logic [DATA_WIDTH-1:0] pixel_bottom,
    input  logic [DATA_WIDTH-1:0] pixel_bottom_right,
    output logic                  valid_out,
    output logic [DATA_WIDTH-1:0] pixel_out
);

    logic signed [GRAD_WIDTH-1:0] gx_r;
    logic signed [GRAD_WIDTH-1:0] gy_r;
    logic [EDGE_SUM_WIDTH-1:0]    edge_sum_r;
    logic [DATA_WIDTH-1:0]        pixel_top_left_r;
    logic [DATA_WIDTH-1:0]        pixel_top_r;
    logic [DATA_WIDTH-1:0]        pixel_top_right_r;
    logic [DATA_WIDTH-1:0]        pixel_left_r;
    logic [DATA_WIDTH-1:0]        pixel_right_r;
    logic [DATA_WIDTH-1:0]        pixel_bottom_left_r;
    logic [DATA_WIDTH-1:0]        pixel_bottom_r;
    logic [DATA_WIDTH-1:0]        pixel_bottom_right_r;
    logic                         valid_window_r;
    logic                         valid_grad_r;
    logic                         valid_sum_r;
    logic                         border_window_r;
    logic                         border_grad_r;
    logic                         border_sum_r;

    function automatic logic signed [GRAD_WIDTH-1:0] sx(input logic [DATA_WIDTH-1:0] value);
        logic signed [GRAD_WIDTH-1:0] extended;

        extended = '0;
        extended[DATA_WIDTH-1:0] = value;
        return extended;
    endfunction

    function automatic logic [GRAD_WIDTH-1:0] abs_grad(input logic signed [GRAD_WIDTH-1:0] value);
        logic signed [GRAD_WIDTH-1:0] negated;

        if (value[GRAD_WIDTH-1] == 1'b1) begin
            negated = -value;
            return negated[GRAD_WIDTH-1:0];
        end

        return value[GRAD_WIDTH-1:0];
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_window_r <= 1'b0;
            valid_grad_r <= 1'b0;
            valid_sum_r <= 1'b0;
            valid_out <= 1'b0;
            border_window_r <= 1'b0;
            border_grad_r <= 1'b0;
            border_sum_r <= 1'b0;
        end else begin
            valid_window_r <= valid_in;
            valid_grad_r <= valid_window_r;
            valid_sum_r <= valid_grad_r;
            valid_out <= valid_sum_r;

            border_window_r <= border_in;
            border_grad_r <= border_window_r;
            border_sum_r <= border_grad_r;

            pixel_top_left_r <= pixel_top_left;
            pixel_top_r <= pixel_top;
            pixel_top_right_r <= pixel_top_right;
            pixel_left_r <= pixel_left;
            pixel_right_r <= pixel_right;
            pixel_bottom_left_r <= pixel_bottom_left;
            pixel_bottom_r <= pixel_bottom;
            pixel_bottom_right_r <= pixel_bottom_right;

            gx_r <= -sx(pixel_top_left_r)
                  + sx(pixel_top_right_r)
                  - (sx(pixel_left_r) <<< 1)
                  + (sx(pixel_right_r) <<< 1)
                  - sx(pixel_bottom_left_r)
                  + sx(pixel_bottom_right_r);

            gy_r <= -sx(pixel_top_left_r)
                  - (sx(pixel_top_r) <<< 1)
                  - sx(pixel_top_right_r)
                  + sx(pixel_bottom_left_r)
                  + (sx(pixel_bottom_r) <<< 1)
                  + sx(pixel_bottom_right_r);

            edge_sum_r <= EDGE_SUM_WIDTH'(abs_grad(gx_r)) + EDGE_SUM_WIDTH'(abs_grad(gy_r));

            if (border_sum_r) begin
                pixel_out <= '0;
            end else if (edge_sum_r > EDGE_SUM_WIDTH'((1 << DATA_WIDTH) - 1)) begin
                pixel_out <= '1;
            end else begin
                pixel_out <= edge_sum_r[DATA_WIDTH-1:0];
            end
        end
    end

endmodule
