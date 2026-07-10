// Class: random_control_sequence
// Description:
//Small randomized legal AXI-Lite register sequence.

class random_control_sequence extends control_sequence;

    `uvm_object_utils(random_control_sequence)

    function new(string name = "random_control_sequence");
        super.new(name);
    endfunction

    task body();
        bit [AXI_DATA_WIDTH-1:0] read_value;
        int unsigned choice;

        repeat (32) begin
            choice = $urandom_range(0, 3);
            unique case (choice)
                0: axi_write(ADDR_THRESHOLD, $urandom_range(0, 255));
                1: axi_write(ADDR_MODE, $urandom_range(0, 3));
                2: axi_read(ADDR_STATUS, read_value);
                default: axi_read(ADDR_MODE, read_value);
            endcase
        end
    endtask

endclass
