// Class: axi_lite_driver
// Description:
//AXI4-Lite UVM driver for the preprocessing register interface.

class axi_lite_driver extends uvm_driver #(axi_lite_item);

    `uvm_component_utils(axi_lite_driver)

    virtual preprocess_if vif;

    function new(string name = "axi_lite_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "axi_lite_driver could not get preprocess_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axi_lite_item tr;

        init_bus();
        wait (vif.rstn === 1'b1);

        forever begin
            seq_item_port.get_next_item(tr);

            if (tr.kind == AXI_LITE_WRITE) begin
                drive_write(tr);
            end else begin
                drive_read(tr);
            end

            seq_item_port.item_done();
        end
    endtask

    task init_bus();
        vif.s_axi_awaddr <= '0;
        vif.s_axi_awprot <= '0;
        vif.s_axi_awvalid <= 1'b0;
        vif.s_axi_wdata <= '0;
        vif.s_axi_wstrb <= '0;
        vif.s_axi_wvalid <= 1'b0;
        vif.s_axi_bready <= 1'b0;
        vif.s_axi_araddr <= '0;
        vif.s_axi_arprot <= '0;
        vif.s_axi_arvalid <= 1'b0;
        vif.s_axi_rready <= 1'b0;
    endtask

    task drive_write(axi_lite_item tr);
        bit aw_done;
        bit w_done;

        aw_done = 1'b0;
        w_done = 1'b0;

        @(negedge vif.clk);
        vif.s_axi_awaddr <= tr.addr;
        vif.s_axi_awvalid <= 1'b1;
        vif.s_axi_wdata <= tr.data;
        vif.s_axi_wstrb <= tr.strb;
        vif.s_axi_wvalid <= 1'b1;
        vif.s_axi_bready <= 1'b0;

        while (!aw_done || !w_done) begin
            @(posedge vif.clk);
            if (vif.s_axi_awvalid && vif.s_axi_awready) begin
                aw_done = 1'b1;
            end
            if (vif.s_axi_wvalid && vif.s_axi_wready) begin
                w_done = 1'b1;
            end

            @(negedge vif.clk);
            if (aw_done) begin
                vif.s_axi_awvalid <= 1'b0;
            end
            if (w_done) begin
                vif.s_axi_wvalid <= 1'b0;
            end
        end

        repeat (tr.response_stall_cycles) @(posedge vif.clk);

        @(negedge vif.clk);
        vif.s_axi_bready <= 1'b1;

        while (vif.s_axi_bvalid !== 1'b1) begin
            @(posedge vif.clk);
        end

        tr.resp = vif.s_axi_bresp;

        @(negedge vif.clk);
        vif.s_axi_bready <= 1'b0;
        vif.s_axi_awaddr <= '0;
        vif.s_axi_wdata <= '0;
        vif.s_axi_wstrb <= '0;
    endtask

    task drive_read(axi_lite_item tr);
        @(negedge vif.clk);
        vif.s_axi_araddr <= tr.addr;
        vif.s_axi_arvalid <= 1'b1;
        vif.s_axi_rready <= 1'b0;

        do begin
            @(posedge vif.clk);
        end while (!(vif.s_axi_arvalid && vif.s_axi_arready));

        @(negedge vif.clk);
        vif.s_axi_arvalid <= 1'b0;

        repeat (tr.response_stall_cycles) @(posedge vif.clk);

        @(negedge vif.clk);
        vif.s_axi_rready <= 1'b1;

        while (vif.s_axi_rvalid !== 1'b1) begin
            @(posedge vif.clk);
        end

        tr.rdata = vif.s_axi_rdata;
        tr.resp = vif.s_axi_rresp;

        @(negedge vif.clk);
        vif.s_axi_rready <= 1'b0;
        vif.s_axi_araddr <= '0;
    endtask

endclass
