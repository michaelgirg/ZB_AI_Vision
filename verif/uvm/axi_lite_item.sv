// Class: axi_lite_item
// Description:
//UVM transaction for one AXI4-Lite register read or write.

typedef enum int {
    AXI_LITE_READ,
    AXI_LITE_WRITE
} axi_lite_kind_e;

typedef enum int {
    AXI_WRITE_TOGETHER,
    AXI_WRITE_AW_FIRST,
    AXI_WRITE_W_FIRST
} axi_write_order_e;

class axi_lite_item extends uvm_sequence_item;

    rand axi_lite_kind_e kind;
    rand bit [AXI_ADDR_WIDTH-1:0] addr;
    rand bit [AXI_DATA_WIDTH-1:0] data;
    rand bit [(AXI_DATA_WIDTH/8)-1:0] strb;
    rand int unsigned aw_delay_cycles;
    rand int unsigned w_delay_cycles;
    rand int unsigned response_stall_cycles;

    bit [AXI_DATA_WIDTH-1:0] rdata;
    bit [1:0] resp;
    axi_write_order_e observed_write_order;

    constraint default_strobe_c {
        soft strb == '1;
    }

    constraint response_stall_c {
        response_stall_cycles inside {[0:4]};
    }

    constraint channel_delay_c {
        aw_delay_cycles inside {[0:8]};
        w_delay_cycles inside {[0:8]};
    }

    `uvm_object_utils_begin(axi_lite_item)
        `uvm_field_enum(axi_lite_kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_HEX)
        `uvm_field_int(data, UVM_HEX)
        `uvm_field_int(strb, UVM_HEX)
        `uvm_field_int(aw_delay_cycles, UVM_DEC)
        `uvm_field_int(w_delay_cycles, UVM_DEC)
        `uvm_field_int(response_stall_cycles, UVM_DEC)
        `uvm_field_int(rdata, UVM_HEX | UVM_NOPACK)
        `uvm_field_int(resp, UVM_HEX | UVM_NOPACK)
        `uvm_field_enum(axi_write_order_e, observed_write_order, UVM_DEFAULT | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "axi_lite_item");
        super.new(name);
        kind = AXI_LITE_WRITE;
        addr = '0;
        data = '0;
        strb = '1;
        aw_delay_cycles = 0;
        w_delay_cycles = 0;
        response_stall_cycles = 0;
        rdata = '0;
        resp = 2'b00;
        observed_write_order = AXI_WRITE_TOGETHER;
    endfunction

endclass
