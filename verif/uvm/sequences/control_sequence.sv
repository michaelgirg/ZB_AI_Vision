// Class: control_sequence
// Description:
//UVM sequence for register control coverage.

class control_sequence extends uvm_sequence #(axi_lite_item);

    `uvm_object_utils(control_sequence)

    int threshold_values [6] = '{0, 1, 127, 128, 254, 255};
    int mode_values [4] = '{0, 1, 2, 3};

    function new(string name = "control_sequence");
        super.new(name);
    endfunction

    task body();
        bit [AXI_DATA_WIDTH-1:0] read_value;

        foreach (threshold_values[index]) begin
            axi_write(ADDR_THRESHOLD, threshold_values[index]);
            axi_read(ADDR_THRESHOLD, read_value);
            if (read_value[7:0] != threshold_values[index][7:0]) begin
                `uvm_error("THRESHOLD", "Threshold readback mismatch")
            end
        end

        foreach (mode_values[index]) begin
            axi_write(ADDR_MODE, mode_values[index]);
            axi_read(ADDR_MODE, read_value);
        end

        axi_write(ADDR_CTRL, 2);
        axi_write(ADDR_CTRL, 3);
    endtask

    task axi_write(input bit [AXI_ADDR_WIDTH-1:0] addr, input bit [AXI_DATA_WIDTH-1:0] data);
        axi_lite_item tr;

        tr = axi_lite_item::type_id::create("control_write_tr");
        tr.kind = AXI_LITE_WRITE;
        tr.addr = addr;
        tr.data = data;
        tr.strb = '1;
        start_item(tr);
        finish_item(tr);
    endtask

    task axi_read(input bit [AXI_ADDR_WIDTH-1:0] addr, output bit [AXI_DATA_WIDTH-1:0] data);
        axi_lite_item tr;

        tr = axi_lite_item::type_id::create("control_read_tr");
        tr.kind = AXI_LITE_READ;
        tr.addr = addr;
        start_item(tr);
        finish_item(tr);
        data = tr.rdata;
    endtask

endclass
