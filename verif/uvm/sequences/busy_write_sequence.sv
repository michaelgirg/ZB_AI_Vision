// Class: busy_write_sequence
// Description:
//Busy-time AXI write stress test sequence.

class busy_write_sequence extends control_sequence;

    `uvm_object_utils(busy_write_sequence)

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    bit [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];

    function new(string name = "busy_write_sequence");
        super.new(name);
    endfunction

    task body();
        bit [AXI_DATA_WIDTH-1:0] read_value;

        $readmemh(input_mem_path, input_pixels);

        axi_write(ADDR_THRESHOLD, 128);
        axi_write(ADDR_MODE, MODE_THRESHOLD);
        axi_write(ADDR_INPUT_WMASK, 1);

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_INPUT_ADDR, pixel);
            axi_write(ADDR_INPUT_WDATA, input_pixels[pixel]);
        end

        axi_write(ADDR_CTRL, 1);
        wait_for_busy();

        axi_write(ADDR_THRESHOLD, 0);
        axi_write(ADDR_MODE, MODE_SOBEL);
        axi_write(ADDR_INPUT_ADDR, 0);
        axi_write(ADDR_INPUT_WDATA, 8'h00);
        axi_write(ADDR_CTRL, 1);

        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] != 8'd128) begin
            `uvm_error("BUSY_WRITE", "Threshold register changed during busy processing")
        end

        axi_read(ADDR_MODE, read_value);
        if (read_value[1:0] != MODE_THRESHOLD[1:0]) begin
            `uvm_error("BUSY_WRITE", "Mode register changed during busy processing")
        end

        poll_done();

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        if (read_value != expected_cycles(MODE_THRESHOLD)) begin
            `uvm_error(
                "BUSY_WRITE",
                $sformatf(
                    "Threshold cycles actual=%0d expected=%0d after busy writes",
                    read_value,
                    expected_cycles(MODE_THRESHOLD)
                )
            )
        end

        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] != 8'd128) begin
            `uvm_error("BUSY_WRITE", "Threshold register corrupted after busy processing")
        end

        axi_read(ADDR_MODE, read_value);
        if (read_value[1:0] != MODE_THRESHOLD[1:0]) begin
            `uvm_error("BUSY_WRITE", "Mode register corrupted after busy processing")
        end

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_OUTPUT_ADDR, pixel);
            axi_read(ADDR_OUTPUT_RDATA, read_value);
        end

        axi_write(ADDR_CTRL, 2);
    endtask

    task wait_for_busy();
        bit [AXI_DATA_WIDTH-1:0] status_value;

        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            axi_read(ADDR_STATUS, status_value);
            if (status_value[0]) begin
                return;
            end
        end

        `uvm_fatal("BUSY_TIMEOUT", "Accelerator did not enter busy state")
    endtask

    task poll_done();
        bit [AXI_DATA_WIDTH-1:0] status_value;

        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            axi_read(ADDR_STATUS, status_value);
            if (status_value[1]) begin
                return;
            end
        end

        `uvm_fatal("DONE_TIMEOUT", "Accelerator did not report done after busy-write stress")
    endtask

endclass
