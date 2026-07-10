// Classes: vector_control_sequence, vector_image_sequence, vector_busy_write_sequence

class vector_control_sequence extends uvm_sequence #(axi_lite_item);
    `uvm_object_utils(vector_control_sequence)
    bit mutate_shadow_after_commit = 1'b1;

    function new(string name = "vector_control_sequence");
        super.new(name);
    endfunction

    task write_reg(bit [7:0] addr, bit [31:0] data);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("write_tr");
        start_item(tr);
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = '1;
        tr.response_stall_cycles = $urandom_range(0, 2);
        finish_item(tr);
        if (tr.resp != 2'b00) begin
            `uvm_error("AXI_WRITE", $sformatf("addr=%02h resp=%0b", addr, tr.resp))
        end
    endtask

    task read_reg(bit [7:0] addr, output bit [31:0] data);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("read_tr");
        start_item(tr);
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;
        tr.data = '0;
        tr.strb = '1;
        tr.response_stall_cycles = $urandom_range(0, 2);
        finish_item(tr);
        data = tr.rdata;
        if (tr.resp != 2'b00) begin
            `uvm_error("AXI_READ", $sformatf("addr=%02h resp=%0b", addr, tr.resp))
        end
    endtask

    task body();
        int signed weights [0:3][0:8] = '{
            '{29, 104, 127, -115, -76, 58, -78, -92, -114},
            '{13, -13, -116, -49, -79, 15, -127, -26, 11},
            '{48, -11, -127, -111, -76, -35, 39, 126, 94},
            '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
        };
        int signed biases [0:3] = '{11029, 17936, 257, -131};
        int shifts [0:3] = '{9, 7, 9, 9};
        bit [31:0] value;

        for (int filter_index = 0; filter_index < 4; filter_index++) begin
            for (int tap_index = 0; tap_index < 9; tap_index++) begin
                write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | tap_index);
                write_reg(ADDR_VECTOR_CFG_DATA, weights[filter_index][tap_index]);
            end
            write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | 9);
            write_reg(ADDR_VECTOR_CFG_DATA, biases[filter_index]);
            write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | 10);
            write_reg(ADDR_VECTOR_CFG_DATA, (1 << 8) | shifts[filter_index]);
        end

        write_reg(ADDR_VECTOR_CFG_COMMIT, 32'd1);
        read_reg(ADDR_VECTOR_CFG_VERSION, value);
        if (value != 32'd1) begin
            `uvm_error("CFG_VERSION", $sformatf("actual=%0d expected=1", value))
        end

        if (mutate_shadow_after_commit) begin
            write_reg(ADDR_VECTOR_CFG_INDEX, 32'd0);
            write_reg(ADDR_VECTOR_CFG_DATA, 32'd0);
            read_reg(ADDR_VECTOR_CFG_DATA, value);
            if (value != 32'd0) begin
                `uvm_error("SHADOW_READBACK", $sformatf("actual=%08h expected=0", value))
            end
        end

        write_reg(ADDR_MODE, MODE_VECTOR4);
        write_reg(ADDR_CTRL, 32'd1);
    endtask
endclass

class vector_saturation_control_sequence extends vector_control_sequence;
    `uvm_object_utils(vector_saturation_control_sequence)

    function new(string name = "vector_saturation_control_sequence");
        super.new(name);
    endfunction

    task body();
        bit [31:0] value;

        for (int filter_index = 0; filter_index < 4; filter_index++) begin
            for (int tap_index = 0; tap_index < 9; tap_index++) begin
                write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | tap_index);
                write_reg(ADDR_VECTOR_CFG_DATA, 32'd0);
            end
            write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | 9);
            write_reg(ADDR_VECTOR_CFG_DATA, 32'd255);
            write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | 10);
            write_reg(ADDR_VECTOR_CFG_DATA, 32'h0000_0100);
        end

        write_reg(ADDR_VECTOR_CFG_COMMIT, 32'd1);
        read_reg(ADDR_VECTOR_CFG_VERSION, value);
        if (value != 32'd1) begin
            `uvm_error("SAT_CFG_VERSION", $sformatf("actual=%0d expected=1", value))
        end

        write_reg(ADDR_MODE, MODE_VECTOR4);
        write_reg(ADDR_CTRL, 32'd1);
    endtask
endclass

class vector_image_sequence extends uvm_sequence #(axis_stream_item);
    `uvm_object_utils(vector_image_sequence)
    string input_mem = "generated/test_vectors/sample_000_input.mem";
    bit [7:0] input_pixels [0:IMAGE_PIXELS-1];

    function new(string name = "vector_image_sequence");
        super.new(name);
    endfunction

    task body();
        axis_stream_item tr;
        void'($value$plusargs("INPUT_MEM=%s", input_mem));
        $readmemh(input_mem, input_pixels);
        for (int beat_index = 0; beat_index < IMAGE_PIXELS; beat_index++) begin
            tr = axis_stream_item::type_id::create($sformatf("pixel_%0d", beat_index));
            start_item(tr);
            tr.data = {{(AXIS_DATA_WIDTH - 8){1'b0}}, input_pixels[beat_index]};
            tr.keep = '1;
            tr.last = (beat_index == IMAGE_PIXELS - 1);
            tr.gap_cycles = $urandom_range(0, 2);
            tr.beat_index = beat_index;
            finish_item(tr);
        end
    endtask
endclass

class vector_busy_write_sequence extends uvm_sequence #(axi_lite_item);
    `uvm_object_utils(vector_busy_write_sequence)

    function new(string name = "vector_busy_write_sequence");
        super.new(name);
    endfunction

    task send_write(bit [7:0] addr, bit [31:0] data);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("busy_write_tr");
        start_item(tr);
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = '1;
        tr.response_stall_cycles = 0;
        finish_item(tr);
    endtask

    task send_read(bit [7:0] addr, output bit [31:0] data);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("busy_read_tr");
        start_item(tr);
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;
        tr.data = '0;
        tr.strb = '1;
        tr.response_stall_cycles = 0;
        finish_item(tr);
        data = tr.rdata;
    endtask

    task body();
        bit [31:0] value;

        send_read(ADDR_STATUS, value);
        if (!value[0]) begin
            `uvm_error("NOT_BUSY", "busy-write sequence started while accelerator was idle")
        end

        send_write(ADDR_VECTOR_CFG_INDEX, 32'd0);
        send_write(ADDR_VECTOR_CFG_DATA, 32'h0000_007f);
        send_write(ADDR_VECTOR_CFG_COMMIT, 32'd1);
        send_write(ADDR_MODE, MODE_THRESHOLD);
        send_write(ADDR_CTRL, 32'd1);

        send_read(ADDR_VECTOR_CFG_VERSION, value);
        if (value != 32'd1) begin
            `uvm_error(
                "BUSY_COMMIT",
                $sformatf("configuration version changed while busy: %0d", value)
            )
        end
    endtask
endclass
