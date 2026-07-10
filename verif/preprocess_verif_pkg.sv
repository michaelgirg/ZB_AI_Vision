`timescale 1 ns / 100 ps

// Package: preprocess_verif_pkg
// Description:
//Shared constants and helper functions for preprocessing verification.

package preprocess_verif_pkg;

    localparam int DATA_WIDTH = 8;
    localparam int IMAGE_WIDTH = 28;
    localparam int IMAGE_HEIGHT = 28;
    localparam int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int AXI_ADDR_WIDTH = 8;
    localparam int TIMEOUT_CYCLES = 20000;

    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CTRL              = 8'h00;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STATUS            = 8'h04;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_THRESHOLD         = 8'h08;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_IMAGE_PIXELS      = 8'h0c;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PIXELS_PER_CYCLE  = 8'h10;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_INPUT_ADDR        = 8'h18;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_INPUT_WDATA       = 8'h1c;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_INPUT_WMASK       = 8'h20;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_ADDR       = 8'h24;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_RDATA      = 8'h28;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_MODE              = 8'h2c;

    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_SOBEL = 1;
    localparam int SOBEL_BORDER_PIXELS = (2 * IMAGE_WIDTH) + (2 * (IMAGE_HEIGHT - 2));
    localparam int THRESHOLD_EXPECTED_CYCLES = IMAGE_PIXELS + 2;
    localparam int SOBEL_EXPECTED_CYCLES = SOBEL_BORDER_PIXELS + IMAGE_PIXELS + 6;

    function automatic int expected_cycles(input int mode);
        if (mode == MODE_SOBEL) begin
            return SOBEL_EXPECTED_CYCLES;
        end

        return THRESHOLD_EXPECTED_CYCLES;
    endfunction

    function automatic string mode_name(input int mode);
        if (mode == MODE_SOBEL) begin
            return "sobel";
        end

        return "threshold";
    endfunction

endpackage
