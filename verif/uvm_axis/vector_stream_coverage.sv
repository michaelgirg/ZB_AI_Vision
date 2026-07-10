// Classes: vector_stream_coverage, vector_control_coverage

class vector_stream_coverage extends uvm_subscriber #(axis_stream_item);
    `uvm_component_utils(vector_stream_coverage)

    covergroup output_cg with function sample(
        bit [31:0] data,
        bit [3:0] keep,
        bit last,
        int unsigned stall_cycles,
        bit border
    );
        option.per_instance = 1;
        cp_keep: coverpoint keep { bins full = {4'hf}; illegal_bins other = default; }
        cp_last: coverpoint last;
        cp_stall: coverpoint stall_cycles {
            bins none = {0};
            bins short = {[1:2]};
            bins long = {[3:65535]};
        }
        cp_border: coverpoint border;
        cp_ch0: coverpoint data[7:0] {
            bins zero = {0}; bins active = {[1:254]}; bins saturated = {255};
        }
        cp_ch1: coverpoint data[15:8] {
            bins zero = {0}; bins active = {[1:254]}; bins saturated = {255};
        }
        cp_ch2: coverpoint data[23:16] {
            bins zero = {0}; bins active = {[1:254]}; bins saturated = {255};
        }
        cp_ch3: coverpoint data[31:24] {
            bins zero = {0}; bins active = {[1:254]}; bins saturated = {255};
        }
        border_stall_cross: cross cp_border, cp_stall;
    endgroup

    function new(string name = "vector_stream_coverage", uvm_component parent = null);
        super.new(name, parent);
        output_cg = new();
    endfunction

    function void write(axis_stream_item t);
        int unsigned row;
        int unsigned col;
        bit border;
        row = t.beat_index / IMAGE_WIDTH;
        col = t.beat_index % IMAGE_WIDTH;
        border = (row == 0) || (row == IMAGE_HEIGHT - 1) ||
                 (col == 0) || (col == IMAGE_WIDTH - 1);
        output_cg.sample(t.data, t.keep, t.last, t.stall_cycles, border);
    endfunction
endclass

class vector_control_coverage extends uvm_subscriber #(axi_lite_item);
    `uvm_component_utils(vector_control_coverage)

    covergroup control_cg with function sample(
        axi_lite_kind_e kind,
        bit [7:0] addr,
        bit [31:0] data
    );
        option.per_instance = 1;
        cp_kind: coverpoint kind {
            bins read = {AXI_LITE_READ};
            bins write = {AXI_LITE_WRITE};
        }
        cp_write_addr: coverpoint addr iff (kind == AXI_LITE_WRITE) {
            bins ctrl = {ADDR_CTRL};
            bins mode = {ADDR_MODE};
            bins cfg_index = {ADDR_VECTOR_CFG_INDEX};
            bins cfg_data = {ADDR_VECTOR_CFG_DATA};
            bins cfg_commit = {ADDR_VECTOR_CFG_COMMIT};
        }
        cp_read_addr: coverpoint addr iff (kind == AXI_LITE_READ) {
            bins cfg_version = {ADDR_VECTOR_CFG_VERSION};
            bins status = {ADDR_STATUS};
            bins cfg_data = {ADDR_VECTOR_CFG_DATA};
        }
        cp_filter: coverpoint data[5:4] iff (
            (kind == AXI_LITE_WRITE) && (addr == ADDR_VECTOR_CFG_INDEX)
        ) {
            bins filters[] = {[0:3]};
        }
        cp_entry: coverpoint data[3:0] iff (
            (kind == AXI_LITE_WRITE) && (addr == ADDR_VECTOR_CFG_INDEX)
        ) {
            bins weights[] = {[0:8]};
            bins bias = {9};
            bins shift_relu = {10};
        }
        cp_mode: coverpoint data[1:0] iff (
            (kind == AXI_LITE_WRITE) && (addr == ADDR_MODE)
        ) {
            bins vector4 = {MODE_VECTOR4};
        }
    endgroup

    function new(string name = "vector_control_coverage", uvm_component parent = null);
        super.new(name, parent);
        control_cg = new();
    endfunction

    function void write(axi_lite_item t);
        bit [31:0] sampled_data;
        sampled_data = (t.kind == AXI_LITE_WRITE) ? t.data : t.rdata;
        control_cg.sample(t.kind, t.addr, sampled_data);
    endfunction
endclass
