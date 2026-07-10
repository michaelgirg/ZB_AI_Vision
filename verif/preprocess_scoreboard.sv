`timescale 1 ns / 100 ps

// Module: preprocess_scoreboard
// Description:
//Pixel scoreboard shared by verification tests.

module preprocess_scoreboard #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_PIXELS = 784
);

    int mismatch_count;

    task automatic reset();
        mismatch_count = 0;
    endtask

    task automatic check_pixel(
        input int pixel_index,
        input logic [DATA_WIDTH-1:0] actual,
        input logic [DATA_WIDTH-1:0] expected
    );
        if (actual !== expected) begin
            mismatch_count++;
            $error(
                "Pixel mismatch at %0d: actual=0x%02h expected=0x%02h",
                pixel_index,
                actual,
                expected
            );
        end
    endtask

    function automatic int errors();
        return mismatch_count;
    endfunction

    task automatic report(input string test_name);
        if (mismatch_count == 0) begin
            $display("PASS: %s matched %0d pixels.", test_name, IMAGE_PIXELS);
        end else begin
            $fatal(1, "FAIL: %s found %0d pixel mismatch(es).", test_name, mismatch_count);
        end
    endtask

endmodule
