// Class: reset_sequence
// Description:
//Reset-focused sequence for idle and active accelerator states.

class reset_sequence extends control_sequence;

    `uvm_object_utils(reset_sequence)

    virtual preprocess_if vif;
    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    bit [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];

    function new(string name = "reset_sequence");
        super.new(name);
    endfunction

    task body();
        if (vif == null) begin
            `uvm_fatal("NO_VIF", "reset_sequence requires a virtual preprocess_if")
        end

        $readmemh(input_mem_path, input_pixels);

        apply_reset("idle");
        check_reset_defaults("idle reset");

        load_image();
        axi_write(ADDR_THRESHOLD, 128);
        axi_write(ADDR_MODE, MODE_THRESHOLD);
        axi_write(ADDR_CTRL, 1);
        wait_for_busy();
        apply_reset("active threshold");
        check_reset_defaults("active threshold reset");

        load_image();
        axi_write(ADDR_THRESHOLD, 128);
        axi_write(ADDR_MODE, MODE_SOBEL);
        axi_write(ADDR_CTRL, 1);
        wait_for_busy();
        apply_reset("active Sobel");
        check_reset_defaults("active Sobel reset");

        load_image();
        axi_write(ADDR_THRESHOLD, 128);
        axi_write(ADDR_MODE, MODE_THRESHOLD);
        axi_write(ADDR_CTRL, 1);
        poll_done();
        check_clean_threshold_run();

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            bit [AXI_DATA_WIDTH-1:0] read_value;

            axi_write(ADDR_OUTPUT_ADDR, pixel);
            axi_read(ADDR_OUTPUT_RDATA, read_value);
        end

        axi_write(ADDR_CTRL, 2);
    endtask

    task load_image();
        axi_write(ADDR_INPUT_WMASK, 1);

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_INPUT_ADDR, pixel);
            axi_write(ADDR_INPUT_WDATA, input_pixels[pixel]);
        end
    endtask

    task apply_reset(input string reset_name);
        `uvm_info("RESET_SEQ", $sformatf("Applying %s reset", reset_name), UVM_LOW)

        @(negedge vif.clk);
        vif.rstn <= 1'b0;
        repeat (5) @(posedge vif.clk);
        @(negedge vif.clk);
        vif.rstn <= 1'b1;
        repeat (3) @(posedge vif.clk);
    endtask

    task check_reset_defaults(input string reset_context);
        bit [AXI_DATA_WIDTH-1:0] read_value;

        axi_read(ADDR_STATUS, read_value);
        if (read_value[1:0] != 2'b00) begin
            `uvm_error("RESET_SEQ", $sformatf("%s left status=0x%0h", reset_context, read_value[1:0]))
        end

        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] != 8'd128) begin
            `uvm_error("RESET_SEQ", $sformatf("%s left threshold=%0d", reset_context, read_value[7:0]))
        end

        axi_read(ADDR_MODE, read_value);
        if (read_value[1:0] != MODE_THRESHOLD[1:0]) begin
            `uvm_error("RESET_SEQ", $sformatf("%s left mode=%0d", reset_context, read_value[1:0]))
        end

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        if (read_value != '0) begin
            `uvm_error("RESET_SEQ", $sformatf("%s left cycle count=%0d", reset_context, read_value))
        end
    endtask

    task check_clean_threshold_run();
        bit [AXI_DATA_WIDTH-1:0] read_value;

        axi_read(ADDR_STATUS, read_value);
        if (read_value[0] || !read_value[1]) begin
            `uvm_error("RESET_SEQ", $sformatf("Clean run ended with status=0x%0h", read_value[1:0]))
        end

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        if (read_value != expected_cycles(MODE_THRESHOLD)) begin
            `uvm_error(
                "RESET_SEQ",
                $sformatf(
                    "Clean threshold cycles actual=%0d expected=%0d",
                    read_value,
                    expected_cycles(MODE_THRESHOLD)
                )
            )
        end
    endtask

    task wait_for_busy();
        bit [AXI_DATA_WIDTH-1:0] status_value;

        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            axi_read(ADDR_STATUS, status_value);
            if (status_value[0]) begin
                return;
            end
        end

        `uvm_fatal("RESET_SEQ", "Accelerator did not enter busy state before reset")
    endtask

    task poll_done();
        bit [AXI_DATA_WIDTH-1:0] status_value;

        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            axi_read(ADDR_STATUS, status_value);
            if (status_value[1]) begin
                return;
            end
        end

        `uvm_fatal("RESET_SEQ", "Clean post-reset operation did not report done")
    endtask

endclass
