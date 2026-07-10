// Module: image_preprocess_engine
// Description:
//   Full-image threshold preprocessing engine.
//
// Timing intent:
//   - one read beat issued per cycle while active
//   - one processed beat written per cycle after pipeline fill
//   - countdown counters for done detection
//   - reset control/valid state, not bulky datapath values
//
// Memory is intentionally outside this module. That keeps this engine reusable
// for testbench memories, BRAM wrappers, AXI-Lite buffers, or future DMA.

module image_preprocess_engine #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int PIXELS_PER_CYCLE = 1,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int NUM_BEATS = (IMAGE_PIXELS + PIXELS_PER_CYCLE - 1) / PIXELS_PER_CYCLE,
    parameter int ADDR_WIDTH = (NUM_BEATS <= 1) ? 1 : $clog2(NUM_BEATS),
    parameter int COUNT_WIDTH = (NUM_BEATS <= 1) ? 1 : $clog2(NUM_BEATS + 1),
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                                      clk,
    input  logic                                      rst,
    input  logic                                      start,
    input  logic [DATA_WIDTH-1:0]                     threshold,
    output logic                                      busy,
    output logic                                      done,
    output logic [CYCLE_COUNT_WIDTH-1:0]              processing_cycles,

    output logic                                      read_en,
    output logic [ADDR_WIDTH-1:0]                     read_addr,
    input  logic [PIXELS_PER_CYCLE*DATA_WIDTH-1:0]    read_data,

    output logic                                      write_en,
    output logic [ADDR_WIDTH-1:0]                     write_addr,
    output logic [PIXELS_PER_CYCLE-1:0]               write_mask,
    output logic [PIXELS_PER_CYCLE*DATA_WIDTH-1:0]    write_data
);

    localparam int BEAT_WIDTH = PIXELS_PER_CYCLE * DATA_WIDTH;
    localparam int LAST_BEAT_PIXELS = IMAGE_PIXELS - ((NUM_BEATS - 1) * PIXELS_PER_CYCLE);

    typedef enum logic {
        STATE_IDLE,
        STATE_RUN
    } state_t;

    state_t state_r;

    logic [DATA_WIDTH-1:0]        threshold_r;
    logic [ADDR_WIDTH-1:0]        next_read_addr_r;
    logic [ADDR_WIDTH-1:0]        issued_read_addr_r;
    logic [ADDR_WIDTH-1:0]        threshold_addr_r;
    logic [COUNT_WIDTH-1:0]       reads_remaining_r;
    logic [COUNT_WIDTH-1:0]       writes_remaining_r;
    logic [CYCLE_COUNT_WIDTH-1:0] cycle_count_r;
    logic [PIXELS_PER_CYCLE-1:0]  issued_read_mask_r;
    logic [PIXELS_PER_CYCLE-1:0]  threshold_mask_r;
    logic                         read_valid_r;
    logic [PIXELS_PER_CYCLE-1:0]  threshold_valid;

    logic start_accepted;
    logic issue_read;

    assign start_accepted = (state_r == STATE_IDLE) && start;
    assign issue_read = start_accepted || ((state_r == STATE_RUN) && (reads_remaining_r != '0));

    assign busy = (state_r == STATE_RUN) || start_accepted;
    assign read_en = issue_read;
    assign read_addr = start_accepted ? '0 : next_read_addr_r;

    assign write_en = threshold_valid[0];
    assign write_addr = threshold_addr_r;
    assign write_mask = write_en ? threshold_mask_r : '0;

    function automatic logic [PIXELS_PER_CYCLE-1:0] beat_mask(input logic [ADDR_WIDTH-1:0] addr);
        logic [PIXELS_PER_CYCLE-1:0] mask;
        mask = '1;

        if (LAST_BEAT_PIXELS < PIXELS_PER_CYCLE) begin
            if (addr == ADDR_WIDTH'(NUM_BEATS - 1)) begin
                mask = '0;
                for (int i = 0; i < LAST_BEAT_PIXELS; i++) begin
                    mask[i] = 1'b1;
                end
            end
        end

        return mask;
    endfunction

    genvar lane;
    generate
        for (lane = 0; lane < PIXELS_PER_CYCLE; lane++) begin : g_threshold_lanes
            threshold_core #(
                .DATA_WIDTH(DATA_WIDTH)
            ) threshold_lane (
                .clk(clk),
                .rst(rst),
                .valid_in(read_valid_r),
                .pixel_in(read_data[lane*DATA_WIDTH +: DATA_WIDTH]),
                .threshold(threshold_r),
                .valid_out(threshold_valid[lane]),
                .pixel_out(write_data[lane*DATA_WIDTH +: DATA_WIDTH])
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst) begin
            state_r <= STATE_IDLE;
            done <= 1'b0;
            processing_cycles <= '0;
            next_read_addr_r <= '0;
            issued_read_addr_r <= '0;
            threshold_addr_r <= '0;
            reads_remaining_r <= '0;
            writes_remaining_r <= '0;
            cycle_count_r <= '0;
            issued_read_mask_r <= '0;
            threshold_mask_r <= '0;
            read_valid_r <= 1'b0;
            threshold_r <= '0;
        end else begin
            done <= 1'b0;

            read_valid_r <= issue_read;
            issued_read_addr_r <= read_addr;
            issued_read_mask_r <= beat_mask(read_addr);
            threshold_addr_r <= issued_read_addr_r;
            threshold_mask_r <= issued_read_mask_r;

            unique case (state_r)
                STATE_IDLE : begin
                    cycle_count_r <= '0;

                    if (start_accepted) begin
                        state_r <= STATE_RUN;
                        threshold_r <= threshold;
                        reads_remaining_r <= COUNT_WIDTH'(NUM_BEATS - 1);
                        writes_remaining_r <= COUNT_WIDTH'(NUM_BEATS);
                        next_read_addr_r <= (NUM_BEATS > 1) ? ADDR_WIDTH'(1) : '0;
                        cycle_count_r <= CYCLE_COUNT_WIDTH'(1);
                    end
                end

                STATE_RUN : begin
                    cycle_count_r <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);

                    if (issue_read) begin
                        reads_remaining_r <= reads_remaining_r - COUNT_WIDTH'(1);
                        next_read_addr_r <= next_read_addr_r + ADDR_WIDTH'(1);
                    end

                    if (write_en) begin
                        writes_remaining_r <= writes_remaining_r - COUNT_WIDTH'(1);

                        if (writes_remaining_r == COUNT_WIDTH'(1)) begin
                            state_r <= STATE_IDLE;
                            done <= 1'b1;
                            processing_cycles <= cycle_count_r + CYCLE_COUNT_WIDTH'(1);
                        end
                    end
                end

                default : begin
                    state_r <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule
