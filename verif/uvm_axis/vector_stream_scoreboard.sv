`uvm_analysis_imp_decl(_source)
`uvm_analysis_imp_decl(_sink)

// Class: vector_stream_scoreboard
// Description:
//Pixel-accurate scoreboard for one 28x28 packed four-filter feature frame.

class vector_stream_scoreboard extends uvm_component;
    `uvm_component_utils(vector_stream_scoreboard)

    uvm_analysis_imp_source #(axis_stream_item, vector_stream_scoreboard) source_export;
    uvm_analysis_imp_sink #(axis_stream_item, vector_stream_scoreboard) sink_export;
    bit [AXIS_DATA_WIDTH-1:0] expected_words [0:IMAGE_PIXELS-1];
    string expected_mem = "generated/test_vectors/sample_000_conv4.mem";
    int unsigned source_count;
    int unsigned sink_count;
    int unsigned mismatch_count;
    bit complete;

    function new(string name = "vector_stream_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        source_export = new("source_export", this);
        sink_export = new("sink_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_config_db#(string)::get(this, "", "expected_mem", expected_mem));
        $readmemh(expected_mem, expected_words);
        source_count = 0;
        sink_count = 0;
        mismatch_count = 0;
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
        if (tr.keep != '1) begin
            mismatch_count++;
            `uvm_error("SOURCE_KEEP", $sformatf("source TKEEP invalid at %0d", tr.beat_index))
        end
        if (tr.last != (tr.beat_index == IMAGE_PIXELS - 1)) begin
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
        if (tr.data !== expected_words[tr.beat_index]) begin
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

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
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
