`timescale 1 ns / 100 ps

// Module: image_preprocess_buffered
// Description:
//   Adds input/output image buffers around the preprocessing engines.
//
// This is the integration step before AXI-Lite. The external "host" ports are
// intentionally simple so the future Zynq wrapper can map them to registers or
// BRAM control without changing the timing-aware engine.
//
// Mode:
//   0 = threshold
//   1 = Sobel

module image_preprocess_buffered #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int PIXELS_PER_CYCLE = 1,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int NUM_BEATS = (IMAGE_PIXELS + PIXELS_PER_CYCLE - 1) / PIXELS_PER_CYCLE,
    parameter int ADDR_WIDTH = (NUM_BEATS <= 1) ? 1 : $clog2(NUM_BEATS),
    parameter int BEAT_WIDTH = PIXELS_PER_CYCLE * DATA_WIDTH,
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                              clk,
    input  logic                              rst,
    input  logic                              start,
    input  logic [1:0]                        mode,
    input  logic [DATA_WIDTH-1:0]             threshold,
    output logic                              busy,
    output logic                              done,
    output logic [CYCLE_COUNT_WIDTH-1:0]      processing_cycles,

    input  logic                              host_input_we,
    input  logic [ADDR_WIDTH-1:0]             host_input_addr,
    input  logic [BEAT_WIDTH-1:0]             host_input_wdata,
    input  logic [PIXELS_PER_CYCLE-1:0]       host_input_wmask,

    input  logic                              host_output_re,
    input  logic [ADDR_WIDTH-1:0]             host_output_addr,
    output logic [BEAT_WIDTH-1:0]             host_output_rdata
);

    localparam logic [1:0] MODE_THRESHOLD = 2'd0;
    localparam logic [1:0] MODE_SOBEL     = 2'd1;

    logic                           threshold_start;
    logic                           threshold_busy;
    logic                           threshold_done;
    logic [CYCLE_COUNT_WIDTH-1:0]   threshold_cycles;
    logic                           threshold_read_en;
    logic [ADDR_WIDTH-1:0]          threshold_read_addr;
    logic [BEAT_WIDTH-1:0]          threshold_read_data;
    logic                           threshold_write_en;
    logic [ADDR_WIDTH-1:0]          threshold_write_addr;
    logic [PIXELS_PER_CYCLE-1:0]    threshold_write_mask;
    logic [BEAT_WIDTH-1:0]          threshold_write_data;

    logic                           sobel_start;
    logic                           sobel_busy;
    logic                           sobel_done;
    logic [CYCLE_COUNT_WIDTH-1:0]   sobel_cycles;
    logic                           sobel_read_en;
    logic [ADDR_WIDTH-1:0]          sobel_read_addr;
    logic [DATA_WIDTH-1:0]          sobel_read_data;
    logic                           sobel_write_en;
    logic [ADDR_WIDTH-1:0]          sobel_write_addr;
    logic [DATA_WIDTH-1:0]          sobel_write_data;

    logic [1:0]                     mode_r;
    logic                           output_mem_we;
    logic [ADDR_WIDTH-1:0]          output_mem_waddr;
    logic [PIXELS_PER_CYCLE-1:0]    output_mem_wmask;
    logic [BEAT_WIDTH-1:0]          output_mem_wdata;

    (* ram_style = "block" *) logic [BEAT_WIDTH-1:0] input_mem [0:NUM_BEATS-1];
    (* ram_style = "block" *) logic [BEAT_WIDTH-1:0] output_mem [0:NUM_BEATS-1];

    assign threshold_start = start && (mode == MODE_THRESHOLD);
    assign sobel_start = start && (mode == MODE_SOBEL);
    assign busy = threshold_busy || sobel_busy;
    assign done = threshold_done || sobel_done;
    assign processing_cycles = (mode_r == MODE_SOBEL) ? sobel_cycles : threshold_cycles;

    image_preprocess_engine #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(PIXELS_PER_CYCLE),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) engine (
        .clk(clk),
        .rst(rst),
        .start(threshold_start),
        .threshold(threshold),
        .busy(threshold_busy),
        .done(threshold_done),
        .processing_cycles(threshold_cycles),
        .read_en(threshold_read_en),
        .read_addr(threshold_read_addr),
        .read_data(threshold_read_data),
        .write_en(threshold_write_en),
        .write_addr(threshold_write_addr),
        .write_mask(threshold_write_mask),
        .write_data(threshold_write_data)
    );

    image_sobel_engine #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) sobel_engine (
        .clk(clk),
        .rst(rst),
        .start(sobel_start),
        .busy(sobel_busy),
        .done(sobel_done),
        .processing_cycles(sobel_cycles),
        .read_en(sobel_read_en),
        .read_addr(sobel_read_addr),
        .read_data(sobel_read_data),
        .write_en(sobel_write_en),
        .write_addr(sobel_write_addr),
        .write_data(sobel_write_data)
    );

`ifndef SYNTHESIS
    initial begin
        if (PIXELS_PER_CYCLE != 1) begin
            $fatal(1, "Sobel mode currently requires PIXELS_PER_CYCLE = 1.");
        end
    end
`endif

    always_ff @(posedge clk) begin
        if (rst) begin
            mode_r <= MODE_THRESHOLD;
        end else if (start) begin
            mode_r <= mode;
        end
    end

    always_comb begin
        output_mem_we = 1'b0;
        output_mem_waddr = '0;
        output_mem_wmask = '0;
        output_mem_wdata = '0;

        if (threshold_write_en) begin
            output_mem_we = 1'b1;
            output_mem_waddr = threshold_write_addr;
            output_mem_wmask = threshold_write_mask;
            output_mem_wdata = threshold_write_data;
        end else if (sobel_write_en) begin
            output_mem_we = 1'b1;
            output_mem_waddr = sobel_write_addr;
            output_mem_wmask[0] = 1'b1;
            output_mem_wdata[DATA_WIDTH-1:0] = sobel_write_data;
        end
    end

    always_ff @(posedge clk) begin
        if (host_input_we) begin
            for (int lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin
                if (host_input_wmask[lane]) begin
                    input_mem[host_input_addr][lane*DATA_WIDTH +: DATA_WIDTH] <=
                        host_input_wdata[lane*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end

        if (threshold_read_en) begin
            threshold_read_data <= input_mem[threshold_read_addr];
        end

        if (sobel_read_en) begin
            sobel_read_data <= input_mem[sobel_read_addr][DATA_WIDTH-1:0];
        end
    end

    always_ff @(posedge clk) begin
        if (output_mem_we) begin
            for (int lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin
                if (output_mem_wmask[lane]) begin
                    output_mem[output_mem_waddr][lane*DATA_WIDTH +: DATA_WIDTH] <=
                        output_mem_wdata[lane*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end

        if (host_output_re) begin
            host_output_rdata <= output_mem[host_output_addr];
        end
    end

endmodule
