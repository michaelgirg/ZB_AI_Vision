
// Module: image_preprocess_reg_block
// Description:
//Register-controlled wrapper around the buffered preprocessing block.
//
//This is not a complete AXI-Lite slave. It is the protocol-neutral register
//layer that the future AXI-Lite wrapper will drive.

module image_preprocess_reg_block #(
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
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                            clk,
    input  logic                            rst,

    input  logic                            reg_write_en,
    input  logic [REG_ADDR_WIDTH-1:0]       reg_write_addr,
    input  logic [REG_DATA_WIDTH-1:0]       reg_write_data,

    input  logic                            reg_read_en,
    input  logic [REG_ADDR_WIDTH-1:0]       reg_read_addr,
    output logic [REG_DATA_WIDTH-1:0]       reg_read_data
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

    localparam logic [1:0] MODE_THRESHOLD = 2'd0;
    localparam logic [1:0] MODE_SOBEL     = 2'd1;

    logic                              start_pulse;
    logic                              clear_done_pulse;
    logic                              busy;
    logic                              done_pulse;
    logic [CYCLE_COUNT_WIDTH-1:0]      processing_cycles;
    logic [DATA_WIDTH-1:0]             threshold_r;
    logic [1:0]                        mode_r;
    logic                              done_latched_r;
    logic [CYCLE_COUNT_WIDTH-1:0]      processing_cycles_latched_r;
    logic [ADDR_WIDTH-1:0]             input_addr_r;
    logic [PIXELS_PER_CYCLE-1:0]       input_wmask_r;
    logic [ADDR_WIDTH-1:0]             output_addr_r;
    logic                              input_data_write;
    logic                              output_addr_write;
    logic [BEAT_WIDTH-1:0]             host_output_rdata;

    assign start_pulse =
        reg_write_en && (reg_write_addr == ADDR_CTRL) && reg_write_data[0];

    assign clear_done_pulse =
        reg_write_en && (reg_write_addr == ADDR_CTRL) && reg_write_data[1];

    assign input_data_write =
        reg_write_en && (reg_write_addr == ADDR_INPUT_WDATA) && !busy;

    assign output_addr_write =
        reg_write_en && (reg_write_addr == ADDR_OUTPUT_ADDR);

    image_preprocess_buffered #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .PIXELS_PER_CYCLE(PIXELS_PER_CYCLE),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) buffered (
        .clk(clk),
        .rst(rst),
        .start(start_pulse),
        .mode(mode_r),
        .threshold(threshold_r),
        .busy(busy),
        .done(done_pulse),
        .processing_cycles(processing_cycles),
        .host_input_we(input_data_write),
        .host_input_addr(input_addr_r),
        .host_input_wdata(reg_write_data[BEAT_WIDTH-1:0]),
        .host_input_wmask(input_wmask_r),
        .host_output_re(output_addr_write),
        .host_output_addr(output_addr_write ? reg_write_data[ADDR_WIDTH-1:0] : output_addr_r),
        .host_output_rdata(host_output_rdata)
    );

`ifndef SYNTHESIS
    initial begin
        if (BEAT_WIDTH > REG_DATA_WIDTH) begin
            $fatal(1, "BEAT_WIDTH must fit inside REG_DATA_WIDTH.");
        end
    end
`endif

    always_ff @(posedge clk) begin
        if (rst) begin
            threshold_r <= DATA_WIDTH'(128);
            mode_r <= MODE_THRESHOLD;
            done_latched_r <= 1'b0;
            processing_cycles_latched_r <= '0;
            input_addr_r <= '0;
            input_wmask_r <= '1;
            output_addr_r <= '0;
        end else begin
            if (done_pulse) begin
                done_latched_r <= 1'b1;
                processing_cycles_latched_r <= processing_cycles;
            end

            if (start_pulse || clear_done_pulse) begin
                done_latched_r <= 1'b0;
            end

            if (reg_write_en) begin
                unique case (reg_write_addr)
                    ADDR_THRESHOLD : begin
                        if (!busy) begin
                            threshold_r <= reg_write_data[DATA_WIDTH-1:0];
                        end
                    end

                    ADDR_MODE : begin
                        if (!busy) begin
                            unique case (reg_write_data[1:0])
                                MODE_THRESHOLD,
                                MODE_SOBEL : begin
                                    mode_r <= reg_write_data[1:0];
                                end

                                default : begin
                                    mode_r <= MODE_THRESHOLD;
                                end
                            endcase
                        end
                    end

                    ADDR_INPUT_ADDR : begin
                        input_addr_r <= reg_write_data[ADDR_WIDTH-1:0];
                    end

                    ADDR_INPUT_WMASK : begin
                        input_wmask_r <= reg_write_data[PIXELS_PER_CYCLE-1:0];
                    end

                    ADDR_OUTPUT_ADDR : begin
                        output_addr_r <= reg_write_data[ADDR_WIDTH-1:0];
                    end

                    default : begin
                    end
                endcase
            end
        end
    end

    always_comb begin
        reg_read_data = '0;

        if (reg_read_en) begin
            unique case (reg_read_addr)
                ADDR_STATUS : begin
                    reg_read_data[0] = busy;
                    reg_read_data[1] = done_latched_r;
                end

                ADDR_THRESHOLD : begin
                    reg_read_data[DATA_WIDTH-1:0] = threshold_r;
                end

                ADDR_IMAGE_PIXELS : begin
                    reg_read_data = REG_DATA_WIDTH'(IMAGE_PIXELS);
                end

                ADDR_PIXELS_PER_CYCLE : begin
                    reg_read_data = REG_DATA_WIDTH'(PIXELS_PER_CYCLE);
                end

                ADDR_PROCESSING_CYCLES : begin
                    reg_read_data[CYCLE_COUNT_WIDTH-1:0] = processing_cycles_latched_r;
                end

                ADDR_INPUT_ADDR : begin
                    reg_read_data[ADDR_WIDTH-1:0] = input_addr_r;
                end

                ADDR_INPUT_WMASK : begin
                    reg_read_data[PIXELS_PER_CYCLE-1:0] = input_wmask_r;
                end

                ADDR_OUTPUT_ADDR : begin
                    reg_read_data[ADDR_WIDTH-1:0] = output_addr_r;
                end

                ADDR_OUTPUT_RDATA : begin
                    reg_read_data[BEAT_WIDTH-1:0] = host_output_rdata;
                end

                ADDR_MODE : begin
                    reg_read_data[1:0] = mode_r;
                end

                default : begin
                    reg_read_data = '0;
                end
            endcase
        end
    end

endmodule
