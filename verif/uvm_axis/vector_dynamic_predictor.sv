`uvm_analysis_imp_decl(_predictor_input)
`uvm_analysis_imp_decl(_predictor_ctrl)

class vector_dynamic_predictor extends uvm_component;
    `uvm_component_utils(vector_dynamic_predictor)

    uvm_analysis_imp_predictor_input #(axis_stream_item, vector_dynamic_predictor) input_export;
    uvm_analysis_imp_predictor_ctrl #(axi_lite_item, vector_dynamic_predictor) ctrl_export;
    uvm_analysis_port #(axis_stream_item) expected_ap;
    virtual preprocess_if ctrl_vif;

    bit [7:0] pixels [0:IMAGE_PIXELS-1];
    int signed shadow_weights [0:3][0:8];
    int signed committed_weights [0:3][0:8];
    int signed active_weights [0:3][0:8];
    int signed shadow_bias [0:3];
    int signed committed_bias [0:3];
    int signed active_bias [0:3];
    int unsigned shadow_shift [0:3];
    int unsigned committed_shift [0:3];
    int unsigned active_shift [0:3];
    bit shadow_relu [0:3];
    bit committed_relu [0:3];
    bit active_relu [0:3];
    bit [5:0] cfg_index;
    bit [1:0] mode_shadow;
    bit [1:0] active_mode;
    int unsigned input_count;
    bit frame_armed;

    function new(string name = "vector_dynamic_predictor", uvm_component parent = null);
        super.new(name, parent);
        input_export = new("input_export", this);
        ctrl_export = new("ctrl_export", this);
        expected_ap = new("expected_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "vector_dynamic_predictor could not get preprocess_if")
        end
        reset_model();
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(negedge ctrl_vif.rstn);
            reset_model();
        end
    endtask

    function void reset_model();
        int signed defaults [0:3][0:8] = '{
            '{29, 104, 127, -115, -76, 58, -78, -92, -114},
            '{13, -13, -116, -49, -79, 15, -127, -26, 11},
            '{48, -11, -127, -111, -76, -35, 39, 126, 94},
            '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
        };
        int signed default_bias [0:3] = '{11029, 17936, 257, -131};
        int unsigned default_shift [0:3] = '{9, 7, 9, 9};

        cfg_index = 0;
        mode_shadow = MODE_THRESHOLD;
        active_mode = MODE_THRESHOLD;
        input_count = 0;
        frame_armed = 1'b0;
        for (int filter_index = 0; filter_index < 4; filter_index++) begin
            shadow_bias[filter_index] = default_bias[filter_index];
            committed_bias[filter_index] = default_bias[filter_index];
            active_bias[filter_index] = default_bias[filter_index];
            shadow_shift[filter_index] = default_shift[filter_index];
            committed_shift[filter_index] = default_shift[filter_index];
            active_shift[filter_index] = default_shift[filter_index];
            shadow_relu[filter_index] = 1'b1;
            committed_relu[filter_index] = 1'b1;
            active_relu[filter_index] = 1'b1;
            for (int tap_index = 0; tap_index < 9; tap_index++) begin
                shadow_weights[filter_index][tap_index] = defaults[filter_index][tap_index];
                committed_weights[filter_index][tap_index] = defaults[filter_index][tap_index];
                active_weights[filter_index][tap_index] = defaults[filter_index][tap_index];
            end
        end
    endfunction

    function automatic bit [31:0] merge_bytes(
        bit [31:0] current_value,
        bit [31:0] new_value,
        bit [3:0] strobes
    );
        bit [31:0] merged;
        merged = current_value;
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
            if (strobes[byte_index]) begin
                merged[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
            end
        end
        return merged;
    endfunction

    function void write_predictor_ctrl(axi_lite_item tr);
        int unsigned filter_index;
        int unsigned entry_index;
        bit [31:0] merged_value;

        if ((tr.kind != AXI_LITE_WRITE) || (tr.resp != 2'b00)) begin
            return;
        end

        unique case (tr.addr)
            ADDR_MODE: begin
                if (tr.strb[0]) mode_shadow = tr.data[1:0];
            end
            ADDR_VECTOR_CFG_INDEX: begin
                if (tr.strb[0]) cfg_index = tr.data[5:0];
            end
            ADDR_VECTOR_CFG_DATA: begin
                filter_index = cfg_index[5:4];
                entry_index = cfg_index[3:0];
                if (entry_index < 9) begin
                    if (tr.strb[0]) shadow_weights[filter_index][entry_index] = $signed(tr.data[7:0]);
                end else if (entry_index == 9) begin
                    merged_value = merge_bytes(shadow_bias[filter_index], tr.data, tr.strb);
                    shadow_bias[filter_index] = $signed(merged_value);
                end else if (entry_index == 10) begin
                    if (tr.strb[0]) shadow_shift[filter_index] = tr.data[4:0];
                    if (tr.strb[1]) shadow_relu[filter_index] = tr.data[8];
                end
            end
            ADDR_VECTOR_CFG_COMMIT: begin
                if (tr.strb[0] && tr.data[0]) begin
                    for (int f = 0; f < 4; f++) begin
                        committed_bias[f] = shadow_bias[f];
                        committed_shift[f] = shadow_shift[f];
                        committed_relu[f] = shadow_relu[f];
                        for (int tap = 0; tap < 9; tap++) begin
                            committed_weights[f][tap] = shadow_weights[f][tap];
                        end
                    end
                end
            end
            ADDR_CTRL: begin
                if (tr.strb[0] && tr.data[0]) begin
                    active_mode = mode_shadow;
                    frame_armed = 1'b1;
                    input_count = 0;
                    for (int f = 0; f < 4; f++) begin
                        active_bias[f] = committed_bias[f];
                        active_shift[f] = committed_shift[f];
                        active_relu[f] = committed_relu[f];
                        for (int tap = 0; tap < 9; tap++) begin
                            active_weights[f][tap] = committed_weights[f][tap];
                        end
                    end
                end
            end
            default: begin
            end
        endcase
    endfunction

    function automatic bit [7:0] finalize(int signed accumulator, int unsigned shift, bit relu);
        int signed shifted;
        shifted = (shift == 0) ? accumulator : (accumulator >>> shift);
        if (relu && (shifted < 0)) return 0;
        if (shifted < 0) return 0;
        if (shifted > 255) return 8'hff;
        return shifted[7:0];
    endfunction

    function void emit_expected_frame();
        axis_stream_item expected_tr;
        bit [31:0] packed_value;
        int signed accumulator;
        int unsigned row;
        int unsigned col;
        int unsigned tap;

        if (active_mode != MODE_VECTOR4) begin
            `uvm_error("PREDICTOR_MODE", $sformatf("dynamic vector predictor saw active mode %0d", active_mode))
            return;
        end

        for (int output_index = 0; output_index < IMAGE_PIXELS; output_index++) begin
            row = output_index / IMAGE_WIDTH;
            col = output_index % IMAGE_WIDTH;
            packed_value = '0;
            if ((row != 0) && (row != IMAGE_HEIGHT-1) && (col != 0) && (col != IMAGE_WIDTH-1)) begin
                for (int filter_index = 0; filter_index < 4; filter_index++) begin
                    accumulator = active_bias[filter_index];
                    tap = 0;
                    for (int kernel_row = -1; kernel_row <= 1; kernel_row++) begin
                        for (int kernel_col = -1; kernel_col <= 1; kernel_col++) begin
                            accumulator +=
                                pixels[(row + kernel_row) * IMAGE_WIDTH + (col + kernel_col)] *
                                active_weights[filter_index][tap];
                            tap++;
                        end
                    end
                    packed_value[filter_index*8 +: 8] = finalize(
                        accumulator,
                        active_shift[filter_index],
                        active_relu[filter_index]
                    );
                end
            end

            expected_tr = axis_stream_item::type_id::create(
                $sformatf("predicted_%0d", output_index),
                this
            );
            expected_tr.data = packed_value;
            expected_tr.keep = '1;
            expected_tr.last = (output_index == IMAGE_PIXELS - 1);
            expected_tr.beat_index = output_index;
            expected_ap.write(expected_tr);
        end
    endfunction

    function void write_predictor_input(axis_stream_item tr);
        if (!frame_armed) begin
            `uvm_error("PREDICTOR_ARM", "input beat accepted without a modeled start")
            return;
        end
        if (tr.beat_index >= IMAGE_PIXELS) begin
            `uvm_error("PREDICTOR_COUNT", $sformatf("input beat %0d exceeded frame", tr.beat_index))
            return;
        end
        pixels[tr.beat_index] = tr.data[7:0];
        input_count++;
        if (input_count == IMAGE_PIXELS) begin
            emit_expected_frame();
            input_count = 0;
            frame_armed = 1'b0;
        end
    endfunction
endclass
