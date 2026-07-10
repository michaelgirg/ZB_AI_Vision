`timescale 1 ns / 100 ps

// Module: sobel_core_tb
// Description:
//   Directed testbench for the pipelined Sobel core against Python golden
//   vectors.

module sobel_core_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int CORE_LATENCY = 3,
    parameter int TIMEOUT_CYCLES = 2000
);

    logic                  clk = 1'b0;
    logic                  rst;
    logic                  valid_in;
    logic                  border_in;
    logic [DATA_WIDTH-1:0] pixel_top_left;
    logic [DATA_WIDTH-1:0] pixel_top;
    logic [DATA_WIDTH-1:0] pixel_top_right;
    logic [DATA_WIDTH-1:0] pixel_left;
    logic [DATA_WIDTH-1:0] pixel_right;
    logic [DATA_WIDTH-1:0] pixel_bottom_left;
    logic [DATA_WIDTH-1:0] pixel_bottom;
    logic [DATA_WIDTH-1:0] pixel_bottom_right;
    logic                  valid_out;
    logic [DATA_WIDTH-1:0] pixel_out;

    logic [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] output_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_sobel.mem";

    int output_count = 0;
    int mismatch_count = 0;

`ifdef ENABLE_FUNCTIONAL_COVERAGE
    covergroup sobel_output_cg @(negedge clk);
        option.per_instance = 1;

        cp_valid : coverpoint valid_out {
            bins inactive = {1'b0};
            bins active = {1'b1};
        }

        cp_pixel : coverpoint pixel_out iff (valid_out) {
            bins zero = {8'd0};
            bins low = {[8'd1:8'd63]};
            bins mid = {[8'd64:8'd191]};
            bins high = {[8'd192:8'd254]};
            bins saturated = {8'd255};
        }
    endgroup

    sobel_output_cg sobel_cov = new();
`endif

    property valid_clears_after_reset;
        @(posedge clk) rst |=> !valid_out;
    endproperty

    property valid_output_known;
        @(posedge clk) disable iff (rst) valid_out |-> !$isunknown(pixel_out);
    endproperty

    assert property (valid_clears_after_reset)
        else $error("valid_out did not clear after reset.");

    assert property (valid_output_known)
        else $error("pixel_out is unknown while valid_out is asserted.");

    sobel_core #(
        .DATA_WIDTH(DATA_WIDTH)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .border_in(border_in),
        .pixel_top_left(pixel_top_left),
        .pixel_top(pixel_top),
        .pixel_top_right(pixel_top_right),
        .pixel_left(pixel_left),
        .pixel_right(pixel_right),
        .pixel_bottom_left(pixel_bottom_left),
        .pixel_bottom(pixel_bottom),
        .pixel_bottom_right(pixel_bottom_right),
        .valid_out(valid_out),
        .pixel_out(pixel_out)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    function automatic logic [DATA_WIDTH-1:0] pixel_at(input int row, input int col);
        if ((row < 0) || (row >= IMAGE_HEIGHT) || (col < 0) || (col >= IMAGE_WIDTH)) begin
            return '0;
        end

        return input_pixels[(row * IMAGE_WIDTH) + col];
    endfunction

    function automatic logic is_border(input int row, input int col);
        return (row == 0) || (row == IMAGE_HEIGHT - 1) || (col == 0) || (col == IMAGE_WIDTH - 1);
    endfunction

    task automatic drive_window(input int pixel_index);
        int row;
        int col;

        row = pixel_index / IMAGE_WIDTH;
        col = pixel_index % IMAGE_WIDTH;

        valid_in <= 1'b1;
        border_in <= is_border(row, col);
        pixel_top_left <= pixel_at(row - 1, col - 1);
        pixel_top <= pixel_at(row - 1, col);
        pixel_top_right <= pixel_at(row - 1, col + 1);
        pixel_left <= pixel_at(row, col - 1);
        pixel_right <= pixel_at(row, col + 1);
        pixel_bottom_left <= pixel_at(row + 1, col - 1);
        pixel_bottom <= pixel_at(row + 1, col);
        pixel_bottom_right <= pixel_at(row + 1, col + 1);
    endtask

    task automatic drive_idle();
        valid_in <= 1'b0;
        border_in <= 1'b0;
        pixel_top_left <= '0;
        pixel_top <= '0;
        pixel_top_right <= '0;
        pixel_left <= '0;
        pixel_right <= '0;
        pixel_bottom_left <= '0;
        pixel_bottom <= '0;
        pixel_bottom_right <= '0;
    endtask

    initial begin : provide_stimulus
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));

        $timeformat(-9, 0, " ns");
        $display("Sobel input MEM:    %s", input_mem_path);
        $display("Sobel expected MEM: %s", expected_mem_path);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_pixels);

        rst <= 1'b1;
        drive_idle();

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            output_pixels[i] = '0;
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            @(negedge clk);
            drive_window(i);
        end

        @(negedge clk);
        drive_idle();

        wait (output_count == IMAGE_PIXELS);
        repeat (2) @(posedge clk);

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            if (output_pixels[i] !== expected_pixels[i]) begin
                mismatch_count++;
                $error(
                    "Sobel mismatch at pixel %0d: actual=0x%02h expected=0x%02h",
                    i,
                    output_pixels[i],
                    expected_pixels[i]
                );
            end
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: Sobel core matched %0d pixels with %0d-cycle datapath latency.",
                IMAGE_PIXELS,
                CORE_LATENCY
            );
            $finish;
        end

        $fatal(1, "FAIL: Sobel core test found %0d mismatch(es).", mismatch_count);
    end

    initial begin : collect_output
        forever begin
            @(negedge clk);
            if (valid_out === 1'b1) begin
                if (output_count < IMAGE_PIXELS) begin
                    output_pixels[output_count] <= pixel_out;
                    output_count++;
                end else begin
                    $fatal(1, "FAIL: Sobel core produced more than %0d pixels.", IMAGE_PIXELS);
                end
            end
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule
