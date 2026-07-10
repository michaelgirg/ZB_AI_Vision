// Class: axis_stream_item
// Description:
//One monitored or driven AXI4-Stream beat.

class axis_stream_item extends uvm_sequence_item;

    rand bit [AXIS_DATA_WIDTH-1:0] data;
    rand bit [AXIS_KEEP_WIDTH-1:0] keep;
    rand bit last;
    rand int unsigned gap_cycles;
    int unsigned beat_index;
    int unsigned stall_cycles;

    constraint legal_keep_c { keep == '1; }
    constraint gap_c { gap_cycles inside {[0:2]}; }

    `uvm_object_utils_begin(axis_stream_item)
        `uvm_field_int(data, UVM_HEX)
        `uvm_field_int(keep, UVM_HEX)
        `uvm_field_int(last, UVM_BIN)
        `uvm_field_int(gap_cycles, UVM_DEC)
        `uvm_field_int(beat_index, UVM_DEC | UVM_NOPACK)
        `uvm_field_int(stall_cycles, UVM_DEC | UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "axis_stream_item");
        super.new(name);
        keep = '1;
    endfunction

endclass
