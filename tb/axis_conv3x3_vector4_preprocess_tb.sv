`timescale 1 ns / 100 ps

// Module: axis_conv3x3_vector4_preprocess_tb
// Description:
//Checks four packed learned feature channels with AXI4-Stream backpressure.

module axis_conv3x3_vector4_preprocess_tb;

    localparam int DATA_WIDTH = 32;
    localparam int KEEP_WIDTH = 4;
    localparam int PIXEL_WIDTH = 8;
    localparam int FILTERS = 4;
    localparam int TAPS = 9;
    localparam int IMAGE_WIDTH = 28;
    localparam int IMAGE_HEIGHT = 28;
    localparam int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int TIMEOUT_CYCLES = 40000;
    localparam logic [KEEP_WIDTH-1:0] PIXEL_KEEP = '1;

    logic aclk = 1'b0;
    logic aresetn;
    logic signed [7:0] conv_weights [0:FILTERS-1][0:TAPS-1];
    logic signed [31:0] conv_bias [0:FILTERS-1];
    logic [4:0] conv_shift [0:FILTERS-1];
    logic conv_relu_enable [0:FILTERS-1];
    logic clear_done;
    logic busy;
    logic done;
    logic packet_error;
    logic [31:0] processing_cycles;
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic [KEEP_WIDTH-1:0] s_axis_tkeep;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic s_axis_tlast;
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic [KEEP_WIDTH-1:0] m_axis_tkeep;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic m_axis_tlast;

    logic [PIXEL_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [DATA_WIDTH-1:0] expected_words [0:IMAGE_PIXELS-1];
    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_conv4.mem";
    int output_count = 0;
    int mismatch_count = 0;
    int ready_pattern_count = 0;
    logic ready_enable;
    logic was_stalled;
    logic [DATA_WIDTH-1:0] held_tdata;
    logic [KEEP_WIDTH-1:0] held_tkeep;
    logic held_tlast;

    axis_conv3x3_vector4_preprocess #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .FILTERS(FILTERS),
        .TAPS(TAPS),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .conv_weights(conv_weights),
        .conv_bias(conv_bias),
        .conv_shift(conv_shift),
        .conv_relu_enable(conv_relu_enable),
        .clear_done(clear_done),
        .busy(busy),
        .done(done),
        .packet_error(packet_error),
        .processing_cycles(processing_cycles),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    initial begin : generate_clock
        forever #5 aclk <= ~aclk;
    end

    task automatic initialize_parameters;
        int signed weights [0:FILTERS-1][0:TAPS-1] = '{
            '{29, 104, 127, -115, -76, 58, -78, -92, -114},
            '{13, -13, -116, -49, -79, 15, -127, -26, 11},
            '{48, -11, -127, -111, -76, -35, 39, 126, 94},
            '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
        };
        int signed biases [0:FILTERS-1] = '{11029, 17936, 257, -131};
        int shifts [0:FILTERS-1] = '{9, 7, 9, 9};

        for (int filter_index = 0; filter_index < FILTERS; filter_index++) begin
            for (int tap_index = 0; tap_index < TAPS; tap_index++) begin
                conv_weights[filter_index][tap_index] = 8'(weights[filter_index][tap_index]);
            end
            conv_bias[filter_index] = 32'(biases[filter_index]);
            conv_shift[filter_index] = 5'(shifts[filter_index]);
            conv_relu_enable[filter_index] = 1'b1;
        end
    endtask

    task automatic send_pixel(input int pixel_index);
        s_axis_tdata <= {{(DATA_WIDTH-PIXEL_WIDTH){1'b0}}, input_pixels[pixel_index]};
        s_axis_tkeep <= PIXEL_KEEP;
        s_axis_tvalid <= 1'b1;
        s_axis_tlast <= (pixel_index == IMAGE_PIXELS - 1);
        do begin
            @(posedge aclk);
        end while (s_axis_tready !== 1'b1);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        s_axis_tdata <= '0;
        if (((pixel_index % 23) == 8) || ((pixel_index % 59) == 17)) begin
            @(posedge aclk);
        end
    endtask

    initial begin : provide_stimulus
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));
        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_words);
        $display("Vector conv input MEM:    %s", input_mem_path);
        $display("Vector conv expected MEM: %s", expected_mem_path);

        initialize_parameters();
        aresetn <= 1'b0;
        clear_done <= 1'b0;
        s_axis_tdata <= '0;
        s_axis_tkeep <= '0;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        ready_enable <= 1'b0;
        repeat (5) @(posedge aclk);
        @(negedge aclk);
        aresetn <= 1'b1;
        ready_enable <= 1'b1;
        @(posedge aclk);

        for (int pixel_index = 0; pixel_index < IMAGE_PIXELS; pixel_index++) begin
            send_pixel(pixel_index);
        end

        wait (output_count == IMAGE_PIXELS);
        repeat (2) @(posedge aclk);
        if (done !== 1'b1) begin
            mismatch_count++;
            $error("done did not assert after the final vector output.");
        end
        if (busy !== 1'b0) begin
            mismatch_count++;
            $error("busy remained asserted after completion.");
        end
        if (packet_error !== 1'b0) begin
            mismatch_count++;
            $error("packet_error asserted for a legal vector packet.");
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: four-filter vector convolution matched %0d packed outputs in %0d cycles.",
                IMAGE_PIXELS,
                processing_cycles
            );
            $finish;
        end
        $fatal(1, "FAIL: vector convolution found %0d issue(s).", mismatch_count);
    end

    initial begin : drive_output_backpressure
        forever begin
            @(posedge aclk);
            if (!aresetn || !ready_enable) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (((ready_pattern_count % 17) == 4) ||
                         ((ready_pattern_count % 41) == 11)) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= ready_pattern_count + 1;
            end else begin
                m_axis_tready <= 1'b1;
                ready_pattern_count <= ready_pattern_count + 1;
            end
        end
    end

    initial begin : check_output_stream
        forever begin
            @(posedge aclk);
            if (!aresetn) begin
                output_count <= 0;
            end else if (m_axis_tvalid && m_axis_tready) begin
                if (output_count >= IMAGE_PIXELS) begin
                    mismatch_count++;
                    $error("extra vector output beat %0d", output_count);
                end else begin
                    if (m_axis_tdata !== expected_words[output_count]) begin
                        mismatch_count++;
                        $error(
                            "vector mismatch at %0d: actual=%08h expected=%08h",
                            output_count,
                            m_axis_tdata,
                            expected_words[output_count]
                        );
                    end
                    if (m_axis_tkeep !== PIXEL_KEEP) begin
                        mismatch_count++;
                        $error("TKEEP mismatch at output %0d", output_count);
                    end
                    if (m_axis_tlast !== (output_count == IMAGE_PIXELS - 1)) begin
                        mismatch_count++;
                        $error("TLAST mismatch at output %0d", output_count);
                    end
                end
                output_count <= output_count + 1;
            end
        end
    end

    initial begin : check_stall_stability
        was_stalled <= 1'b0;
        forever begin
            @(posedge aclk);
            if (!aresetn) begin
                was_stalled <= 1'b0;
            end else begin
                if (was_stalled && m_axis_tvalid && !m_axis_tready) begin
                    if ((m_axis_tdata !== held_tdata) ||
                        (m_axis_tkeep !== held_tkeep) ||
                        (m_axis_tlast !== held_tlast)) begin
                        mismatch_count++;
                        $error("vector output changed while stalled");
                    end
                end
                if (m_axis_tvalid && !m_axis_tready) begin
                    held_tdata <= m_axis_tdata;
                    held_tkeep <= m_axis_tkeep;
                    held_tlast <= m_axis_tlast;
                    was_stalled <= 1'b1;
                end else begin
                    was_stalled <= 1'b0;
                end
            end
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge aclk);
        $fatal(1, "FAIL: vector convolution timeout after %0d cycles", TIMEOUT_CYCLES);
    end

endmodule
