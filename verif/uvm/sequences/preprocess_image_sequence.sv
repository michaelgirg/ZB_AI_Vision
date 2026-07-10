// Class: preprocess_image_sequence
// Description:
//Base image preprocessing sequence for threshold and Sobel modes.

class preprocess_image_sequence extends uvm_sequence #(axi_lite_item);

    `uvm_object_utils(preprocess_image_sequence)

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    int preprocess_mode = MODE_THRESHOLD;
    int threshold_value = 128;
    bit [DATA_WIDTH-1:0] input_pixels [0:IMAGE_PIXELS-1];

    function new(string name = "preprocess_image_sequence");
        super.new(name);
    endfunction

    task body();
        bit [AXI_DATA_WIDTH-1:0] read_value;

        $readmemh(input_mem_path, input_pixels);
        `uvm_info(
            get_type_name(),
            $sformatf("Running %s sequence with input %s", mode_name(preprocess_mode), input_mem_path),
            UVM_LOW
        )

        axi_read(ADDR_IMAGE_PIXELS, read_value);
        if (read_value != IMAGE_PIXELS) begin
            `uvm_error("CONST", $sformatf("IMAGE_PIXELS actual=%0d expected=%0d", read_value, IMAGE_PIXELS))
        end

        axi_read(ADDR_PIXELS_PER_CYCLE, read_value);
        if (read_value != 1) begin
            `uvm_error("CONST", $sformatf("PIXELS_PER_CYCLE actual=%0d expected=1", read_value))
        end

        axi_write(ADDR_THRESHOLD, threshold_value);
        axi_write(ADDR_MODE, preprocess_mode);
        axi_write(ADDR_INPUT_WMASK, 1);

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_INPUT_ADDR, pixel);
            axi_write(ADDR_INPUT_WDATA, input_pixels[pixel]);
        end

        axi_write(ADDR_CTRL, 1);
        poll_done();

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        if (read_value != expected_cycles(preprocess_mode)) begin
            `uvm_error(
                "CYCLES",
                $sformatf(
                    "%s cycles actual=%0d expected=%0d",
                    mode_name(preprocess_mode),
                    read_value,
                    expected_cycles(preprocess_mode)
                )
            )
        end

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            axi_write(ADDR_OUTPUT_ADDR, pixel);
            axi_read(ADDR_OUTPUT_RDATA, read_value);
        end

        axi_write(ADDR_CTRL, 2);
    endtask

    task axi_write(input bit [AXI_ADDR_WIDTH-1:0] addr, input bit [AXI_DATA_WIDTH-1:0] data);
        axi_lite_item tr;

        tr = axi_lite_item::type_id::create("write_tr");
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = '1;

        start_item(tr);
        finish_item(tr);

        if (tr.resp != 2'b00) begin
            `uvm_error("AXI_WRITE", $sformatf("Write addr=0x%02h resp=%0b", addr, tr.resp))
        end
    endtask

    task axi_read(input bit [AXI_ADDR_WIDTH-1:0] addr, output bit [AXI_DATA_WIDTH-1:0] data);
        axi_lite_item tr;

        tr = axi_lite_item::type_id::create("read_tr");
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;

        start_item(tr);
        finish_item(tr);

        data = tr.rdata;
        if (tr.resp != 2'b00) begin
            `uvm_error("AXI_READ", $sformatf("Read addr=0x%02h resp=%0b", addr, tr.resp))
        end
    endtask

    task poll_done();
        bit [AXI_DATA_WIDTH-1:0] status_value;

        for (int poll_count = 0; poll_count < TIMEOUT_CYCLES; poll_count++) begin
            axi_read(ADDR_STATUS, status_value);
            if (status_value[1]) begin
                return;
            end
        end

        `uvm_fatal("TIMEOUT", "Accelerator did not report done")
    endtask

endclass
