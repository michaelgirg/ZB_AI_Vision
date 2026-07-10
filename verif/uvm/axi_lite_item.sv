// Class: axi_lite_item
// Description:
//UVM transaction for one AXI4-Lite register read or write.

typedef enum int {
    AXI_LITE_READ,
    AXI_LITE_WRITE
} axi_lite_kind_e;

class axi_lite_item extends uvm_sequence_item;

    rand axi_lite_kind_e kind;
    rand bit [AXI_ADDR_WIDTH-1:0] addr;
    rand bit [AXI_DATA_WIDTH-1:0] data;
    rand bit [(AXI_DATA_WIDTH/8)-1:0] strb;
    rand int unsigned response_stall_cycles;

    bit [AXI_DATA_WIDTH-1:0] rdata;
    bit [1:0] resp;

    constraint default_strobe_c {
        strb == '1;
    }

    constraint response_stall_c {
        response_stall_cycles inside {[0:4]};
    }

    `uvm_object_utils_begin(axi_lite_item)
        `uvm_field_enum(axi_lite_kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_HEX)
        `uvm_field_int(data, UVM_HEX)
        `uvm_field_int(strb, UVM_HEX)
        `uvm_field_int(response_stall_cycles, UVM_DEC)
        `uvm_field_int(rdata, UVM_HEX | UVM_NOPACK)
        `uvm_field_int(resp, UVM_HEX | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "axi_lite_item");
        super.new(name);
        kind = AXI_LITE_WRITE;
        addr = '0;
        data = '0;
        strb = '1;
        response_stall_cycles = 0;
        rdata = '0;
        resp = 2'b00;
    endfunction

endclass
