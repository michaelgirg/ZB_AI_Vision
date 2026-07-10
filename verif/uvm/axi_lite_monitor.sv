// Class: axi_lite_monitor
// Description:
//AXI4-Lite monitor that publishes completed read and write transactions.

class axi_lite_monitor extends uvm_component;

    `uvm_component_utils(axi_lite_monitor)

    virtual preprocess_if vif;
    uvm_analysis_port #(axi_lite_item) ap;

    function new(string name = "axi_lite_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "axi_lite_monitor could not get preprocess_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        fork
            collect_writes();
            collect_reads();
        join
    endtask

    task collect_writes();
        bit aw_seen;
        bit w_seen;
        bit [AXI_ADDR_WIDTH-1:0] addr_q;
        bit [AXI_DATA_WIDTH-1:0] data_q;
        bit [(AXI_DATA_WIDTH/8)-1:0] strb_q;
        axi_lite_item tr;

        aw_seen = 1'b0;
        w_seen = 1'b0;

        forever begin
            @(posedge vif.clk);
            if (!vif.rstn) begin
                aw_seen = 1'b0;
                w_seen = 1'b0;
            end else begin
                if (vif.s_axi_awvalid && vif.s_axi_awready) begin
                    aw_seen = 1'b1;
                    addr_q = vif.s_axi_awaddr;
                end

                if (vif.s_axi_wvalid && vif.s_axi_wready) begin
                    w_seen = 1'b1;
                    data_q = vif.s_axi_wdata;
                    strb_q = vif.s_axi_wstrb;
                end

                if (aw_seen && w_seen && vif.s_axi_bvalid && vif.s_axi_bready) begin
                    tr = axi_lite_item::type_id::create("mon_write_tr", this);
                    tr.kind = AXI_LITE_WRITE;
                    tr.addr = addr_q;
                    tr.data = data_q;
                    tr.strb = strb_q;
                    tr.resp = vif.s_axi_bresp;
                    ap.write(tr);
                    aw_seen = 1'b0;
                    w_seen = 1'b0;
                end
            end
        end
    endtask

    task collect_reads();
        bit ar_seen;
        bit [AXI_ADDR_WIDTH-1:0] addr_q;
        axi_lite_item tr;

        ar_seen = 1'b0;

        forever begin
            @(posedge vif.clk);
            if (!vif.rstn) begin
                ar_seen = 1'b0;
            end else begin
                if (vif.s_axi_arvalid && vif.s_axi_arready) begin
                    ar_seen = 1'b1;
                    addr_q = vif.s_axi_araddr;
                end

                if (ar_seen && vif.s_axi_rvalid && vif.s_axi_rready) begin
                    tr = axi_lite_item::type_id::create("mon_read_tr", this);
                    tr.kind = AXI_LITE_READ;
                    tr.addr = addr_q;
                    tr.rdata = vif.s_axi_rdata;
                    tr.resp = vif.s_axi_rresp;
                    ap.write(tr);
                    ar_seen = 1'b0;
                end
            end
        end
    endtask

endclass
