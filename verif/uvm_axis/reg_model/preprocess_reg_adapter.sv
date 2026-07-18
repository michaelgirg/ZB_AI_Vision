class preprocess_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(preprocess_reg_adapter)

    function new(string name = "preprocess_reg_adapter");
        super.new(name);
        supports_byte_enable = 1;
        provides_responses = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        axi_lite_item tr;
        tr = axi_lite_item::type_id::create("ral_tr");
        tr.kind = (rw.kind == UVM_WRITE) ? AXI_LITE_WRITE : AXI_LITE_READ;
        tr.addr = rw.addr[AXI_ADDR_WIDTH-1:0];
        tr.data = rw.data[AXI_DATA_WIDTH-1:0];
        tr.strb = (rw.kind == UVM_WRITE) ? rw.byte_en[3:0] : '0;
        if ((rw.kind == UVM_WRITE) && (tr.strb == '0)) begin
            tr.strb = '1;
        end
        tr.aw_delay_cycles = 0;
        tr.w_delay_cycles = 0;
        tr.response_stall_cycles = 0;
        return tr;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        axi_lite_item tr;
        if (!$cast(tr, bus_item)) begin
            `uvm_fatal("RAL_CAST", "preprocess_reg_adapter received the wrong transaction type")
        end
        rw.kind = (tr.kind == AXI_LITE_WRITE) ? UVM_WRITE : UVM_READ;
        rw.addr = tr.addr;
        rw.data = (tr.kind == AXI_LITE_WRITE) ? tr.data : tr.rdata;
        rw.byte_en = tr.strb;
        rw.status = (tr.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
    endfunction
endclass
