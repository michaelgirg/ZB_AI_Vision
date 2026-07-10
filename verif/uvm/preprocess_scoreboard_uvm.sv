// Class: preprocess_scoreboard_uvm
// Description:
//UVM scoreboard that compares output register reads against golden pixels.

class preprocess_scoreboard_uvm extends uvm_component;

    `uvm_component_utils(preprocess_scoreboard_uvm)

    uvm_analysis_imp #(axi_lite_item, preprocess_scoreboard_uvm) analysis_export;

    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
    bit enable_pixel_compare = 1'b1;
    bit [DATA_WIDTH-1:0] expected_pixels [0:IMAGE_PIXELS-1];
    int output_addr;
    int compare_count;
    int mismatch_count;

    function new(string name = "preprocess_scoreboard_uvm", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        void'(uvm_config_db#(string)::get(this, "", "expected_mem_path", expected_mem_path));
        void'(uvm_config_db#(bit)::get(this, "", "enable_pixel_compare", enable_pixel_compare));
        $readmemh(expected_mem_path, expected_pixels);
        `uvm_info("SCOREBOARD", $sformatf("Loaded expected MEM: %s", expected_mem_path), UVM_LOW)
    endfunction

    function void write(axi_lite_item tr);
        if (!enable_pixel_compare) begin
            return;
        end

        if (tr.kind == AXI_LITE_WRITE && tr.addr == ADDR_OUTPUT_ADDR) begin
            output_addr = tr.data;
        end

        if (tr.kind == AXI_LITE_READ && tr.addr == ADDR_OUTPUT_RDATA) begin
            compare_count++;
            if (tr.rdata[DATA_WIDTH-1:0] !== expected_pixels[output_addr]) begin
                mismatch_count++;
                `uvm_error(
                    "PIXEL_MISMATCH",
                    $sformatf(
                        "Pixel %0d actual=0x%02h expected=0x%02h",
                        output_addr,
                        tr.rdata[DATA_WIDTH-1:0],
                        expected_pixels[output_addr]
                    )
                )
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (!enable_pixel_compare) begin
            `uvm_info("SCOREBOARD", "Pixel comparison disabled for control-only test.", UVM_LOW)
            return;
        end

        if (compare_count != IMAGE_PIXELS) begin
            `uvm_error(
                "SCOREBOARD",
                $sformatf("Compared %0d output pixel(s), expected %0d.", compare_count, IMAGE_PIXELS)
            )
        end

        if (mismatch_count != 0) begin
            `uvm_error("SCOREBOARD", $sformatf("Found %0d mismatch(es).", mismatch_count))
        end else begin
            `uvm_info(
                "SCOREBOARD",
                $sformatf("Matched %0d output pixel read(s).", compare_count),
                UVM_LOW
            )
        end
    endfunction

endclass
