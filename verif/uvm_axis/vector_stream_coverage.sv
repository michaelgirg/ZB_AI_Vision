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
    virtual preprocess_if ctrl_vif;

    covergroup control_cg with function sample(
        axi_lite_kind_e kind,
        bit [7:0] addr,
        bit [31:0] data,
        bit [3:0] strb,
        bit [1:0] resp,
        axi_write_order_e write_order,
        bit irq
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
            bins error_status = {ADDR_ERROR_STATUS};
            bins int_status = {ADDR_INT_STATUS};
            bins int_enable = {ADDR_INT_ENABLE};
            bins perf_control = {ADDR_PERF_CONTROL};
        }
        cp_read_addr: coverpoint addr iff (kind == AXI_LITE_READ) {
            bins cfg_version = {ADDR_VECTOR_CFG_VERSION};
            bins status = {ADDR_STATUS};
            bins cfg_data = {ADDR_VECTOR_CFG_DATA};
            bins identity[] = {ADDR_IP_ID, ADDR_IP_VERSION, ADDR_CAPABILITIES};
            bins counters[] = {
                ADDR_FRAME_COUNT,
                ADDR_ERROR_COUNT,
                ADDR_INPUT_STALL_CYCLES,
                ADDR_OUTPUT_STALL_CYCLES
            };
            bins diagnostics[] = {ADDR_ERROR_STATUS, ADDR_INT_STATUS, ADDR_INT_ENABLE};
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
        cp_strb: coverpoint strb iff (kind == AXI_LITE_WRITE) {
            bins patterns[] = {[0:15]};
        }
        cp_resp: coverpoint resp {
            bins okay = {2'b00};
            bins slverr = {2'b10};
            illegal_bins other = default;
        }
        cp_write_order: coverpoint write_order iff (kind == AXI_LITE_WRITE) {
            bins together = {AXI_WRITE_TOGETHER};
            bins aw_first = {AXI_WRITE_AW_FIRST};
            bins w_first = {AXI_WRITE_W_FIRST};
        }
        cp_error_status: coverpoint data[2:0] iff (
            (kind == AXI_LITE_READ) && (addr == ADDR_ERROR_STATUS)
        ) {
            bins clear = {3'b000};
            bins packet = {3'b001};
            bins rejected_write = {3'b010};
            bins rejected_read = {3'b100};
            bins combined = {3'b011, 3'b101, 3'b110, 3'b111};
        }
        cp_int_status: coverpoint data[2:0] iff (
            (kind == AXI_LITE_READ) && (addr == ADDR_INT_STATUS)
        ) {
            bins clear = {3'b000};
            bins done = {3'b001};
            bins packet_error = {3'b010};
            bins access_error = {3'b100};
            bins combined = {3'b011, 3'b101, 3'b110, 3'b111};
        }
        cp_int_enable: coverpoint data[2:0] iff (
            (kind == AXI_LITE_WRITE) && (addr == ADDR_INT_ENABLE)
        ) {
            bins disabled = {3'b000};
            bins individual[] = {3'b001, 3'b010, 3'b100};
            bins all = {3'b111};
            bins mixed[] = {3'b011, 3'b101, 3'b110};
        }
        cp_error_count: coverpoint data iff (
            (kind == AXI_LITE_READ) && (addr == ADDR_ERROR_COUNT)
        ) {
            bins zero = {0};
            bins one = {1};
            bins multiple = {[2:32'hffff_fffe]};
            // Reaching 0xffff_ffff requires 2^32 production error events.
            // Dynamic simulation covers zero/one/multiple; saturation remains
            // an assertion/formal obligation in production_diag_sva.
            ignore_bins saturated = {32'hffff_ffff};
        }
        cp_irq: coverpoint irq;
        order_response_cross: cross cp_write_order, cp_resp;
        irq_response_cross: cross cp_irq, cp_resp;
    endgroup

    function new(string name = "vector_control_coverage", uvm_component parent = null);
        super.new(name, parent);
        control_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "vector control coverage could not get preprocess_if")
        end
    endfunction

    function void write(axi_lite_item t);
        bit [31:0] sampled_data;
        sampled_data = (t.kind == AXI_LITE_WRITE) ? t.data : t.rdata;
        control_cg.sample(
            t.kind,
            t.addr,
            sampled_data,
            t.strb,
            t.resp,
            t.observed_write_order,
            ctrl_vif.irq
        );
    endfunction
endclass
