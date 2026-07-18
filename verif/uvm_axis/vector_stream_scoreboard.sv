`uvm_analysis_imp_decl(_source)
`uvm_analysis_imp_decl(_sink)
`uvm_analysis_imp_decl(_expected)

// Class: vector_stream_scoreboard
// Description:
//Pixel-accurate scoreboard for one 28x28 packed four-filter feature frame.

class vector_stream_scoreboard extends uvm_component;
    `uvm_component_utils(vector_stream_scoreboard)

    uvm_analysis_imp_source #(axis_stream_item, vector_stream_scoreboard) source_export;
    uvm_analysis_imp_sink #(axis_stream_item, vector_stream_scoreboard) sink_export;
    uvm_analysis_imp_expected #(axis_stream_item, vector_stream_scoreboard) expected_export;
    bit [AXIS_DATA_WIDTH-1:0] expected_words [0:IMAGE_PIXELS-1];
    bit [AXIS_DATA_WIDTH-1:0] predicted_words [0:IMAGE_PIXELS-1];
    bit [AXIS_DATA_WIDTH-1:0] actual_words [0:IMAGE_PIXELS-1];
    string expected_mem = "generated/test_vectors/sample_000_conv4.mem";
    int unsigned source_count;
    int unsigned sink_count;
    int unsigned mismatch_count;
    int unsigned expected_count;
    bit complete;
    bit enable_frame_check = 1'b1;
    bit enable_fixed_file_check = 1'b1;
    bit enable_dynamic_check = 1'b1;
    bit allow_malformed_source = 1'b0;

    function new(string name = "vector_stream_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        source_export = new("source_export", this);
        sink_export = new("sink_export", this);
        expected_export = new("expected_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_config_db#(string)::get(this, "", "expected_mem", expected_mem));
        void'(uvm_config_db#(bit)::get(this, "", "enable_frame_check", enable_frame_check));
        void'(uvm_config_db#(bit)::get(this, "", "enable_fixed_file_check", enable_fixed_file_check));
        void'(uvm_config_db#(bit)::get(this, "", "enable_dynamic_check", enable_dynamic_check));
        void'(uvm_config_db#(bit)::get(this, "", "allow_malformed_source", allow_malformed_source));
        $readmemh(expected_mem, expected_words);
        source_count = 0;
        sink_count = 0;
        mismatch_count = 0;
        expected_count = 0;
        complete = 1'b0;
        `uvm_info("SCOREBOARD", $sformatf("loaded %s", expected_mem), UVM_LOW)
    endfunction

    function void write_source(axis_stream_item tr);
        if (tr.beat_index >= IMAGE_PIXELS) begin
            mismatch_count++;
            `uvm_error("SOURCE_COUNT", $sformatf("extra source beat %0d", tr.beat_index))
            return;
        end
        if (tr.data[AXIS_DATA_WIDTH-1:8] != 0) begin
            mismatch_count++;
            `uvm_error("SOURCE_DATA", $sformatf("upper source bits nonzero at %0d", tr.beat_index))
        end
        if (!allow_malformed_source && (tr.keep != '1)) begin
            mismatch_count++;
            `uvm_error("SOURCE_KEEP", $sformatf("source TKEEP invalid at %0d", tr.beat_index))
        end
        if (!allow_malformed_source &&
            (tr.last != (tr.beat_index == IMAGE_PIXELS - 1))) begin
            mismatch_count++;
            `uvm_error("SOURCE_LAST", $sformatf("source TLAST invalid at %0d", tr.beat_index))
        end
        source_count++;
    endfunction

    function void write_sink(axis_stream_item tr);
        if (tr.beat_index >= IMAGE_PIXELS) begin
            mismatch_count++;
            `uvm_error("SINK_COUNT", $sformatf("extra sink beat %0d", tr.beat_index))
            return;
        end
        actual_words[tr.beat_index] = tr.data;
        if (enable_fixed_file_check && (tr.data !== expected_words[tr.beat_index])) begin
            mismatch_count++;
            `uvm_error(
                "PIXEL_MISMATCH",
                $sformatf(
                    "beat=%0d actual=%08h expected=%08h",
                    tr.beat_index,
                    tr.data,
                    expected_words[tr.beat_index]
                )
            )
        end
        if (tr.keep != '1) begin
            mismatch_count++;
            `uvm_error("SINK_KEEP", $sformatf("sink TKEEP invalid at %0d", tr.beat_index))
        end
        if (tr.last != (tr.beat_index == IMAGE_PIXELS - 1)) begin
            mismatch_count++;
            `uvm_error("SINK_LAST", $sformatf("sink TLAST invalid at %0d", tr.beat_index))
        end
        sink_count++;
        if (tr.beat_index == IMAGE_PIXELS - 1) begin
            complete = 1'b1;
        end
    endfunction

    function void write_expected(axis_stream_item tr);
        if (tr.beat_index >= IMAGE_PIXELS) begin
            mismatch_count++;
            `uvm_error("EXPECTED_COUNT", $sformatf("extra predicted beat %0d", tr.beat_index))
            return;
        end
        predicted_words[tr.beat_index] = tr.data;
        expected_count++;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (!enable_frame_check) begin
            `uvm_info("VECTOR_SCOREBOARD", "frame checking disabled for control-only test", UVM_LOW)
            return;
        end
        if (enable_dynamic_check) begin
            if (expected_count != IMAGE_PIXELS) begin
                mismatch_count++;
                `uvm_error(
                    "PREDICTOR_COUNT",
                    $sformatf("predicted=%0d/%0d", expected_count, IMAGE_PIXELS)
                )
            end else begin
                for (int beat_index = 0; beat_index < IMAGE_PIXELS; beat_index++) begin
                    if (actual_words[beat_index] !== predicted_words[beat_index]) begin
                        mismatch_count++;
                        `uvm_error(
                            "PREDICTOR_MISMATCH",
                            $sformatf(
                                "beat=%0d actual=%08h predicted=%08h",
                                beat_index,
                                actual_words[beat_index],
                                predicted_words[beat_index]
                            )
                        )
                    end
                end
            end
        end
        if ((source_count != IMAGE_PIXELS) ||
            (sink_count != IMAGE_PIXELS) ||
            (mismatch_count != 0)) begin
            `uvm_error(
                "VECTOR_SCOREBOARD",
                $sformatf(
                    "source=%0d/%0d sink=%0d/%0d mismatches=%0d",
                    source_count,
                    IMAGE_PIXELS,
                    sink_count,
                    IMAGE_PIXELS,
                    mismatch_count
                )
            )
        end else begin
            `uvm_info(
                "VECTOR_SCOREBOARD",
                $sformatf("PASS: matched %0d packed vector outputs", sink_count),
                UVM_NONE
            )
        end
    endfunction
endclass
