`timescale 1 ns / 100 ps

// Module: image_preprocess_buffered_tb
// Description:
//Verifies the buffered preprocessing block against Python golden vectors.

module image_preprocess_buffered_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int PIXELS_PER_CYCLE = 1,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int NUM_BEATS = (IMAGE_PIXELS + PIXELS_PER_CYCLE - 1) / PIXELS_PER_CYCLE,
    parameter int ADDR_WIDTH = (NUM_BEATS <= 1) ? 1 : $clog2(NUM_BEATS),
    parameter int BEAT_WIDTH = PIXELS_PER_CYCLE * DATA_WIDTH,
    parameter int TIMEOUT_CYCLES = 4000
);

    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_SOBEL = 1;
    localparam int SOBEL_BORDER_PIXELS = (2 * IMAGE_WIDTH) + (2 * (IMAGE_HEIGHT - 2));
    localparam int SOBEL_EXPECTED_CYCLES = SOBEL_BORDER_PIXELS + IMAGE_PIXELS + 6;

    logic                         clk = 1'b0;
    logic                         rst;
    logic                         start;
    logic [1:0]                   mode;
    logic [DATA_WIDTH-1:0]        threshold;
    logic                         busy;
    logic                         done;
    logic [31:0]                  processing_cycles;
    logic                         host_input_we;
    logic [ADDR_WIDTH-1:0]        host_input_addr;
    logic [BEAT_WIDTH-1:0]        host_input_wdata;
    logic [PIXELS_PER_CYCLE-1:0]  host_input_wmask;
    logic                         host_output_re;
    logic [ADDR_WIDTH-1:0]        host_output_addr;
    logic [BEAT_WIDTH-1:0]        host_output_rdata;

    logic [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int mismatch_count = 0;
    int preprocess_mode = MODE_THRESHOLD;

    image_preprocess_buffered #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(PIXELS_PER_CYCLE)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .start(start),
        .mode(mode),
        .threshold(threshold),
        .busy(busy),
        .done(done),
        .processing_cycles(processing_cycles),
        .host_input_we(host_input_we),
        .host_input_addr(host_input_addr),
        .host_input_wdata(host_input_wdata),
        .host_input_wmask(host_input_wmask),
        .host_output_re(host_output_re),
        .host_output_addr(host_output_addr),
        .host_output_rdata(host_output_rdata)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    function automatic logic [PIXELS_PER_CYCLE-1:0] beat_mask(input int beat_index);
        logic [PIXELS_PER_CYCLE-1:0] mask;
        int pixel_index;

        mask = '0;
        for (int lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin
            pixel_index = beat_index * PIXELS_PER_CYCLE + lane;
            if (pixel_index < IMAGE_PIXELS) begin
                mask[lane] = 1'b1;
            end
        end

        return mask;
    endfunction

    function automatic logic [BEAT_WIDTH-1:0] pack_input_beat(input int beat_index);
        logic [BEAT_WIDTH-1:0] beat;
        int pixel_index;

        beat = '0;
        for (int lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin
            pixel_index = beat_index * PIXELS_PER_CYCLE + lane;
            if (pixel_index < IMAGE_PIXELS) begin
                beat[lane*DATA_WIDTH +: DATA_WIDTH] = input_pixels[pixel_index];
            end
        end

        return beat;
    endfunction

    task automatic check_output_beat(input int beat_index);
        int pixel_index;

        for (int lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin
            pixel_index = beat_index * PIXELS_PER_CYCLE + lane;
            if (pixel_index < IMAGE_PIXELS) begin
                if (host_output_rdata[lane*DATA_WIDTH +: DATA_WIDTH] !== expected_pixels[pixel_index]) begin
                    mismatch_count++;
                    $error(
                        "Buffered mismatch at pixel %0d: actual=0x%02h expected=0x%02h",
                        pixel_index,
                        host_output_rdata[lane*DATA_WIDTH +: DATA_WIDTH],
                        expected_pixels[pixel_index]
                    );
                end
            end
        end
    endtask

    initial begin : provide_stimulus
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));
        void'($value$plusargs("MODE=%d", preprocess_mode));

        $timeformat(-9, 0, " ns");
        $display("Buffered input MEM:    %s", input_mem_path);
        $display("Buffered expected MEM: %s", expected_mem_path);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_pixels);

        rst <= 1'b1;
        start <= 1'b0;
        mode <= 2'(preprocess_mode);
        threshold <= 8'd128;
        host_input_we <= 1'b0;
        host_input_addr <= '0;
        host_input_wdata <= '0;
        host_input_wmask <= '0;
        host_output_re <= 1'b0;
        host_output_addr <= '0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        for (int beat = 0; beat < NUM_BEATS; beat++) begin
            @(negedge clk);
            host_input_we <= 1'b1;
            host_input_addr <= ADDR_WIDTH'(beat);
            host_input_wdata <= pack_input_beat(beat);
            host_input_wmask <= beat_mask(beat);
        end

        @(negedge clk);
        host_input_we <= 1'b0;
        host_input_wdata <= '0;
        host_input_wmask <= '0;

        @(negedge clk);
        start <= 1'b1;
        @(negedge clk);
        start <= 1'b0;

        wait (done === 1'b1);
        @(posedge clk);

        for (int beat = 0; beat < NUM_BEATS; beat++) begin
            @(negedge clk);
            host_output_re <= 1'b1;
            host_output_addr <= ADDR_WIDTH'(beat);

            if (beat > 0) begin
                check_output_beat(beat - 1);
            end
        end

        @(negedge clk);
        check_output_beat(NUM_BEATS - 1);
        host_output_re <= 1'b0;

        if (preprocess_mode == MODE_SOBEL) begin
            if (processing_cycles !== 32'(SOBEL_EXPECTED_CYCLES)) begin
                mismatch_count++;
                $error(
                    "Expected %0d Sobel processing cycles, saw %0d.",
                    SOBEL_EXPECTED_CYCLES,
                    processing_cycles
                );
            end
        end else if (processing_cycles !== 32'(NUM_BEATS + 2)) begin
            mismatch_count++;
            $error(
                "Expected %0d processing cycles, saw %0d.",
                NUM_BEATS + 2,
                processing_cycles
            );
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: buffered engine matched %0d pixels in %0d cycles.",
                IMAGE_PIXELS,
                processing_cycles
            );
            $finish;
        end

        $fatal(1, "FAIL: buffered test found %0d issue(s).", mismatch_count);
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule
