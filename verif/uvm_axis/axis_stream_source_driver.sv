// Class: axis_stream_source_driver
// Description:
//Drives image pixels into the DUT AXI4-Stream slave interface.

class axis_stream_source_driver extends uvm_driver #(axis_stream_item);

    `uvm_component_utils(axis_stream_source_driver)
    virtual axis_stream_if vif;

    function new(string name = "axis_stream_source_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axis_stream_if)::get(this, "", "axis_vif", vif)) begin
            `uvm_fatal("NO_AXIS_VIF", "source driver could not get axis_stream_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axis_stream_item tr;
        vif.s_tdata <= '0;
        vif.s_tkeep <= '0;
        vif.s_tvalid <= 1'b0;
        vif.s_tlast <= 1'b0;
        wait (vif.rstn === 1'b1);

        forever begin
            bit transfer_aborted;
            seq_item_port.get_next_item(tr);
            transfer_aborted = 1'b0;
            repeat (tr.gap_cycles) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.s_tdata <= tr.data;
            vif.s_tkeep <= tr.keep;
            vif.s_tvalid <= 1'b1;
            vif.s_tlast <= tr.last;
            do begin
                @(posedge vif.clk);
                if (!vif.rstn) begin
                    transfer_aborted = 1'b1;
                    break;
                end
            end while (!(vif.s_tvalid && vif.s_tready));
            @(negedge vif.clk);
            vif.s_tvalid <= 1'b0;
            vif.s_tlast <= 1'b0;
            vif.s_tdata <= '0;
            vif.s_tkeep <= '0;
            if (transfer_aborted) begin
                `uvm_info("SOURCE_RESET", "aborted an in-flight source beat on reset", UVM_LOW)
            end
            seq_item_port.item_done();
            if (!vif.rstn) begin
                wait (vif.rstn === 1'b1);
            end
        end
    endtask

endclass
