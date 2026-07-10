// Class: preprocess_coverage_uvm
// Description:
//UVM coverage subscriber for AXI-Lite register traffic.

class preprocess_coverage_uvm extends uvm_subscriber #(axi_lite_item);

    `uvm_component_utils(preprocess_coverage_uvm)

    axi_lite_kind_e cov_kind;
    bit [AXI_ADDR_WIDTH-1:0] cov_addr;
    bit [7:0] cov_data_low;

    covergroup axi_lite_cg;
        option.per_instance = 1;

        cp_kind: coverpoint cov_kind {
            bins read = {AXI_LITE_READ};
            bins write = {AXI_LITE_WRITE};
        }

        cp_write_addr: coverpoint cov_addr iff (cov_kind == AXI_LITE_WRITE) {
            bins ctrl = {ADDR_CTRL};
            bins threshold = {ADDR_THRESHOLD};
            bins input_addr = {ADDR_INPUT_ADDR};
            bins input_wdata = {ADDR_INPUT_WDATA};
            bins input_wmask = {ADDR_INPUT_WMASK};
            bins output_addr = {ADDR_OUTPUT_ADDR};
            bins mode = {ADDR_MODE};
        }

        cp_read_addr: coverpoint cov_addr iff (cov_kind == AXI_LITE_READ) {
            bins status = {ADDR_STATUS};
            bins image_pixels = {ADDR_IMAGE_PIXELS};
            bins pixels_per_cycle = {ADDR_PIXELS_PER_CYCLE};
            bins processing_cycles = {ADDR_PROCESSING_CYCLES};
            bins output_rdata = {ADDR_OUTPUT_RDATA};
            bins mode = {ADDR_MODE};
        }

        cp_mode_write: coverpoint cov_data_low[1:0]
            iff (cov_kind == AXI_LITE_WRITE && cov_addr == ADDR_MODE) {
            bins threshold = {2'd0};
            bins sobel = {2'd1};
            bins invalid[] = {[2:3]};
        }

        cp_threshold_write: coverpoint cov_data_low
            iff (cov_kind == AXI_LITE_WRITE && cov_addr == ADDR_THRESHOLD) {
            bins zero = {8'd0};
            bins one = {8'd1};
            bins mid_low = {8'd127};
            bins mid = {8'd128};
            bins high = {8'd254};
            bins max = {8'd255};
        }

        cp_ctrl_write: coverpoint cov_data_low[1:0]
            iff (cov_kind == AXI_LITE_WRITE && cov_addr == ADDR_CTRL) {
            bins start_only = {2'b01};
            bins clear_only = {2'b10};
            bins start_and_clear = {2'b11};
        }
    endgroup

    function new(string name = "preprocess_coverage_uvm", uvm_component parent = null);
        super.new(name, parent);
        axi_lite_cg = new();
    endfunction

    function void write(axi_lite_item t);
        cov_kind = t.kind;
        cov_addr = t.addr;
        cov_data_low = t.data[7:0];
        axi_lite_cg.sample();
    endfunction

endclass
