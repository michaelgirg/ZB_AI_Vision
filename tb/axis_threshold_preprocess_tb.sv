`timescale 1 ns / 100 ps

// Module: axis_threshold_preprocess_tb
// Description:
//Verifies the AXI4-Stream threshold core with valid/ready stalls and golden pixels.

module axis_threshold_preprocess_tb #(
    parameter int DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int PIXEL_WIDTH = 8,
    parameter int IMAGE_PIXELS = 784,
    parameter int TIMEOUT_CYCLES = 4000
);

    localparam logic [KEEP_WIDTH-1:0] PIXEL_KEEP = '1;

    logic                         aclk = 1'b0;
    logic                         aresetn;
    logic [PIXEL_WIDTH-1:0]       threshold;
    logic                         clear_done;
    logic                         busy;
    logic                         done;
    logic                         packet_error;
    logic [31:0]                  processing_cycles;

    logic [DATA_WIDTH-1:0]        s_axis_tdata;
    logic [KEEP_WIDTH-1:0]        s_axis_tkeep;
    logic                         s_axis_tvalid;
    logic                         s_axis_tready;
    logic                         s_axis_tlast;

    logic [DATA_WIDTH-1:0]        m_axis_tdata;
    logic [KEEP_WIDTH-1:0]        m_axis_tkeep;
    logic                         m_axis_tvalid;
    logic                         m_axis_tready;
    logic                         m_axis_tlast;

    logic [PIXEL_WIDTH-1:0]       input_pixels [0:IMAGE_PIXELS-1];
    logic [PIXEL_WIDTH-1:0]       expected_pixels [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int output_count = 0;
    int mismatch_count = 0;

    logic [DATA_WIDTH-1:0] held_tdata;
    logic [KEEP_WIDTH-1:0] held_tkeep;
    logic                  held_tlast;
    logic                  was_stalled;
    logic                  ready_enable;
    int                    ready_pattern_count = 0;

    axis_threshold_preprocess #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .IMAGE_PIXELS(IMAGE_PIXELS)
    ) DUT (
        .aclk(aclk),
        .aresetn(aresetn),
        .threshold(threshold),
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

    task automatic send_pixel(
        input int pixel_index
    );
        begin
            s_axis_tdata  <= {{(DATA_WIDTH-PIXEL_WIDTH){1'b0}}, input_pixels[pixel_index]};
            s_axis_tkeep  <= PIXEL_KEEP;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (pixel_index == IMAGE_PIXELS - 1);

            do begin
                @(posedge aclk);
            end while (s_axis_tready !== 1'b1);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;

            if ((pixel_index % 37) == 13) begin
                @(posedge aclk);
            end
        end
    endtask

    initial begin : provide_stimulus
        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem_path));

        $timeformat(-9, 0, " ns");
        $display("AXI4-Stream threshold input MEM:    %s", input_mem_path);
        $display("AXI4-Stream threshold expected MEM: %s", expected_mem_path);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_pixels);

        aresetn       <= 1'b0;
        threshold     <= 8'd128;
        clear_done    <= 1'b0;
        s_axis_tdata  <= '0;
        s_axis_tkeep  <= '0;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
        ready_enable  <= 1'b0;

        repeat (5) @(posedge aclk);
        @(negedge aclk);
        aresetn <= 1'b1;
        ready_enable <= 1'b1;
        @(posedge aclk);

        for (int i = 0; i < IMAGE_PIXELS; i++) begin
            send_pixel(i);
        end

        wait (output_count == IMAGE_PIXELS);
        repeat (2) @(posedge aclk);

        if (done !== 1'b1) begin
            mismatch_count++;
            $error("done did not assert after final output beat.");
        end

        if (busy !== 1'b0) begin
            mismatch_count++;
            $error("busy remained asserted after final output beat.");
        end

        if (packet_error !== 1'b0) begin
            mismatch_count++;
            $error("packet_error asserted for a legal image packet.");
        end

        if (processing_cycles == 0) begin
            mismatch_count++;
            $error("processing_cycles was zero after completion.");
        end

        clear_done <= 1'b1;
        @(posedge aclk);
        clear_done <= 1'b0;
        @(posedge aclk);

        if (done !== 1'b0) begin
            mismatch_count++;
            $error("done did not clear after clear_done pulse.");
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: AXI4-Stream threshold matched %0d pixels in %0d cycles.",
                IMAGE_PIXELS,
                processing_cycles
            );
            $finish;
        end

        $fatal(1, "FAIL: AXI4-Stream threshold test found %0d issue(s).", mismatch_count);
    end

    initial begin : drive_output_backpressure
        forever begin
            @(posedge aclk);

            if (aresetn === 1'b0) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (ready_enable !== 1'b1) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (((ready_pattern_count % 23) == 5) ||
                         ((ready_pattern_count % 41) == 17)) begin
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

            if (aresetn === 1'b0) begin
                output_count <= 0;
            end else if ((m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b1)) begin
                if (output_count >= IMAGE_PIXELS) begin
                    mismatch_count++;
                    $error("Received extra output beat %0d.", output_count);
                end else begin
                    if (m_axis_tkeep !== PIXEL_KEEP) begin
                        mismatch_count++;
                        $error(
                            "tkeep mismatch at output %0d: actual=0x%0h expected=0x%0h",
                            output_count,
                            m_axis_tkeep,
                            PIXEL_KEEP
                        );
                    end

                    if (m_axis_tdata[DATA_WIDTH-1:PIXEL_WIDTH] !== '0) begin
                        mismatch_count++;
                        $error(
                            "upper tdata bits were nonzero at output %0d: actual=0x%0h",
                            output_count,
                            m_axis_tdata
                        );
                    end

                    if (m_axis_tdata[PIXEL_WIDTH-1:0] !== expected_pixels[output_count]) begin
                        mismatch_count++;
                        $error(
                            "pixel mismatch at output %0d: actual=0x%02h expected=0x%02h",
                            output_count,
                            m_axis_tdata[PIXEL_WIDTH-1:0],
                            expected_pixels[output_count]
                        );
                    end

                    if (m_axis_tlast !== (output_count == IMAGE_PIXELS - 1)) begin
                        mismatch_count++;
                        $error(
                            "tlast mismatch at output %0d: actual=%0b expected=%0b",
                            output_count,
                            m_axis_tlast,
                            (output_count == IMAGE_PIXELS - 1)
                        );
                    end
                end

                output_count <= output_count + 1;
            end
        end
    end

    initial begin : check_stall_stability
        was_stalled <= 1'b0;
        held_tdata  <= '0;
        held_tkeep  <= '0;
        held_tlast  <= 1'b0;

        forever begin
            @(posedge aclk);

            if (aresetn === 1'b0) begin
                was_stalled <= 1'b0;
            end else begin
                if (was_stalled && (m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b0)) begin
                    if ((m_axis_tdata !== held_tdata) ||
                        (m_axis_tkeep !== held_tkeep) ||
                        (m_axis_tlast !== held_tlast)) begin
                        mismatch_count++;
                        $error("AXI4-Stream output changed while stalled.");
                    end
                end

                if ((m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b0)) begin
                    held_tdata  <= m_axis_tdata;
                    held_tkeep  <= m_axis_tkeep;
                    held_tlast  <= m_axis_tlast;
                    was_stalled <= 1'b1;
                end else begin
                    was_stalled <= 1'b0;
                end
            end
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge aclk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule
