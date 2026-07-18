// Classes: vector_control_sequence, vector_image_sequence, vector_busy_write_sequence

class vector_control_sequence extends uvm_sequence #(axi_lite_item);
    `uvm_object_utils(vector_control_sequence)
    bit mutate_shadow_after_commit = 1'b1;
    int unsigned expected_version = 1;

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
        if (value != expected_version) begin
            `uvm_error(
                "CFG_VERSION",
                $sformatf("actual=%0d expected=%0d", value, expected_version)
            )
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
    bit stop_after_current_item = 1'b0;

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
            if (stop_after_current_item) begin
                break;
            end
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
        if (tr.resp != 2'b10) begin
            `uvm_error(
                "BUSY_WRITE_RESP",
                $sformatf("addr=%02h actual=%0b expected=SLVERR", addr, tr.resp)
            )
        end
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

class vector_diagnostics_setup_sequence extends vector_control_sequence;
    `uvm_object_utils(vector_diagnostics_setup_sequence)

    function new(string name = "vector_diagnostics_setup_sequence");
        super.new(name);
    endfunction

    task body();
        write_reg(ADDR_ERROR_STATUS, 32'h0000_0007);
        write_reg(ADDR_INT_STATUS, 32'h0000_0007);
        write_reg(ADDR_PERF_CONTROL, 32'h0000_0001);
        // Exercise every mixed interrupt-enable mask before leaving all
        // production interrupt sources enabled for the diagnostics test.
        write_reg(ADDR_INT_ENABLE, 32'h0000_0003);
        write_reg(ADDR_INT_ENABLE, 32'h0000_0005);
        write_reg(ADDR_INT_ENABLE, 32'h0000_0006);
        write_reg(ADDR_INT_ENABLE, 32'h0000_0007);
        super.body();
    endtask
endclass

class vector_diagnostics_check_sequence extends vector_control_sequence;
    `uvm_object_utils(vector_diagnostics_check_sequence)
    virtual preprocess_if ctrl_vif;

    function new(string name = "vector_diagnostics_check_sequence");
        super.new(name);
    endfunction

    task write_expect_response(
        bit [7:0] addr,
        bit [31:0] data,
        bit [1:0] expected_resp
    );
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("diag_write_tr");
        start_item(tr);
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = 4'hf;
        tr.aw_delay_cycles = $urandom_range(0, 3);
        tr.w_delay_cycles = $urandom_range(0, 3);
        tr.response_stall_cycles = $urandom_range(0, 2);
        finish_item(tr);
        if (tr.resp != expected_resp) begin
            `uvm_error(
                "DIAG_WRITE_RESP",
                $sformatf("addr=%02h actual=%0b expected=%0b", addr, tr.resp, expected_resp)
            )
        end
    endtask

    task read_expect_response(
        bit [7:0] addr,
        bit [1:0] expected_resp,
        output bit [31:0] data
    );
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("diag_read_tr");
        start_item(tr);
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;
        tr.data = '0;
        tr.strb = '1;
        tr.response_stall_cycles = $urandom_range(0, 2);
        finish_item(tr);
        data = tr.rdata;
        if (tr.resp != expected_resp) begin
            `uvm_error(
                "DIAG_READ_RESP",
                $sformatf("addr=%02h actual=%0b expected=%0b", addr, tr.resp, expected_resp)
            )
        end
    endtask

    task body();
        bit [31:0] value;

        if (ctrl_vif == null) begin
            `uvm_fatal("NO_DIAG_VIF", "diagnostics sequence requires ctrl_vif")
        end

        read_reg(ADDR_FRAME_COUNT, value);
        if (value != 32'd1) begin
            `uvm_error("DIAG_FRAME_COUNT", $sformatf("actual=%0d expected=1", value))
        end
        read_reg(ADDR_ERROR_COUNT, value);
        if (value != 32'd0) begin
            `uvm_error("DIAG_ERROR_COUNT", $sformatf("legal frame produced %0d errors", value))
        end
        read_reg(ADDR_OUTPUT_STALL_CYCLES, value);
        if (value == 0) begin
            `uvm_error("DIAG_OUTPUT_STALL", "randomized sink produced no recorded output stall")
        end
        read_reg(ADDR_INT_STATUS, value);
        if (!value[0] || !ctrl_vif.irq) begin
            `uvm_error(
                "DIAG_DONE_IRQ",
                $sformatf("done status=%08h irq=%0b", value, ctrl_vif.irq)
            )
        end

        // Preserve the completed-frame status while injecting a rejected
        // write. This checks sticky status composition (done + access error),
        // the single-error counter state, and IRQ behavior.
        write_expect_response(ADDR_IP_ID, 32'h1234_5678, 2'b10);
        repeat (2) @(posedge ctrl_vif.clk);
        if (!ctrl_vif.irq) begin
            `uvm_error("DIAG_WRITE_IRQ", "rejected write did not assert IRQ")
        end
        read_reg(ADDR_ERROR_STATUS, value);
        if (value[2:0] != 3'b010) begin
            `uvm_error("DIAG_WRITE_STATUS", $sformatf("actual=%03b expected=010", value[2:0]))
        end
        read_reg(ADDR_INT_STATUS, value);
        if (value[2:0] != 3'b101) begin
            `uvm_error("DIAG_WRITE_INT", $sformatf("actual=%03b expected=101", value[2:0]))
        end
        read_reg(ADDR_ERROR_COUNT, value);
        if (value != 32'd1) begin
            `uvm_error("DIAG_ERROR_ONE", $sformatf("actual=%0d expected=1", value))
        end

        write_reg(ADDR_ERROR_STATUS, 32'h0000_0007);
        write_reg(ADDR_INT_STATUS, 32'h0000_0007);
        repeat (2) @(posedge ctrl_vif.clk);
        if (ctrl_vif.irq) begin
            `uvm_error("DIAG_FIRST_CLEAR", "IRQ remained asserted after first W1C")
        end

        // Sample a rejected read independently, then add a rejected write
        // without clearing to verify combined sticky error causes.
        read_expect_response(8'h9c, 2'b10, value);
        repeat (2) @(posedge ctrl_vif.clk);
        read_reg(ADDR_ERROR_STATUS, value);
        if (value[2:0] != 3'b100) begin
            `uvm_error("DIAG_READ_STATUS", $sformatf("actual=%03b expected=100", value[2:0]))
        end
        read_reg(ADDR_INT_STATUS, value);
        if (value[2:0] != 3'b100) begin
            `uvm_error("DIAG_READ_INT", $sformatf("actual=%03b expected=100", value[2:0]))
        end
        read_reg(ADDR_ERROR_COUNT, value);
        if (value != 32'd2) begin
            `uvm_error("DIAG_ERROR_TWO", $sformatf("actual=%0d expected=2", value))
        end

        write_expect_response(ADDR_IP_ID, 32'h8765_4321, 2'b10);
        repeat (2) @(posedge ctrl_vif.clk);
        read_reg(ADDR_ERROR_STATUS, value);
        if (value[2:0] != 3'b110) begin
            `uvm_error("DIAG_COMBINED_STATUS", $sformatf("actual=%03b expected=110", value[2:0]))
        end
        read_reg(ADDR_ERROR_COUNT, value);
        if (value != 32'd3) begin
            `uvm_error("DIAG_ERROR_THREE", $sformatf("actual=%0d expected=3", value))
        end

        write_reg(ADDR_ERROR_STATUS, 32'h0000_0007);
        write_reg(ADDR_INT_STATUS, 32'h0000_0007);
        repeat (2) @(posedge ctrl_vif.clk);
        if (ctrl_vif.irq) begin
            `uvm_error("DIAG_FINAL_CLEAR", "IRQ remained asserted after final W1C")
        end
    endtask
endclass

class vector_wstrb_sequence extends uvm_sequence #(axi_lite_item);
    `uvm_object_utils(vector_wstrb_sequence)

    function new(string name = "vector_wstrb_sequence");
        super.new(name);
    endfunction

    task write_reg(bit [7:0] addr, bit [31:0] data, bit [3:0] strb = 4'hf);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("wstrb_write_tr");
        start_item(tr);
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = strb;
        tr.response_stall_cycles = $urandom_range(0, 4);
        finish_item(tr);
        if (tr.resp != 2'b00) begin
            `uvm_error("WSTRB_WRITE", $sformatf("addr=%02h strb=%0h resp=%0b", addr, strb, tr.resp))
        end
    endtask

    task read_reg(bit [7:0] addr, output bit [31:0] data);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("wstrb_read_tr");
        start_item(tr);
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;
        tr.data = '0;
        tr.strb = '0;
        tr.response_stall_cycles = $urandom_range(0, 4);
        finish_item(tr);
        data = tr.rdata;
        if (tr.resp != 2'b00) begin
            `uvm_error("WSTRB_READ", $sformatf("addr=%02h resp=%0b", addr, tr.resp))
        end
    endtask

    function automatic bit [31:0] merge_bytes(
        bit [31:0] current_value,
        bit [31:0] new_value,
        bit [3:0] strb
    );
        bit [31:0] merged;
        merged = current_value;
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
            if (strb[byte_index]) begin
                merged[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
            end
        end
        return merged;
    endfunction

    task body();
        bit [31:0] read_value;
        bit [31:0] expected;
        bit [31:0] base_value = 32'h1122_3344;
        bit [31:0] update_value = 32'ha1b2_c3d4;

        write_reg(ADDR_THRESHOLD, 32'h0000_005a, 4'b0001);
        write_reg(ADDR_THRESHOLD, 32'hffff_0000, 4'b1110);
        read_reg(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] != 8'h5a) begin
            `uvm_error("WSTRB_THRESHOLD", $sformatf("actual=%02h expected=5a", read_value[7:0]))
        end

        write_reg(ADDR_MODE, MODE_VECTOR4, 4'b0010);
        read_reg(ADDR_MODE, read_value);
        if (read_value[1:0] != MODE_THRESHOLD) begin
            `uvm_error("WSTRB_MODE", $sformatf("actual=%0d expected=%0d", read_value[1:0], MODE_THRESHOLD))
        end

        for (int strobe_value = 0; strobe_value < 16; strobe_value++) begin
            write_reg(ADDR_CONV_BIAS, base_value, 4'hf);
            write_reg(ADDR_CONV_BIAS, update_value, strobe_value[3:0]);
            read_reg(ADDR_CONV_BIAS, read_value);
            expected = merge_bytes(base_value, update_value, strobe_value[3:0]);
            if (read_value != expected) begin
                `uvm_error(
                    "WSTRB_BIAS",
                    $sformatf(
                        "strb=%0h actual=%08h expected=%08h",
                        strobe_value[3:0],
                        read_value,
                        expected
                    )
                )
            end
        end

        write_reg(ADDR_VECTOR_CFG_INDEX, 32'd9);
        write_reg(ADDR_VECTOR_CFG_DATA, base_value);
        write_reg(ADDR_VECTOR_CFG_DATA, update_value, 4'b0101);
        read_reg(ADDR_VECTOR_CFG_DATA, read_value);
        expected = merge_bytes(base_value, update_value, 4'b0101);
        if (read_value != expected) begin
            `uvm_error("WSTRB_VECTOR_BIAS", $sformatf("actual=%08h expected=%08h", read_value, expected))
        end

        write_reg(ADDR_VECTOR_CFG_INDEX, 32'd10);
        write_reg(ADDR_VECTOR_CFG_DATA, 32'h0000_0109);
        write_reg(ADDR_VECTOR_CFG_DATA, 32'h0000_0003, 4'b0001);
        read_reg(ADDR_VECTOR_CFG_DATA, read_value);
        if (read_value[8:0] != 9'h103) begin
            `uvm_error("WSTRB_SHIFT", $sformatf("actual=%03h expected=103", read_value[8:0]))
        end

        write_reg(ADDR_VECTOR_CFG_DATA, 32'h0000_0000, 4'b0010);
        read_reg(ADDR_VECTOR_CFG_DATA, read_value);
        if (read_value[8:0] != 9'h003) begin
            `uvm_error("WSTRB_RELU", $sformatf("actual=%03h expected=003", read_value[8:0]))
        end

        write_reg(ADDR_VECTOR_CFG_COMMIT, 32'd1, 4'b1110);
        read_reg(ADDR_VECTOR_CFG_VERSION, read_value);
        if (read_value != 32'd0) begin
            `uvm_error("WSTRB_COMMIT", $sformatf("version changed to %0d", read_value))
        end

        write_reg(ADDR_CTRL, 32'd1, 4'b1110);
        read_reg(ADDR_STATUS, read_value);
        if (read_value[3:0] != 4'b0000) begin
            `uvm_error("WSTRB_CTRL", $sformatf("status changed to %08h", read_value))
        end

        `uvm_info("WSTRB_PASS", "PASS: AXI4-Lite WSTRB preservation checks completed", UVM_NONE)
    endtask
endclass

class vector_axi_protocol_sequence extends uvm_sequence #(axi_lite_item);
    `uvm_object_utils(vector_axi_protocol_sequence)

    function new(string name = "vector_axi_protocol_sequence");
        super.new(name);
    endfunction

    task send_write(
        bit [7:0] addr,
        bit [31:0] data,
        bit [3:0] strb,
        int unsigned aw_delay,
        int unsigned w_delay,
        bit [1:0] expected_resp
    );
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("protocol_write_tr");
        start_item(tr);
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = strb;
        tr.aw_delay_cycles = aw_delay;
        tr.w_delay_cycles = w_delay;
        tr.response_stall_cycles = $urandom_range(0, 4);
        finish_item(tr);
        if (tr.resp != expected_resp) begin
            `uvm_error(
                "AXI_PROTOCOL_WRITE",
                $sformatf(
                    "addr=%02h aw_delay=%0d w_delay=%0d actual_resp=%0b expected_resp=%0b",
                    addr,
                    aw_delay,
                    w_delay,
                    tr.resp,
                    expected_resp
                )
            )
        end
    endtask

    task send_read(bit [7:0] addr, bit [1:0] expected_resp, output bit [31:0] data);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("protocol_read_tr");
        start_item(tr);
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;
        tr.data = '0;
        tr.strb = '0;
        tr.aw_delay_cycles = 0;
        tr.w_delay_cycles = 0;
        tr.response_stall_cycles = $urandom_range(0, 4);
        finish_item(tr);
        data = tr.rdata;
        if (tr.resp != expected_resp) begin
            `uvm_error(
                "AXI_PROTOCOL_READ",
                $sformatf("addr=%02h actual_resp=%0b expected_resp=%0b", addr, tr.resp, expected_resp)
            )
        end
    endtask

    task body();
        bit [31:0] read_value;
        bit [7:0] threshold_model;
        bit [3:0] strb;
        bit [31:0] data;
        int unsigned aw_delay;
        int unsigned w_delay;

        send_write(ADDR_THRESHOLD, 32'h0000_0011, 4'b0001, 0, 4, 2'b00);
        send_read(ADDR_THRESHOLD, 2'b00, read_value);
        if (read_value[7:0] != 8'h11) begin
            `uvm_error("AXI_PROTOCOL_REPEAT_READ", $sformatf("first read returned %02h", read_value[7:0]))
        end
        send_write(ADDR_THRESHOLD, 32'h0000_0022, 4'b0001, 4, 0, 2'b00);
        send_read(ADDR_THRESHOLD, 2'b00, read_value);
        if (read_value[7:0] != 8'h22) begin
            `uvm_error("AXI_PROTOCOL_REPEAT_READ", $sformatf("repeated-address read returned stale value %02h", read_value[7:0]))
        end
        send_write(ADDR_THRESHOLD, 32'h0000_0033, 4'b0001, 0, 0, 2'b00);
        threshold_model = 8'h33;

        for (int transaction_index = 0; transaction_index < 64; transaction_index++) begin
            strb = $urandom_range(0, 15);
            data = $urandom;
            aw_delay = $urandom_range(0, 8);
            w_delay = $urandom_range(0, 8);
            send_write(ADDR_THRESHOLD, data, strb, aw_delay, w_delay, 2'b00);
            if (strb[0]) begin
                threshold_model = data[7:0];
            end
            send_read(ADDR_THRESHOLD, 2'b00, read_value);
            if (read_value[7:0] != threshold_model) begin
                `uvm_error(
                    "AXI_PROTOCOL_MODEL",
                    $sformatf(
                        "transaction=%0d strb=%0h actual=%02h expected=%02h",
                        transaction_index,
                        strb,
                        read_value[7:0],
                        threshold_model
                    )
                )
            end
        end

        send_write(ADDR_STATUS, 32'hffff_ffff, 4'hf, 0, 0, 2'b10);
        send_write(8'h09, 32'h0000_00aa, 4'hf, 0, 3, 2'b10);
        send_write(8'h70, 32'h1234_5678, 4'hf, 3, 0, 2'b10);

        send_read(ADDR_CTRL, 2'b10, read_value);
        if (read_value != 0) begin
            `uvm_error("AXI_PROTOCOL_WO_READ", $sformatf("CTRL returned %08h", read_value))
        end
        send_read(ADDR_VECTOR_CFG_COMMIT, 2'b10, read_value);
        send_read(8'h09, 2'b10, read_value);
        send_read(ADDR_IP_ID, 2'b00, read_value);
        if (read_value != 32'h5a42_4156) begin
            `uvm_error("AXI_PROTOCOL_IP_ID", $sformatf("IP_ID returned %08h", read_value))
        end
        send_read(8'h9c, 2'b10, read_value);

        `uvm_info("AXI_PROTOCOL_PASS", "PASS: randomized AXI4-Lite ordering/response checks completed", UVM_NONE)
    endtask
endclass

class vector_random_control_sequence extends vector_control_sequence;
    `uvm_object_utils(vector_random_control_sequence)

    function new(string name = "vector_random_control_sequence");
        super.new(name);
    endfunction

    task body();
        int signed weight;
        int signed bias;
        int unsigned shift;
        bit relu;

        for (int filter_index = 0; filter_index < 4; filter_index++) begin
            for (int tap_index = 0; tap_index < 9; tap_index++) begin
                weight = $urandom_range(0, 255) - 128;
                write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | tap_index);
                write_reg(ADDR_VECTOR_CFG_DATA, weight);
            end
            bias = $urandom_range(0, 400000) - 200000;
            write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | 9);
            write_reg(ADDR_VECTOR_CFG_DATA, bias);
            shift = $urandom_range(0, 31);
            relu = $urandom_range(0, 1);
            write_reg(ADDR_VECTOR_CFG_INDEX, (filter_index << 4) | 10);
            write_reg(ADDR_VECTOR_CFG_DATA, (relu << 8) | shift);
        end

        write_reg(ADDR_VECTOR_CFG_COMMIT, 32'd1);
        write_reg(ADDR_MODE, MODE_VECTOR4);
        write_reg(ADDR_CTRL, 32'd1);
    endtask
endclass

class vector_random_image_sequence extends uvm_sequence #(axis_stream_item);
    `uvm_object_utils(vector_random_image_sequence)

    function new(string name = "vector_random_image_sequence");
        super.new(name);
    endfunction

    task body();
        axis_stream_item tr;
        for (int beat_index = 0; beat_index < IMAGE_PIXELS; beat_index++) begin
            tr = axis_stream_item::type_id::create($sformatf("random_pixel_%0d", beat_index));
            start_item(tr);
            tr.data = $urandom_range(0, 255);
            tr.keep = '1;
            tr.last = (beat_index == IMAGE_PIXELS - 1);
            tr.gap_cycles = $urandom_range(0, 4);
            tr.beat_index = beat_index;
            finish_item(tr);
        end
    endtask
endclass

typedef enum int {
    VECTOR_FAULT_EARLY_TLAST,
    VECTOR_FAULT_MISSING_TLAST,
    VECTOR_FAULT_BAD_TKEEP
} vector_packet_fault_e;

class vector_malformed_image_sequence extends uvm_sequence #(axis_stream_item);
    `uvm_object_utils(vector_malformed_image_sequence)
    vector_packet_fault_e fault = VECTOR_FAULT_EARLY_TLAST;
    string input_mem = "generated/test_vectors/sample_000_input.mem";
    bit [7:0] input_pixels [0:IMAGE_PIXELS-1];

    function new(string name = "vector_malformed_image_sequence");
        super.new(name);
    endfunction

    task body();
        axis_stream_item tr;
        $readmemh(input_mem, input_pixels);
        for (int beat_index = 0; beat_index < IMAGE_PIXELS; beat_index++) begin
            tr = axis_stream_item::type_id::create($sformatf("malformed_pixel_%0d", beat_index));
            start_item(tr);
            tr.data = input_pixels[beat_index];
            tr.keep = ((fault == VECTOR_FAULT_BAD_TKEEP) && (beat_index == 200)) ? 4'b0001 : 4'hf;
            unique case (fault)
                VECTOR_FAULT_EARLY_TLAST:
                    tr.last = (beat_index == 100) || (beat_index == IMAGE_PIXELS - 1);
                VECTOR_FAULT_MISSING_TLAST:
                    tr.last = 1'b0;
                default:
                    tr.last = (beat_index == IMAGE_PIXELS - 1);
            endcase
            tr.gap_cycles = $urandom_range(0, 2);
            tr.beat_index = beat_index;
            finish_item(tr);
        end
    endtask
endclass

class vector_status_check_sequence extends vector_control_sequence;
    `uvm_object_utils(vector_status_check_sequence)
    bit expected_packet_error;
    bit clear_after_check = 1'b1;
    int unsigned expected_error_count = 0;

    function new(string name = "vector_status_check_sequence");
        super.new(name);
    endfunction

    task body();
        bit [31:0] status_value;
        bit [31:0] diag_value;
        for (int poll_count = 0; poll_count < UVM_TIMEOUT_CYCLES; poll_count++) begin
            read_reg(ADDR_STATUS, status_value);
            if (status_value[1]) begin
                if (status_value[2] != expected_packet_error) begin
                    `uvm_error(
                        "PACKET_STATUS",
                        $sformatf(
                            "actual_error=%0b expected_error=%0b status=%08h",
                            status_value[2],
                            expected_packet_error,
                            status_value
                        )
                    )
                end

                read_reg(ADDR_ERROR_STATUS, diag_value);
                if (diag_value[2:0] != (expected_packet_error ? 3'b001 : 3'b000)) begin
                    `uvm_error(
                        "PACKET_ERROR_STATUS",
                        $sformatf(
                            "actual=%03b expected=%03b",
                            diag_value[2:0],
                            expected_packet_error ? 3'b001 : 3'b000
                        )
                    )
                end
                read_reg(ADDR_INT_STATUS, diag_value);
                if (!diag_value[0] || (diag_value[1] != expected_packet_error) || diag_value[2]) begin
                    `uvm_error(
                        "PACKET_INT_STATUS",
                        $sformatf(
                            "actual=%03b expected_done=1 expected_packet=%0b",
                            diag_value[2:0],
                            expected_packet_error
                        )
                    )
                end
                if (expected_packet_error) begin
                    // First sample the combined done+packet state, then clear
                    // only done and sample the individual packet cause.
                    write_reg(ADDR_INT_STATUS, 32'h0000_0001);
                    read_reg(ADDR_INT_STATUS, diag_value);
                    if (diag_value[2:0] != 3'b010) begin
                        `uvm_error(
                            "PACKET_INT_ISOLATE",
                            $sformatf("actual=%03b expected=010", diag_value[2:0])
                        )
                    end
                end
                read_reg(ADDR_ERROR_COUNT, diag_value);
                if (diag_value != expected_error_count) begin
                    `uvm_error(
                        "PACKET_ERROR_COUNT",
                        $sformatf("actual=%0d expected=%0d", diag_value, expected_error_count)
                    )
                end
                write_reg(ADDR_ERROR_STATUS, 32'h0000_0007);
                write_reg(ADDR_INT_STATUS, 32'h0000_0007);

                if (clear_after_check) begin
                    write_reg(ADDR_CTRL, 32'd2);
                    read_reg(ADDR_STATUS, status_value);
                    if (status_value[2:1] != 2'b00) begin
                        `uvm_error("PACKET_CLEAR", $sformatf("status remained %08h", status_value))
                    end
                end
                return;
            end
        end
        `uvm_fatal("PACKET_TIMEOUT", "frame did not reach terminal done status")
    endtask
endclass

class vector_reset_check_sequence extends vector_control_sequence;
    `uvm_object_utils(vector_reset_check_sequence)

    function new(string name = "vector_reset_check_sequence");
        super.new(name);
    endfunction

    task body();
        bit [31:0] value;
        read_reg(ADDR_STATUS, value);
        if (value[3:0] != 0) begin
            `uvm_error("RESET_STATUS", $sformatf("status=%08h", value))
        end
        read_reg(ADDR_THRESHOLD, value);
        if (value[7:0] != 8'd128) begin
            `uvm_error("RESET_THRESHOLD", $sformatf("threshold=%0d", value[7:0]))
        end
        read_reg(ADDR_MODE, value);
        if (value[1:0] != MODE_THRESHOLD) begin
            `uvm_error("RESET_MODE", $sformatf("mode=%0d", value[1:0]))
        end
        read_reg(ADDR_VECTOR_CFG_VERSION, value);
        if (value != 0) begin
            `uvm_error("RESET_VERSION", $sformatf("version=%0d", value))
        end
    endtask
endclass
