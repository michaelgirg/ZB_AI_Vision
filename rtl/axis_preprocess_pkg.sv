`timescale 1 ns / 100 ps

// Package: axis_preprocess_pkg
// Description:
//Shared constants for the future AXI4-Stream preprocessing datapath.

package axis_preprocess_pkg;

    localparam int AXIS_DATA_WIDTH = 32;
    localparam int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;
    localparam int AXIS_PIXEL_WIDTH = 8;

    localparam int AXIS_IMAGE_WIDTH = 28;
    localparam int AXIS_IMAGE_HEIGHT = 28;
    localparam int AXIS_IMAGE_PIXELS = AXIS_IMAGE_WIDTH * AXIS_IMAGE_HEIGHT;

    localparam int AXIS_MODE_THRESHOLD = 0;
    localparam int AXIS_MODE_SOBEL = 1;
    localparam int AXIS_MODE_CONV3X3 = 2;

    localparam logic [AXIS_KEEP_WIDTH-1:0] AXIS_PIXEL_KEEP = '1;

endpackage
