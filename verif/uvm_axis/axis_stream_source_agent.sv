// Class: axis_stream_source_agent

class axis_stream_source_agent extends uvm_agent;

    `uvm_component_utils(axis_stream_source_agent)
    axis_stream_sequencer sequencer;
    axis_stream_source_driver driver;

    function new(string name = "axis_stream_source_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = axis_stream_sequencer::type_id::create("sequencer", this);
        driver = axis_stream_source_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
