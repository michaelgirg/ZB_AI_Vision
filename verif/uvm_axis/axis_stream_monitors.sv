// Classes: axis_stream_input_monitor, axis_stream_output_monitor

class axis_stream_input_monitor extends uvm_component;
    `uvm_component_utils(axis_stream_input_monitor)
    virtual axis_stream_if vif;
    uvm_analysis_port #(axis_stream_item) ap;
    int unsigned beat_index;

    function new(string name = "axis_stream_input_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_stream_if)::get(this, "", "axis_vif", vif)) begin
            `uvm_fatal("NO_AXIS_VIF", "input monitor could not get axis_stream_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axis_stream_item tr;
        beat_index = 0;
        forever begin
            @(posedge vif.clk);
            if (!vif.rstn) begin
                beat_index = 0;
            end else if (vif.s_tvalid && vif.s_tready) begin
                tr = axis_stream_item::type_id::create("input_tr", this);
                tr.data = vif.s_tdata;
                tr.keep = vif.s_tkeep;
                tr.last = vif.s_tlast;
                tr.beat_index = beat_index;
                ap.write(tr);
                beat_index = tr.last ? 0 : (beat_index + 1);
            end
        end
    endtask
endclass

class axis_stream_output_monitor extends uvm_component;
    `uvm_component_utils(axis_stream_output_monitor)
    virtual axis_stream_if vif;
    uvm_analysis_port #(axis_stream_item) ap;
    int unsigned beat_index;
    int unsigned stall_cycles;

    function new(string name = "axis_stream_output_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_stream_if)::get(this, "", "axis_vif", vif)) begin
            `uvm_fatal("NO_AXIS_VIF", "output monitor could not get axis_stream_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axis_stream_item tr;
        beat_index = 0;
        stall_cycles = 0;
        forever begin
            @(posedge vif.clk);
            if (!vif.rstn) begin
                beat_index = 0;
                stall_cycles = 0;
            end else if (vif.m_tvalid && !vif.m_tready) begin
                stall_cycles++;
            end else if (vif.m_tvalid && vif.m_tready) begin
                tr = axis_stream_item::type_id::create("output_tr", this);
                tr.data = vif.m_tdata;
                tr.keep = vif.m_tkeep;
                tr.last = vif.m_tlast;
                tr.beat_index = beat_index;
                tr.stall_cycles = stall_cycles;
                ap.write(tr);
                beat_index = tr.last ? 0 : (beat_index + 1);
                stall_cycles = 0;
            end else begin
                stall_cycles = 0;
            end
        end
    endtask
endclass
