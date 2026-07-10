`timescale 1 ns / 100 ps

// Module: image_sobel_engine_tb
// Description:
//   Verifies the full-image Sobel engine against Python golden vectors.

module image_sobel_engine_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int ADDR_WIDTH = (IMAGE_PIXELS <= 1) ? 1 : $clog2(IMAGE_PIXELS),
    parameter int TIMEOUT_CYCLES = 3000
);

    logic                  clk = 1'b0;
    logic                  rst;
    logic                  start;
    logic                  busy;
    logic                  done;
    logic [31:0]           processing_cycles;
    logic                  read_en;
    logic [ADDR_WIDTH-1:0] read_addr;
    logic [DATA_WIDTH-1:0] read_data;
    logic                  write_en;
    logic [ADDR_WIDTH-1:0] write_addr;
    logic [DATA_WIDTH-1:0] write_data;

    logic [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] output_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_sobel.mem";

    int mismatch_count = 0;
    int write_count = 0;

    image_sobel_engine #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .busy(busy),
        .done(done),
        .processing_cycles(processing_cycles),
        .read_en(read_en),
        .read_addr(read_addr),
        .read_data(read_data),
        .write_en(write_en),
        .write_addr(write_addr),
        .write_data(write_data)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    initial begin : provide_stimulus
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));

        $timeformat(-9, 0, " ns");
        $display("Sobel engine input MEM:    %s", input_mem_path);
        $display("Sobel engine expected MEM: %s", expected_mem_path);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_pixels);

        rst <= 1'b1;
        start <= 1'b0;

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            output_pixels[i] = '0;
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        @(posedge clk);

        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (done === 1'b1);
        @(posedge clk);

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            if (output_pixels[i] !== expected_pixels[i]) begin
                mismatch_count++;
                $error(
                    "Sobel engine mismatch at pixel %0d: actual=0x%02h expected=0x%02h",
                    i,
                    output_pixels[i],
                    expected_pixels[i]
                );
            end
        end

        if (write_count !== IMAGE_PIXELS) begin
            mismatch_count++;
            $error("Expected %0d output writes, saw %0d.", IMAGE_PIXELS, write_count);
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: Sobel engine matched %0d pixels in %0d cycles.",
                IMAGE_PIXELS,
                processing_cycles
            );
            $finish;
        end

        $fatal(1, "FAIL: Sobel engine test found %0d issue(s).", mismatch_count);
    end

    initial begin : input_memory
        read_data <= '0;

        forever begin
            @(posedge clk);
            if (read_en === 1'b1) begin
                read_data <= input_pixels[read_addr];
            end
        end
    end

    initial begin : output_memory
        forever begin
            @(posedge clk);
            if (write_en === 1'b1) begin
                if (int'(write_addr) >= IMAGE_PIXELS) begin
                    $fatal(1, "FAIL: output write address %0d is out of range.", write_addr);
                end

                output_pixels[write_addr] <= write_data;
                write_count++;
            end
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule
