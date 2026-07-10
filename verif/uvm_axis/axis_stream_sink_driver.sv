// Class: axis_stream_sink_driver
// Description:
//Generates deterministic-seed randomized output backpressure.

class axis_stream_sink_driver extends uvm_component;

    `uvm_component_utils(axis_stream_sink_driver)
    virtual axis_stream_if vif;
    int unsigned ready_low_percent = 20;

    function new(string name = "axis_stream_sink_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_stream_if)::get(this, "", "axis_vif", vif)) begin
            `uvm_fatal("NO_AXIS_VIF", "sink driver could not get axis_stream_if")
        end
        void'(uvm_config_db#(int unsigned)::get(this, "", "ready_low_percent", ready_low_percent));
        if (ready_low_percent > 95) begin
            `uvm_fatal("BAD_READY_PCT", "ready_low_percent must be <= 95")
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.m_tready <= 1'b0;
        forever begin
            @(negedge vif.clk);
            if (!vif.rstn) begin
                vif.m_tready <= 1'b0;
            end else begin
                vif.m_tready <= ($urandom_range(0, 99) >= ready_low_percent);
            end
        end
    endtask

endclass
