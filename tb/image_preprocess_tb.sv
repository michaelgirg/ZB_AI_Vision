`timescale 1 ns / 100 ps

// Module: image_preprocess_tb
// Description:
//Verifies threshold_core against Python-generated golden .mem files.

module image_preprocess_tb #(
    parameter int IMAGE_PIXELS = 784,
    parameter int DATA_WIDTH = 8,
    parameter int TIMEOUT_CYCLES = 2000
);

    logic                  clk = 1'b0;
    logic                  rst;
    logic                  valid_in;
    logic [DATA_WIDTH-1:0] pixel_in;
    logic [DATA_WIDTH-1:0] threshold;
    logic                  valid_out;
    logic [DATA_WIDTH-1:0] pixel_out;

    logic [DATA_WIDTH-1:0] input_image [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_image [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_pipe;
    logic                  expected_valid;

    // Override these with +INPUT_MEM=... and +EXPECTED_MEM=... when needed.
    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int output_count = 0;
    int mismatch_count = 0;

    threshold_core #(
        .DATA_WIDTH(DATA_WIDTH)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .pixel_in(pixel_in),
        .threshold(threshold),
        .valid_out(valid_out),
        .pixel_out(pixel_out)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    function automatic logic [DATA_WIDTH-1:0] model(
        input logic [DATA_WIDTH-1:0] pixel,
        input logic [DATA_WIDTH-1:0] threshold_value
    );
        return (pixel >= threshold_value) ? '1 : '0;
    endfunction

    initial begin : provide_stimulus
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));

        $timeformat(-9, 0, " ns");
        $display("Input MEM:    %s", input_mem_path);
        $display("Expected MEM: %s", expected_mem_path);

        $readmemh(input_mem_path, input_image);
        $readmemh(expected_mem_path, expected_image);

        rst       <= 1'b1;
        valid_in  <= 1'b0;
        pixel_in  <= '0;
        threshold <= 8'd128;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        @(posedge clk);

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            valid_in <= 1'b1;
            pixel_in <= input_image[i];
            @(posedge clk);
        end

        valid_in <= 1'b0;
        pixel_in <= '0;

        wait (output_count == IMAGE_PIXELS);
        repeat (2) @(posedge clk);

        if (mismatch_count == 0) begin
            $display("PASS: threshold output matched %0d pixels.", IMAGE_PIXELS);
            $finish;
        end else begin
            $fatal(1, "FAIL: %0d mismatches detected.", mismatch_count);
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

    initial begin : monitor_expected
        expected_pipe  <= '0;
        expected_valid <= 1'b0;

        forever begin
            @(posedge clk);
            if (rst) begin
                expected_pipe  <= '0;
                expected_valid <= 1'b0;
            end else begin
                expected_pipe  <= model(pixel_in, threshold);
                expected_valid <= valid_in;
            end
        end
    end

    initial begin : check_outputs
        forever begin
            @(posedge clk);

            if (rst === 1'b0) begin
                if (valid_out !== expected_valid) begin
                    mismatch_count++;
                    $error(
                        "valid_out mismatch at output %0d: actual=%0b expected=%0b",
                        output_count,
                        valid_out,
                        expected_valid
                    );
                end

                if (valid_out === 1'b1) begin
                    if (pixel_out !== expected_pipe) begin
                        mismatch_count++;
                        $error(
                            "model mismatch at output %0d: actual=0x%02h expected=0x%02h",
                            output_count,
                            pixel_out,
                            expected_pipe
                        );
                    end

                    if (pixel_out !== expected_image[output_count]) begin
                        mismatch_count++;
                        $error(
                            "golden file mismatch at output %0d: actual=0x%02h expected=0x%02h",
                            output_count,
                            pixel_out,
                            expected_image[output_count]
                        );
                    end

                    output_count++;
                end
            end
        end
    end

endmodule
