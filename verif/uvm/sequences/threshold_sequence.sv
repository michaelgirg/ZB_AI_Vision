// Class: threshold_sequence
// Description:
//UVM image sequence configured for threshold preprocessing.

class threshold_sequence extends preprocess_image_sequence;

    `uvm_object_utils(threshold_sequence)

    function new(string name = "threshold_sequence");
        super.new(name);
        preprocess_mode = MODE_THRESHOLD;
    endfunction

endclass
