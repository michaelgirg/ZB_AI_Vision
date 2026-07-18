`timescale 1 ns / 100 ps

module axis_conv3x3_scalable_preprocess_tb #(
    parameter int PARALLEL_FILTERS = 4
);
    localparam int IMAGE_PIXELS = 784;
    localparam logic [3:0] EXPECTED_KEEP = 4'((1 << PARALLEL_FILTERS) - 1);
    localparam logic [31:0] EXPECTED_MASK = 32'((64'(1) << (8 * PARALLEL_FILTERS)) - 1);

    logic clk = 1'b0;
    logic rstn;
    logic signed [7:0] weights [0:PARALLEL_FILTERS-1][0:8];
    logic signed [31:0] biases [0:PARALLEL_FILTERS-1];
    logic [4:0] shifts [0:PARALLEL_FILTERS-1];
    logic relu_enables [0:PARALLEL_FILTERS-1];
    logic clear_done;
    logic busy;
    logic done;
    logic packet_error;
    logic [31:0] processing_cycles;
    logic [31:0] s_tdata;
    logic [3:0] s_tkeep;
    logic s_tvalid;
    logic s_tready;
    logic s_tlast;
    logic [31:0] m_tdata;
    logic [3:0] m_tkeep;
    logic m_tvalid;
    logic m_tready;
    logic m_tlast;

    logic [7:0] input_pixels [0:IMAGE_PIXELS-1];
    logic [31:0] expected_words [0:IMAGE_PIXELS-1];
    int unsigned output_count;
    int unsigned mismatch_count;
    int unsigned ready_count;

    localparam int signed ALL_WEIGHTS [0:3][0:8] = '{
        '{29, 104, 127, -115, -76, 58, -78, -92, -114},
        '{13, -13, -116, -49, -79, 15, -127, -26, 11},
        '{48, -11, -127, -111, -76, -35, 39, 126, 94},
        '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
    };
    localparam int signed ALL_BIASES [0:3] = '{11029, 17936, 257, -131};
    localparam int ALL_SHIFTS [0:3] = '{9, 7, 9, 9};

    always #5 clk = ~clk;

    axis_conv3x3_scalable_preprocess #(
        .PARALLEL_FILTERS(PARALLEL_FILTERS)
    ) DUT (
        .aclk(clk),
        .aresetn(rstn),
        .conv_weights(weights),
        .conv_bias(biases),
        .conv_shift(shifts),
        .conv_relu_enable(relu_enables),
        .clear_done(clear_done),
        .busy(busy),
        .done(done),
        .packet_error(packet_error),
        .processing_cycles(processing_cycles),
        .s_axis_tdata(s_tdata),
        .s_axis_tkeep(s_tkeep),
        .s_axis_tvalid(s_tvalid),
        .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast),
        .m_axis_tdata(m_tdata),
        .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast)
    );

    task automatic send_pixel(input int index);
        s_tdata <= {24'd0, input_pixels[index]};
        s_tkeep <= 4'hf;
        s_tvalid <= 1'b1;
        s_tlast <= (index == IMAGE_PIXELS - 1);
        do @(posedge clk); while (!s_tready);
        s_tvalid <= 1'b0;
        s_tlast <= 1'b0;
        if (((index % 29) == 7) || ((index % 61) == 13)) @(posedge clk);
    endtask

    initial begin
        $readmemh("generated/test_vectors/sample_000_input.mem", input_pixels);
        $readmemh("generated/test_vectors/sample_000_conv4.mem", expected_words);
        for (int filter_index = 0; filter_index < PARALLEL_FILTERS; filter_index++) begin
            biases[filter_index] = ALL_BIASES[filter_index];
            shifts[filter_index] = ALL_SHIFTS[filter_index];
            relu_enables[filter_index] = 1'b1;
            for (int tap_index = 0; tap_index < 9; tap_index++) begin
                weights[filter_index][tap_index] = ALL_WEIGHTS[filter_index][tap_index];
            end
        end

        rstn = 1'b0;
        clear_done = 1'b0;
        s_tdata = '0;
        s_tkeep = '0;
        s_tvalid = 1'b0;
        s_tlast = 1'b0;
        m_tready = 1'b0;
        output_count = 0;
        mismatch_count = 0;
        ready_count = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn = 1'b1;

        for (int index = 0; index < IMAGE_PIXELS; index++) send_pixel(index);
        wait (output_count == IMAGE_PIXELS);
        repeat (3) @(posedge clk);

        if (!done || busy || packet_error) begin
            mismatch_count++;
            $error("terminal state done=%0b busy=%0b packet_error=%0b", done, busy, packet_error);
        end
        if (mismatch_count == 0) begin
            $display(
                "PASS: scalable convolution lanes=%0d matched %0d outputs in %0d cycles.",
                PARALLEL_FILTERS,
                IMAGE_PIXELS,
                processing_cycles
            );
            $finish;
        end
        $fatal(1, "FAIL: scalable lanes=%0d found %0d issue(s)", PARALLEL_FILTERS, mismatch_count);
    end

    always @(posedge clk) begin
        if (!rstn) begin
            m_tready <= 1'b0;
            ready_count <= 0;
        end else begin
            m_tready <= !(((ready_count % 19) == 5) || ((ready_count % 43) == 17));
            ready_count <= ready_count + 1;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            output_count <= 0;
        end else if (m_tvalid && m_tready) begin
            if ((m_tdata & EXPECTED_MASK) !== (expected_words[output_count] & EXPECTED_MASK)) begin
                mismatch_count++;
                $error(
                    "lanes=%0d data mismatch at %0d actual=%08h expected=%08h mask=%08h",
                    PARALLEL_FILTERS,
                    output_count,
                    m_tdata,
                    expected_words[output_count],
                    EXPECTED_MASK
                );
            end
            if ((m_tdata & ~EXPECTED_MASK) !== 0) begin
                mismatch_count++;
                $error("lanes=%0d nonzero inactive output byte at %0d", PARALLEL_FILTERS, output_count);
            end
            if (m_tkeep !== EXPECTED_KEEP) begin
                mismatch_count++;
                $error("lanes=%0d TKEEP=%h expected=%h", PARALLEL_FILTERS, m_tkeep, EXPECTED_KEEP);
            end
            if (m_tlast !== (output_count == IMAGE_PIXELS - 1)) begin
                mismatch_count++;
                $error("lanes=%0d TLAST mismatch at %0d", PARALLEL_FILTERS, output_count);
            end
            output_count <= output_count + 1;
        end
    end

    initial begin
        repeat (50000) @(posedge clk);
        $fatal(1, "FAIL: scalable lanes=%0d timeout", PARALLEL_FILTERS);
    end
endmodule
