`timescale 1 ns / 100 ps

// Module: image_preprocess_reg_block_tb
// Description:
//   Verifies the register-controlled preprocessing block against Python
//   golden vectors using the planned software-visible register flow.

module image_preprocess_reg_block_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int PIXELS_PER_CYCLE = 1,
    parameter int REG_ADDR_WIDTH = 8,
    parameter int REG_DATA_WIDTH = 32,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int NUM_BEATS = (IMAGE_PIXELS + PIXELS_PER_CYCLE - 1) / PIXELS_PER_CYCLE,
    parameter int ADDR_WIDTH = (NUM_BEATS <= 1) ? 1 : $clog2(NUM_BEATS),
    parameter int BEAT_WIDTH = PIXELS_PER_CYCLE * DATA_WIDTH,
    parameter int TIMEOUT_CYCLES = 15000
);

    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_CTRL              = 8'h00;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_STATUS            = 8'h04;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_THRESHOLD         = 8'h08;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_IMAGE_PIXELS      = 8'h0c;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_PIXELS_PER_CYCLE  = 8'h10;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_INPUT_ADDR        = 8'h18;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_INPUT_WDATA       = 8'h1c;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_INPUT_WMASK       = 8'h20;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_OUTPUT_ADDR       = 8'h24;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_OUTPUT_RDATA      = 8'h28;
    localparam logic [REG_ADDR_WIDTH-1:0] ADDR_MODE              = 8'h2c;

    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_SOBEL = 1;
    localparam int SOBEL_BORDER_PIXELS = (2 * IMAGE_WIDTH) + (2 * (IMAGE_HEIGHT - 2));
    localparam int SOBEL_EXPECTED_CYCLES = SOBEL_BORDER_PIXELS + IMAGE_PIXELS + 6;

    logic                            clk = 1'b0;
    logic                            rst;
    logic                            reg_write_en;
    logic [REG_ADDR_WIDTH-1:0]       reg_write_addr;
    logic [REG_DATA_WIDTH-1:0]       reg_write_data;
    logic                            reg_read_en;
    logic [REG_ADDR_WIDTH-1:0]       reg_read_addr;
    logic [REG_DATA_WIDTH-1:0]       reg_read_data;

    logic [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int mismatch_count = 0;
    int preprocess_mode = MODE_THRESHOLD;

    image_preprocess_reg_block #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(PIXELS_PER_CYCLE),
        .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
        .REG_DATA_WIDTH(REG_DATA_WIDTH)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .reg_write_en(reg_write_en),
        .reg_write_addr(reg_write_addr),
        .reg_write_data(reg_write_data),
        .reg_read_en(reg_read_en),
        .reg_read_addr(reg_read_addr),
        .reg_read_data(reg_read_data)
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

    task automatic write_reg(
        input logic [REG_ADDR_WIDTH-1:0] addr,
        input logic [REG_DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        reg_write_en <= 1'b1;
        reg_write_addr <= addr;
        reg_write_data <= data;
        reg_read_en <= 1'b0;
        @(negedge clk);
        reg_write_en <= 1'b0;
        reg_write_addr <= '0;
        reg_write_data <= '0;
    endtask

    task automatic read_reg(
        input logic [REG_ADDR_WIDTH-1:0] addr,
        output logic [REG_DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        reg_read_en <= 1'b1;
        reg_read_addr <= addr;
        reg_write_en <= 1'b0;
        @(posedge clk);
        data = reg_read_data;
        @(negedge clk);
        reg_read_en <= 1'b0;
        reg_read_addr <= '0;
    endtask

    task automatic check_output_beat(input int beat_index);
        logic [REG_DATA_WIDTH-1:0] read_value;
        int pixel_index;

        write_reg(ADDR_OUTPUT_ADDR, REG_DATA_WIDTH'(beat_index));
        read_reg(ADDR_OUTPUT_RDATA, read_value);

        for (int lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin
            pixel_index = beat_index * PIXELS_PER_CYCLE + lane;
            if (pixel_index < IMAGE_PIXELS) begin
                if (read_value[lane*DATA_WIDTH +: DATA_WIDTH] !== expected_pixels[pixel_index]) begin
                    mismatch_count++;
                    $error(
                        "Register block mismatch at pixel %0d: actual=0x%02h expected=0x%02h",
                        pixel_index,
                        read_value[lane*DATA_WIDTH +: DATA_WIDTH],
                        expected_pixels[pixel_index]
                    );
                end
            end
        end
    endtask

    initial begin : provide_stimulus
        logic [REG_DATA_WIDTH-1:0] read_value;
        logic [REG_DATA_WIDTH-1:0] status_value;

        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));
        void'($value$plusargs("MODE=%d", preprocess_mode));

        $timeformat(-9, 0, " ns");
        $display("Register block input MEM:    %s", input_mem_path);
        $display("Register block expected MEM: %s", expected_mem_path);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_pixels);

        rst <= 1'b1;
        reg_write_en <= 1'b0;
        reg_write_addr <= '0;
        reg_write_data <= '0;
        reg_read_en <= 1'b0;
        reg_read_addr <= '0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;

        read_reg(ADDR_IMAGE_PIXELS, read_value);
        if (read_value !== REG_DATA_WIDTH'(IMAGE_PIXELS)) begin
            mismatch_count++;
            $error("IMAGE_PIXELS register mismatch: actual=%0d expected=%0d", read_value, IMAGE_PIXELS);
        end

        read_reg(ADDR_PIXELS_PER_CYCLE, read_value);
        if (read_value !== REG_DATA_WIDTH'(PIXELS_PER_CYCLE)) begin
            mismatch_count++;
            $error(
                "PIXELS_PER_CYCLE register mismatch: actual=%0d expected=%0d",
                read_value,
                PIXELS_PER_CYCLE
            );
        end

        write_reg(ADDR_THRESHOLD, REG_DATA_WIDTH'(128));
        write_reg(ADDR_MODE, REG_DATA_WIDTH'(preprocess_mode));

        for (int beat = 0; beat < NUM_BEATS; beat++) begin
            write_reg(ADDR_INPUT_ADDR, REG_DATA_WIDTH'(beat));
            write_reg(ADDR_INPUT_WMASK, REG_DATA_WIDTH'(beat_mask(beat)));
            write_reg(ADDR_INPUT_WDATA, REG_DATA_WIDTH'(pack_input_beat(beat)));
        end

        write_reg(ADDR_CTRL, 32'h0000_0001);

        status_value = '0;
        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            read_reg(ADDR_STATUS, status_value);
            if (status_value[1] === 1'b1) begin
                break;
            end
        end

        if (status_value[1] !== 1'b1) begin
            $fatal(1, "FAIL: register block did not report done.");
        end

        read_reg(ADDR_PROCESSING_CYCLES, read_value);
        if (preprocess_mode == MODE_SOBEL) begin
            if (read_value !== REG_DATA_WIDTH'(SOBEL_EXPECTED_CYCLES)) begin
                mismatch_count++;
                $error(
                    "Expected %0d Sobel processing cycles, saw %0d.",
                    SOBEL_EXPECTED_CYCLES,
                    read_value
                );
            end
        end else if (read_value !== REG_DATA_WIDTH'(NUM_BEATS + 2)) begin
            mismatch_count++;
            $error(
                "Expected %0d processing cycles, saw %0d.",
                NUM_BEATS + 2,
                read_value
            );
        end

        for (int beat = 0; beat < NUM_BEATS; beat++) begin
            check_output_beat(beat);
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: register block matched %0d pixels in %0d engine cycles.",
                IMAGE_PIXELS,
                read_value
            );
            $finish;
        end

        $fatal(1, "FAIL: register block test found %0d issue(s).", mismatch_count);
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule
