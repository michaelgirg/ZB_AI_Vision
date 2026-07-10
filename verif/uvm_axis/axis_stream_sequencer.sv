// Class: axis_stream_sequencer

class axis_stream_sequencer extends uvm_sequencer #(axis_stream_item);
    `uvm_component_utils(axis_stream_sequencer)

    function new(string name = "axis_stream_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
